import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "browser")

final class BrowserRuntime: CapabilityRuntime {
    var capabilityName: String { "browser" }
    private let connection = CDPConnection()
    private let lock = NSLock()
    private var _chromeProcess: Process?
    private var _userDataDir: String?
    var sessionStore: BrowserSessionStore?
    var workspaceId: String?
    private var _isFallbackMode = false
    private let fallbackEngine = WebBrowserEngine()
    private var _lastNavigatedURL: String?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _chromeProcess != nil || _isFallbackMode
    }

    var isFallbackMode: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isFallbackMode
    }

    private let chromePath: String = {
        let paths = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/usr/bin/google-chrome",
            "/usr/bin/chromium-browser"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return paths[0]
    }()

    private let defaultPort = 9222

    // MARK: - Lifecycle

    func launch(context: ExecutionContext, headless: Bool = false, userDataDir: String? = nil) async {
        lock.lock()
        let alreadyRunning = _chromeProcess != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        do {
            let port = findAvailablePort()
            let resolvedDataDir = userDataDir ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("orbit-chrome-\(UUID().uuidString.prefix(8))").path

            try FileManager.default.createDirectory(atPath: resolvedDataDir, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: chromePath)
            process.arguments = buildChromeArgs(port: port, headless: headless, userDataDir: resolvedDataDir)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            lock.lock()
            _chromeProcess = process
            _userDataDir = resolvedDataDir
            lock.unlock()

            try await waitForChrome(port: port)
            let pageURL = try await createPage(port: port)
            try await connection.connect(to: pageURL)
            if let store = sessionStore {
                try? await restoreSession(from: store, workspaceId: workspaceId, context: context)
            }
            log.notice("Browser runtime launched (port \(port))")
        } catch {
            log.warning("Chrome unavailable (\(error.localizedDescription)). Using curl-based fallback engine.")
            lock.lock()
            _isFallbackMode = true
            lock.unlock()
        }
    }

    func close(context: ExecutionContext) {
        let c = connection
        Task { await c.disconnect() }
        lock.lock()
        _chromeProcess?.terminate()
        _chromeProcess = nil
        let dir = _userDataDir
        _userDataDir = nil
        lock.unlock()
        if let dir = dir {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    // MARK: - Navigation

    func navigate(url: String, context: ExecutionContext) async throws -> String {
        lock.lock()
        _lastNavigatedURL = url
        lock.unlock()
        if isFallbackMode {
            do {
                let text = try await fallbackEngine.fetchPage(url: url)
                return "Fetched \(url) using fallback engine. Extracted text:\n\(text.prefix(5000))"
            } catch {
                return "Fallback fetch for \(url) returned: \(error.localizedDescription)"
            }
        }
        _ = try await connection.send(method: "Page.enable")
        let result = try await connection.send(method: "Page.navigate", params: ["url": url])
        if let errorText = result["errorText"] as? String {
            throw OrbitError.toolCallFailed("Navigation failed: \(errorText)")
        }
        try await waitForPageLoad()
        if let store = sessionStore {
            try? await saveSession(to: store, workspaceId: workspaceId, context: context)
        }
        return "Navigated to \(url). Current URL: \(try await getCurrentURL(context: context))"
    }

    func getCurrentURL(context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "(fallback mode — no actual URL)" }
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": "window.location.href",
            "returnByValue": true
        ])
        return extractJSResult(from: result) ?? "unknown"
    }

    func getTitle(context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "(fallback mode)" }
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": "document.title",
            "returnByValue": true
        ])
        return extractJSResult(from: result) ?? ""
    }

    // MARK: - Interaction

    func click(selector: String, context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "Click is not available in fallback mode (Chrome not running)." }
        let js = """
        (() => {
            const el = document.querySelector('\(escapeJS(selector))');
            if (!el) return null;
            const rect = el.getBoundingClientRect();
            return { x: rect.x + rect.width/2, y: rect.y + rect.height/2, tag: el.tagName, text: (el.textContent || '').trim().substring(0, 100) };
        })()
        """
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": js,
            "returnByValue": true
        ])

        guard let props = extractJSObject(from: result),
              let x = props["x"] as? Double,
              let y = props["y"] as? Double else {
            return "Element not found for selector '\(selector)'"
        }

        _ = try await connection.send(method: "Input.dispatchMouseEvent", params: [
            "type": "mousePressed",
            "x": x,
            "y": y,
            "button": "left",
            "clickCount": 1
        ])
        _ = try await connection.send(method: "Input.dispatchMouseEvent", params: [
            "type": "mouseReleased",
            "x": x,
            "y": y,
            "button": "left",
            "clickCount": 1
        ])

        // If click triggers navigation, wait for page load (short timeout)
        _ = try? await connection.send(method: "Page.enable")
        try? await withThrowingTimeout(3) {
            _ = try await self.connection.send(method: "Page.loadEventFired")
        }

        let tag = props["tag"] as? String ?? ""
        let text = props["text"] as? String ?? ""
        return "Clicked \(tag.lowercased()) '\(text)'"
    }

    func type(selector: String, text: String, context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "Type is not available in fallback mode (Chrome not running)." }
        try await focus(selector: selector)

        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": """
            (() => {
                const el = document.querySelector('\(escapeJS(selector))');
                if (!el) return false;
                const tag = el.tagName.toLowerCase();
                if (tag === 'input' || tag === 'textarea') {
                    el.value = '';
                    el.value = '\(escapeJS(text))';
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                    el.dispatchEvent(new Event('change', { bubbles: true }));
                    return true;
                }
                el.textContent = '\(escapeJS(text))';
                return true;
            })()
            """,
            "returnByValue": true
        ])

        let success = extractJSResult(from: result) == "true"
        return success ? "Typed '\(text)'" : "Could not type into selector '\(selector)'"
    }

    func pressKey(_ key: String, context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "Press key is not available in fallback mode (Chrome not running)." }
        let cdpKey: String
        switch key.lowercased() {
        case "enter": cdpKey = "Enter"
        case "tab": cdpKey = "Tab"
        case "escape", "esc": cdpKey = "Escape"
        case "backspace": cdpKey = "Backspace"
        case "delete": cdpKey = "Delete"
        case "arrowup", "up": cdpKey = "ArrowUp"
        case "arrowdown", "down": cdpKey = "ArrowDown"
        case "arrowleft", "left": cdpKey = "ArrowLeft"
        case "arrowright", "right": cdpKey = "ArrowRight"
        default: cdpKey = key
        }
        _ = try await connection.send(method: "Input.dispatchKeyEvent", params: [
            "type": "rawKeyDown",
            "key": cdpKey
        ])
        _ = try await connection.send(method: "Input.dispatchKeyEvent", params: [
            "type": "keyUp",
            "key": cdpKey
        ])
        return "Pressed \(cdpKey)"
    }

    // MARK: - Extraction

    func extractText(selector: String? = nil, context: ExecutionContext) async throws -> String {
        if isFallbackMode, let sel = selector {
            return "Extract by selector not available in fallback mode."
        }
        if isFallbackMode {
            lock.lock()
            let url = _lastNavigatedURL
            lock.unlock()
            do {
                return try await fallbackEngine.fetchPage(url: url ?? "about:blank")
            } catch {
                return "Fallback text extraction failed: \(error.localizedDescription)"
            }
        }
        let js: String
        if let sel = selector {
            js = """
            (() => {
                const el = document.querySelector('\(escapeJS(sel))');
                return el ? (el.textContent || '').trim() : null;
            })()
            """
        } else {
            js = "document.body?.innerText || ''"
        }
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": js,
            "returnByValue": true
        ])
        return extractJSResult(from: result) ?? ""
    }

    func extractHTML(selector: String? = nil, context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "HTML extraction not available in fallback mode." }
        let js: String
        if let sel = selector {
            js = """
            (() => {
                const el = document.querySelector('\(escapeJS(sel))');
                return el ? el.outerHTML : null;
            })()
            """
        } else {
            js = "document.documentElement?.outerHTML || ''"
        }
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": js,
            "returnByValue": true
        ])
        return extractJSResult(from: result) ?? ""
    }

    func extractAttribute(selector: String, attribute: String, context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "Attribute extraction not available in fallback mode." }
        let js = """
        (() => {
            const el = document.querySelector('\(escapeJS(selector))');
            return el ? el.getAttribute('\(escapeJS(attribute))') : null;
        })()
        """
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": js,
            "returnByValue": true
        ])
        return extractJSResult(from: result) ?? ""
    }

    func evaluateJavaScript(_ js: String, context: ExecutionContext) async throws -> String {
        if isFallbackMode { return "JavaScript evaluation not available in fallback mode." }
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": js,
            "returnByValue": true
        ])
        return extractJSResult(from: result) ?? ""
    }

    // MARK: - Screenshot

    func takeScreenshot(context: ExecutionContext) async throws -> Data {
        if isFallbackMode { throw CDPError.commandFailed("Screenshot not available in fallback mode.") }
        let result = try await connection.send(method: "Page.captureScreenshot", params: [
            "format": "png"
        ])
        guard let base64 = result["data"] as? String,
              let data = Data(base64Encoded: base64) else {
            throw CDPError.commandFailed("Screenshot capture returned no data")
        }
        return data
    }

    // MARK: - Cookies

    func getCookies(context: ExecutionContext) async throws -> [[String: Any]] {
        if isFallbackMode { return [] }
        _ = try await connection.send(method: "Network.enable")
        let result = try await connection.send(method: "Network.getCookies")
        return result["cookies"] as? [[String: Any]] ?? []
    }

    func setCookie(name: String, value: String, url: String, context: ExecutionContext) async throws {
        if isFallbackMode { return }
        _ = try await connection.send(method: "Network.enable")
        _ = try await connection.send(method: "Network.setCookie", params: [
            "name": name,
            "value": value,
            "url": url
        ])
    }

    func setCookies(_ cookies: [[String: Any]], context: ExecutionContext) async throws {
        if isFallbackMode { return }
        _ = try await connection.send(method: "Network.enable")
        for cookie in cookies {
            _ = try await connection.send(method: "Network.setCookie", params: cookie)
        }
    }

    // MARK: - Local Storage

    func getLocalStorage(context: ExecutionContext) async throws -> [String: String] {
        if isFallbackMode { return [:] }
        let result = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": """
            JSON.stringify(window.localStorage || {})
            """,
            "returnByValue": true
        ])
        guard let jsonStr = extractJSResult(from: result),
              let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }

    func setLocalStorage(items: [String: String], context: ExecutionContext) async throws {
        for (key, value) in items {
            let escapedKey = escapeJS(key)
            let escapedValue = escapeJS(value)
            _ = try await connection.send(method: "Runtime.evaluate", params: [
                "expression": "window.localStorage.setItem('\(escapedKey)', '\(escapedValue)')",
                "returnByValue": true
            ])
        }
    }

    // MARK: - Session Persistence

    func saveSession(to store: BrowserSessionStore, workspaceId: String?, context: ExecutionContext) async throws {
        let cookies = try await getCookies(context: context)
        let cookiesData = try JSONSerialization.data(withJSONObject: cookies)
        let cookiesJSON = String(data: cookiesData, encoding: .utf8) ?? "[]"

        let localStore = try await getLocalStorage(context: context)
        let lsData = try JSONSerialization.data(withJSONObject: localStore)
        let localStorageJSON = String(data: lsData, encoding: .utf8)

        let url = try? await getCurrentURL(context: context)

        let session = BrowserSession(
            id: UUID().uuidString,
            workspaceId: workspaceId,
            url: url,
            cookiesJSON: cookiesJSON,
            localStorageJSON: localStorageJSON,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.save(session)
    }

    func restoreSession(from store: BrowserSessionStore, workspaceId: String?, context: ExecutionContext) async throws {
        guard let session = store.session(workspaceId: workspaceId) else { return }

        if let cookiesData = session.cookiesJSON.data(using: .utf8),
           let cookies = try? JSONSerialization.jsonObject(with: cookiesData) as? [[String: Any]] {
            for cookie in cookies {
                if let name = cookie["name"] as? String,
                   let value = cookie["value"] as? String {
                    let domain = cookie["domain"] as? String ?? ""
                    let url = "https://\(domain.starts(with: ".") ? String(domain.dropFirst()) : domain)"
                    try? await setCookie(name: name, value: value, url: url, context: context)
                }
            }
        }

        if let lsJSON = session.localStorageJSON,
           let lsData = lsJSON.data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: lsData) as? [String: String] {
            try await setLocalStorage(items: items, context: context)
        }
    }

    // MARK: - Private

    private func buildChromeArgs(port: Int, headless: Bool, userDataDir: String) -> [String] {
        var args = [
            "--remote-debugging-port=\(port)",
            "--user-data-dir=\(userDataDir)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-fre",
            "--disable-search-engine-choice-screen",
            "--hide-crash-restore-bubble",
            "--window-size=1280,720"
        ]
        if headless {
            args.append("--headless=new")
        }
        return args
    }

    private func findAvailablePort() -> Int {
        for port in defaultPort...(defaultPort + 100) {
            if !isPortInUse(port) {
                return port
            }
        }
        return defaultPort
    }

    private func isPortInUse(_ port: Int) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti:\(port)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return !data.isEmpty
        } catch {
            return false
        }
    }

    private func waitForChrome(port: Int) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/json/version")!
        for attempt in 1...20 {
            do {
                let (_, res) = try await URLSession.shared.data(from: url)
                if let httpRes = res as? HTTPURLResponse, httpRes.statusCode == 200 {
                    return
                }
            } catch {
                if attempt == 20 { throw CDPError.chromeNotRunning }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw CDPError.chromeNotRunning
    }

    private func createPage(port: Int) async throws -> URL {
        let createURL = URL(string: "http://127.0.0.1:\(port)/json/new?url=about:blank")!
        let (data, _) = try await URLSession.shared.data(from: createURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let wsURL = json?["webSocketDebuggerUrl"] as? String,
           let url = URL(string: wsURL) {
            return url
        }
        let listURL = URL(string: "http://127.0.0.1:\(port)/json")!
        let (listData, _) = try await URLSession.shared.data(from: listURL)
        let targets = try JSONSerialization.jsonObject(with: listData) as? [[String: Any]]
        if let first = targets?.first,
           let wsURL = first["webSocketDebuggerUrl"] as? String,
           let url = URL(string: wsURL) {
            return url
        }
        throw CDPError.chromeNotRunning
    }

    private func waitForPageLoad() async throws {
        _ = try await withThrowingTimeout(30) {
            try await self.connection.send(method: "Page.loadEventFired")
        }
    }

    private func focus(selector: String) async throws {
        _ = try await connection.send(method: "Runtime.evaluate", params: [
            "expression": """
            (() => {
                const el = document.querySelector('\(escapeJS(selector))');
                if (el) el.focus();
            })()
            """,
            "returnByValue": true
        ])
    }

    private func extractJSResult(from response: [String: Any]) -> String? {
        guard let result = response["result"] as? [String: Any],
              let value = result["value"] else {
            return nil
        }
        if value is NSNull { return nil }
        return "\(value)"
    }

    private func extractJSObject(from response: [String: Any]) -> [String: Any]? {
        guard let result = response["result"] as? [String: Any],
              let value = result["value"] as? [String: Any] else {
            return nil
        }
        return value
    }
}

private func escapeJS(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
}

private func withThrowingTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CDPError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
