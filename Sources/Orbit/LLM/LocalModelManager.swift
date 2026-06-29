import Foundation

// MARK: - Discovered Model Representation

struct DiscoveredModel: Identifiable, Equatable {
    let id: String
    let name: String
    let source: ModelSource
    var serverURL: String?
    var size: Int64?

    enum ModelSource: String, Equatable {
        case ollamaRunning
        case ollamaInstalled
        case ggufFile
        case serverDetected
    }
}

struct RunningServer: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let apiType: LocalAPIType
    let detectedModel: String?
}

// MARK: - Discovery Result

struct DiscoveryResult {
    let servers: [RunningServer]
    let models: [DiscoveredModel]
    let ollamaIsInstalled: Bool
    let ollamaAppIsInstalled: Bool
    let hasAnyModel: Bool
    let suggestedModelName: String = "llama3"
}

// MARK: - Local Model Manager

final class LocalModelManager {
    private let session: URLSession
    private let fileManager: FileManager
    private var currentPullProcess: Process?

    static let suggestedModel = "llama3"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: config)
        self.fileManager = .default
    }

    // MARK: - Ollama Installation Detection

    /// Checks for the `ollama` binary in common locations, including inside the .app bundle.
    var ollamaIsInstalled: Bool {
        findOllamaPath() != nil
    }

    /// Checks if the Ollama.app is in /Applications or ~/Applications (even if the binary isn't in PATH).
    var ollamaAppIsInstalled: Bool {
        let appPaths = [
            "/Applications/Ollama.app",
            "\(NSHomeDirectory())/Applications/Ollama.app",
        ]
        return appPaths.first { fileManager.fileExists(atPath: $0) } != nil
    }

    /// Full installation status.
    var ollamaInstallStatus: (installed: Bool, appInstalled: Bool, path: String?) {
        let path = findOllamaPath()
        return (path != nil, ollamaAppIsInstalled, path)
    }

    private func findOllamaPath() -> String? {
        let candidates = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "\(NSHomeDirectory())/Applications/Ollama.app/Contents/Resources/ollama",
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    // MARK: - Probe Common Ports for Running Servers

    private static let probeTargets: [(port: Int, name: String, apiType: LocalAPIType, probePath: String)] = [
        (11434, "Ollama", .ollama, "/api/tags"),
        (8080, "llama.cpp", .llamaCPP, "/v1/chat/completions"),
        (8000, "OpenAI-compatible", .openAICompatible, "/v1/chat/completions"),
        (5000, "OpenAI-compatible", .openAICompatible, "/v1/chat/completions"),
        (1234, "LM Studio", .openAICompatible, "/v1/chat/completions"),
        (4891, "GPT4All", .openAICompatible, "/v1/chat/completions"),
    ]

    func detectRunningServers() async -> [RunningServer] {
        await withTaskGroup(of: RunningServer?.self) { group in
            for target in Self.probeTargets {
                group.addTask {
                    let url = "http://localhost:\(target.port)\(target.probePath)"
                    guard let requestURL = URL(string: url) else { return nil }
                    do {
                        let (data, response) = try await self.session.data(from: requestURL)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200
                        else { return nil }

                        let modelName: String?
                        switch target.apiType {
                        case .ollama:
                            modelName = self.parseOllamaModel(from: data)
                        default:
                            modelName = nil
                        }

                        return RunningServer(
                            id: "\(target.port)",
                            name: target.name,
                            baseURL: "http://localhost:\(target.port)",
                            apiType: target.apiType,
                            detectedModel: modelName
                        )
                    } catch {
                        return nil
                    }
                }
            }
            var servers: [RunningServer] = []
            for await result in group {
                if let server = result { servers.append(server) }
            }
            return servers.sorted { $0.name < $1.name }
        }
    }

    private func parseOllamaModel(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]],
              let first = models.first,
              let name = first["name"] as? String
        else { return nil }
        return name
    }

    // MARK: - List Ollama Models (via CLI)

    func listOllamaModels() async -> [DiscoveredModel] {
        guard let path = findOllamaPath() else { return [] }
        let result = try? await runCommand(path, ["list"])
        guard let output = result else { return [] }
        return parseOllamaListOutput(output)
    }

    private func parseOllamaListOutput(_ output: String) -> [DiscoveredModel] {
        let lines = output.split(separator: "\n").dropFirst()
        return lines.compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard let name = parts.first.map(String.init), !name.isEmpty else { return nil }
            let size: Int64?
            if parts.count >= 3 {
                size = parseSize(String(parts[2]))
            } else {
                size = nil
            }
            return DiscoveredModel(
                id: name,
                name: name,
                source: .ollamaInstalled,
                serverURL: nil,
                size: size
            )
        }
    }

    private func parseSize(_ raw: String) -> Int64? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix("GB") {
            let val = Double(cleaned.dropLast(2).trimmingCharacters(in: .whitespaces)) ?? 0
            return Int64(val * 1_000_000_000)
        }
        if cleaned.hasSuffix("MB") {
            let val = Double(cleaned.dropLast(2).trimmingCharacters(in: .whitespaces)) ?? 0
            return Int64(val * 1_000_000)
        }
        return nil
    }

    // MARK: - Scan for GGUF Files

    func scanGGUFFiles() -> [DiscoveredModel] {
        let searchPaths: [String] = [
            "\(NSHomeDirectory())/models",
            "\(NSHomeDirectory())/.cache/llama.cpp",
            "\(NSHomeDirectory())/Downloads",
            "/opt/models",
            "/Applications",
            "\(NSHomeDirectory())/Applications",
        ]
        var results: [DiscoveredModel] = []
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: path),
                  let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "gguf" else { continue }
                let name = fileURL.deletingPathExtension().lastPathComponent
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                results.append(DiscoveredModel(
                    id: fileURL.path,
                    name: name,
                    source: .ggufFile,
                    serverURL: fileURL.path,
                    size: size
                ))
            }
        }
        return results
    }

    // MARK: - Launch

    enum LaunchError: Error, LocalizedError {
        case ollamaNotInstalled
        case launchFailed(String)
        case modelFileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .ollamaNotInstalled: return "Ollama is not installed."
            case .launchFailed(let detail): return "Failed to launch: \(detail)"
            case .modelFileNotFound(let path): return "Model file not found: \(path)"
            }
        }
    }

    func launchOllamaServe() async throws {
        guard let path = findOllamaPath() else { throw LaunchError.ollamaNotInstalled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve"]
        try process.run()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    func launchLlamaCppServer(modelPath: String, port: Int = 8080) async throws {
        guard fileManager.fileExists(atPath: modelPath) else {
            throw LaunchError.modelFileNotFound(modelPath)
        }
        let llamaPaths = [
            "/usr/local/bin/llama-server",
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-cli",
        ]
        guard let executable = llamaPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw LaunchError.launchFailed("llama-server not found. Install it from https://github.com/ggerganov/llama.cpp")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-m", modelPath, "--port", "\(port)"]
        try process.run()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    // MARK: - Wait for Server Readiness

    func waitForServer(url baseURL: String, timeout: Int = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            guard let url = URL(string: "\(baseURL)/api/tags") ?? URL(string: "\(baseURL)/v1/chat/completions") else { return false }
            do {
                let (_, response) = try await session.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return true }
            } catch {}
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    // MARK: - Fetch Ollama Models via API (if server is running)

    func fetchOllamaModels(baseURL: String) async -> [DiscoveredModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = json?["models"] as? [[String: Any]] ?? []
            return models.compactMap { m in
                guard let name = m["name"] as? String else { return nil }
                let size = (m["size"] as? Int64) ?? (m["size"] as? Int).map(Int64.init)
                return DiscoveredModel(id: name, name: name, source: .ollamaRunning, serverURL: baseURL, size: size)
            }
        } catch {
            return []
        }
    }

    // MARK: - Pull Model (Ollama)

    /// Cancel an ongoing model pull.
    func cancelPull() {
        currentPullProcess?.terminate()
        currentPullProcess = nil
    }

    /// Pull a model via `ollama pull` with streaming progress.
    func pullModel(name: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self, let path = self.findOllamaPath() else {
                    continuation.finish(throwing: LaunchError.ollamaNotInstalled)
                    return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["pull", name]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    await MainActor.run { self.currentPullProcess = process }
                    try process.run()
                    // Read stderr for progress (ollama pull outputs progress to stderr)
                    let errHandle = errPipe.fileHandleForReading
                    errHandle.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                        for part in line.split(separator: "\n") {
                            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                continuation.yield(trimmed)
                            }
                        }
                    }

                    process.waitUntilExit()
                    errHandle.readabilityHandler = nil
                    await MainActor.run { self.currentPullProcess = nil }

                    if process.terminationStatus == 0 {
                        continuation.yield("Done: \(name) downloaded successfully")
                        continuation.finish()
                    } else if process.terminationStatus == 15 {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.finish(throwing: LaunchError.launchFailed(errText))
                    }
                } catch {
                    await MainActor.run { self.currentPullProcess = nil }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Complete Discovery (all-in-one)

    func discoverAll() async -> DiscoveryResult {
        let servers = await detectRunningServers()
        var models: [DiscoveredModel] = []

        for server in servers {
            switch server.apiType {
            case .ollama:
                let ollamaModels = await fetchOllamaModels(baseURL: server.baseURL)
                models.append(contentsOf: ollamaModels)
            case .llamaCPP, .openAICompatible:
                models.append(DiscoveredModel(
                    id: server.baseURL,
                    name: server.name,
                    source: .serverDetected,
                    serverURL: server.baseURL,
                    size: nil
                ))
            }
        }

        if models.isEmpty {
            let installed = await listOllamaModels()
            models.append(contentsOf: installed)
            let ggufModels = scanGGUFFiles()
            models.append(contentsOf: ggufModels)
        }

        let (binInstalled, appInstalled, _) = ollamaInstallStatus

        return DiscoveryResult(
            servers: servers,
            models: models,
            ollamaIsInstalled: binInstalled,
            ollamaAppIsInstalled: appInstalled,
            hasAnyModel: !models.isEmpty
        )
    }

    // MARK: - Shell Helper

    @discardableResult
    private func runCommand(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
