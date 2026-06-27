import Foundation

/// Linux-specific command implementations for tools that are "adaptable"
/// Each method encapsulates the Linux CLI equivalent of a macOS-specific operation.
enum LinuxCommands {
    private static let executor = ScriptExecutor(timeoutSeconds: 15)

    // MARK: - Mouse & Keyboard

    static func mouseClick(button: String = "left") async throws {
        let btn: String
        switch button {
        case "right": btn = "3"
        case "center": btn = "2"
        default: btn = "1"
        }
        try await executor.run(executable: "/usr/bin/xdotool", arguments: ["click", btn])
    }

    static func mouseMove(x: Int, y: Int) async throws {
        try await executor.run(executable: "/usr/bin/xdotool", arguments: ["mousemove", "--sync", String(x), String(y)])
    }

    static func mouseClickAt(x: Int, y: Int, button: String = "left") async throws {
        try await mouseMove(x: x, y: y)
        try await Task.sleep(for: .milliseconds(50))
        try await mouseClick(button: button)
    }

    static func keyboardType(text: String) async throws {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        try await executor.run(executable: "/usr/bin/xdotool", arguments: ["type", "--", escaped])
    }

    // MARK: - Notifications

    static func sendNotification(title: String, body: String) async throws {
        try await executor.run(executable: "/usr/bin/notify-send", arguments: [title, body])
    }

    // MARK: - Volume

    static func getVolume() async throws -> Int {
        let output = try await executor.run(executable: "/usr/bin/pactl", arguments: [
            "get-sink-volume", "@DEFAULT_SINK@"
        ])
        // Parse "front-left: NNNNN / 100% / ..."
        if let pctStr = output.components(separatedBy: "/").dropFirst().first,
           let pct = Int(pctStr.trimmingCharacters(in: .whitespaces).dropLast()) {
            return pct
        }
        return 50
    }

    static func setVolume(_ level: Int) async throws {
        let clamped = max(0, min(100, level))
        try await executor.run(executable: "/usr/bin/pactl", arguments: [
            "set-sink-volume", "@DEFAULT_SINK@", "\(clamped)%"
        ])
    }

    // MARK: - System Info

    static func osInfo() async throws -> String {
        let output = try await executor.run(executable: "/bin/cat", arguments: ["/etc/os-release"])
        var name = "Linux"
        var version = ""
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("PRETTY_NAME=") {
                name = line.replacingOccurrences(of: "PRETTY_NAME=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } else if line.hasPrefix("VERSION_ID=") {
                version = line.replacingOccurrences(of: "VERSION_ID=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        if !version.isEmpty { name += " \(version)" }
        return name
    }

    static func cpuInfo() async throws -> String {
        let output = try await executor.run(executable: "/bin/cat", arguments: ["/proc/cpuinfo"])
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("model name") {
                return line.components(separatedBy: ":").dropFirst().first?.trimmingCharacters(in: .whitespaces) ?? "Unknown CPU"
            }
        }
        return "Unknown CPU"
    }

    static func memoryInfo() async throws -> String {
        let output = try await executor.run(executable: "/usr/bin/free", arguments: ["-h"])
        return output
    }

    // MARK: - Battery

    static func batteryStatus() async throws -> String {
        let output = try await executor.run(executable: "/usr/bin/upower", arguments: ["-i", "/org/freedesktop/UPower/devices/battery_BAT0"])
        return output
    }

    // MARK: - Screen / Frontmost App

    static func frontmostApp() async throws -> String {
        let output = try await executor.run(executable: "/usr/bin/xdotool", arguments: ["getactivewindow", "getwindowname"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Screenshot

    static func captureScreenshot(to path: String) async throws {
        try await executor.run(executable: "/usr/bin/import", arguments: [path])
    }

    // MARK: - Open URL / App

    static func openURL(_ url: String) async throws {
        try await executor.run(executable: "/usr/bin/xdg-open", arguments: [url])
    }

    static func openApplication(_ name: String) async throws {
        try await executor.run(executable: "/usr/bin/xdg-open", arguments: [name])
    }

    // MARK: - Clipboard

    static func clipboardCopy(_ text: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xclip")
        process.arguments = ["-selection", "clipboard"]
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        guard let data = text.data(using: .utf8) else { throw OrbitError.invalidInput("Could not encode clipboard text as UTF-8") }
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }

    static func clipboardPaste() async throws -> String {
        return try await executor.run(executable: "/usr/bin/xclip", arguments: ["-selection", "clipboard", "-o"])
    }

    // MARK: - Speech

    static func speak(_ text: String) async throws {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        try await executor.run(executable: "/usr/bin/espeak", arguments: [escaped])
    }

    // MARK: - Music Control (MPRIS)

    static func musicPlayPause() async throws {
        try await executor.run(executable: "/usr/bin/playerctl", arguments: ["play-pause"])
    }

    static func musicNext() async throws {
        try await executor.run(executable: "/usr/bin/playerctl", arguments: ["next"])
    }

    static func musicPrevious() async throws {
        try await executor.run(executable: "/usr/bin/playerctl", arguments: ["previous"])
    }

    // MARK: - Finder Search (local file search)

    static func fileSearch(query: String) async throws -> String {
        let output = try await executor.run(executable: "/usr/bin/locate", arguments: ["-i", query])
        return output
    }

    // MARK: - Network Info

    static func networkSSID() async throws -> String {
        let output = try await executor.run(executable: "/usr/bin/nmcli", arguments: ["-t", "-f", "ACTIVE,SSID", "dev", "wifi"])
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("yes:") {
                return String(line.dropFirst(4))
            }
        }
        return "Not connected"
    }

    static func ipAddress() async throws -> String {
        let output = try await executor.run(executable: "/sbin/ip", arguments: ["-4", "addr", "show", "scope", "global"])
        // Parse "inet 192.168.1.5/24 ..."
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                return String(trimmed.dropFirst(5).split(separator: "/").first ?? "")
            }
        }
        return "Unknown"
    }

    // MARK: - Brightness

    static func getBrightness() async throws -> Int {
        let output = try await executor.run(executable: "/usr/bin/light", arguments: ["-G"])
        return Int(Double(output.trimmingCharacters(in: .whitespaces)) ?? 50)
    }

    static func setBrightness(_ level: Int) async throws {
        let clamped = max(0, min(100, level))
        try await executor.run(executable: "/usr/bin/light", arguments: ["-S", String(clamped)])
    }
}
