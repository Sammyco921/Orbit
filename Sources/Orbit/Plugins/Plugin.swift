import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "plugin")

final class Plugin: Identifiable, Observable {
    let manifest: PluginManifest
    let directory: URL
    var isEnabled: Bool {
        didSet { persistEnabled() }
    }
    private(set) var process: Process?
    private(set) var isRunning: Bool = false
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var responseContinuations: [Int: CheckedContinuation<String, Error>] = [:]
    private var nextId = 1
    private let queue = DispatchQueue(label: "com.orbit.plugin.mcp", qos: .default)
    private var readTask: Task<Void, Never>?
    private let decoder = JSONDecoder()
    private var crashCount = 0
    private let maxRetries = 3
    private var restartTask: Task<Void, Never>?

    var id: String { manifest.id }
    var name: String { manifest.name }

    init(manifest: PluginManifest, directory: URL, isEnabled: Bool = true) {
        self.manifest = manifest
        self.directory = directory
        self.isEnabled = isEnabled
    }

    func start() throws {
        guard !isRunning else { return }
        let entryURL = directory.appendingPathComponent(manifest.entryPoint)
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            throw OrbitError.missingEntryPoint(entryURL.path)
        }

        let process = Process()
        process.currentDirectoryURL = directory

        // Build the original command args
        let commandArgs: [String]
        if manifest.entryPoint.hasSuffix(".py") {
            commandArgs = ["python3", entryURL.path]
        } else if manifest.entryPoint.hasSuffix(".sh") {
            commandArgs = ["bash", entryURL.path]
        } else if manifest.entryPoint.hasSuffix(".js") {
            commandArgs = ["node", entryURL.path]
        } else {
            commandArgs = [entryURL.path]
        }

        // Apply sandbox if available
        let sandbox = PluginSandbox(pluginDirectory: directory)
        do {
            try sandbox.writeProfile()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-f", sandbox.profilePath, "/usr/bin/env"] + commandArgs
            log.notice("Plugin \(self.manifest.id) sandboxed with profile at \(sandbox.profilePath)")
        } catch {
            log.error("Could not apply sandbox to plugin \(self.manifest.id): \(error.localizedDescription). Plugin load aborted.")
            throw OrbitError.invalidInput("Plugin \(self.manifest.id) sandbox setup failed: \(error.localizedDescription)")
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.isRunning = false
            self.process = nil
            log.warning("Plugin \(self.manifest.id) terminated (exit \(proc.terminationStatus))")
            if proc.terminationStatus != 0 && self.crashCount < self.maxRetries {
                self.crashCount += 1
                let delay = UInt64(pow(2.0, Double(self.crashCount - 1))) * 1_000_000_000
                log.notice("Restarting plugin \(self.manifest.id) in \(delay / 1_000_000_000)s (attempt \(self.crashCount)/\(self.maxRetries))")
                self.restartTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: delay)
                    guard let self, !Task.isCancelled else { return }
                    try? self.start()
                }
            }
        }

        try process.run()
        isRunning = true

        startReadTask()
        try handshake()
    }

    func stop() {
        restartTask?.cancel()
        restartTask = nil
        readTask?.cancel()
        readTask = nil
        process?.terminate()
        process = nil
        isRunning = false
        crashCount = 0
    }

    func restart() throws {
        stop()
        crashCount = 0
        try start()
    }

    func callTool(name: String, arguments: [String: String]) async throws -> String {
        let id = nextId
        nextId += 1

        let params = JSONValue.object([
            "name": .string(name),
            "arguments": .object(arguments.mapValues { .string($0) })
        ])
        let request = JSONRPCRequest(jsonrpc: "2.0", id: .int(id), method: "tools/call", params: params)
        let data = try JSONEncoder().encode(request)

        return try await withTimeout(30) {
            try await withCheckedThrowingContinuation { continuation in
                self.queue.sync {
                    self.responseContinuations[id] = continuation
                }
                self.stdinPipe?.fileHandleForWriting.write(data + Data("\n".utf8))
            }
        }
    }

    // MARK: - Private

    private func handshake() throws {
        let req = JSONRPCRequest(jsonrpc: "2.0", id: .int(0), method: "initialize", params: .object([
            "protocolVersion": .string("2024-11-05"),
            "clientInfo": .object(["name": .string("Orbit"), "version": .string("1.0")])
        ]))
        let data = try JSONEncoder().encode(req)
        stdinPipe?.fileHandleForWriting.write(data + Data("\n".utf8))
    }

    private func startReadTask() {
        readTask = Task { [weak self] in
            guard let self else { return }
            let handle = self.stdoutPipe!.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }
                buffer.append(chunk)
                while let newlineRange = buffer.firstRange(of: Data("\n".utf8)) {
                    let lineData = buffer[..<newlineRange.lowerBound]
                    buffer = buffer[newlineRange.upperBound...]
                    if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: lineData) {
                        handleResponse(response)
                    }
                }
            }
        }
    }

    private func handleResponse(_ response: JSONRPCResponse) {
        guard case .int(let id) = response.id else { return }
        queue.sync {
            guard let continuation = responseContinuations.removeValue(forKey: id) else { return }
            if let error = response.error {
                continuation.resume(throwing: OrbitError.pluginToolCallFailed(error.message))
            } else if let result = response.result,
                      case .object(let obj) = result,
                      case .array(let content)? = obj["content"],
                      case .string(let text)? = content.first {
                continuation.resume(returning: text)
            } else {
                continuation.resume(returning: "")
            }
        }
    }

    private func persistEnabled() {
        UserDefaults.standard.set(isEnabled, forKey: "plugin_enabled_\(manifest.id)")
    }
}
