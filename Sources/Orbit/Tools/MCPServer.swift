import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "mcp")

// MARK: - MCPServer

final class MCPServer {
    private let toolRegistry: ToolRegistry
    weak var toolService: ToolService?
    private let queue = DispatchQueue(label: "com.orbit.mcp", qos: .default)
    private var isInitialized = false
    private var stdioTask: Task<Void, Never>?
    private var socketTask: Task<Void, Never>?
    private var socketFD: Int32?

    init(toolRegistry: ToolRegistry) {
        self.toolRegistry = toolRegistry
    }

    deinit {
        stop()
    }

    func stop() {
        stdioTask?.cancel()
        stdioTask = nil
        socketTask?.cancel()
        socketTask = nil
        if let fd = socketFD {
            Darwin.close(fd)
            socketFD = nil
        }
    }

    // MARK: - Stdio Transport

    func startStdio() {
        stdioTask = Task { [weak self] in
            guard let self else { return }
            let input = FileHandle.standardInput

            while !Task.isCancelled {
                do {
                    let data = try input.readToEnd() ?? Data()
                    guard !data.isEmpty else {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    let json = String(data: data, encoding: .utf8) ?? ""
                    for line in json.components(separatedBy: "\n").filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        let response = await handleJSON(line)
                        if let response, let responseData = response.data(using: .utf8) {
                            try FileHandle.standardOutput.write(contentsOf: responseData + Data("\n".utf8))
                        }
                    }
                } catch {
                    if Task.isCancelled { break }
                    log.error("Stdio error: \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    // MARK: - Unix Socket Transport

    func startSocket() {
        socketTask = Task { [weak self] in
            guard let self else { return }

            let socketPath = Self.socketPath
            let parentDir = (socketPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: socketPath) {
                try? FileManager.default.removeItem(atPath: socketPath)
            }

            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                log.error("MCP socket: failed to create socket: \(errno)")
                return
            }
            self.socketFD = fd

            var addr = sockaddr_un()
            addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            addr.sun_family = UInt8(AF_UNIX)
            socketPath.withCString { cstr in
                withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    let raw = UnsafeMutableRawPointer(ptr)
                    let len = min(socketPath.utf8.count + 1, 104)
                    raw.copyMemory(from: cstr, byteCount: len)
                }
            }

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard bindResult == 0 else {
                log.error("MCP socket: bind failed: \(errno)")
                Darwin.close(fd)
                self.socketFD = nil
                return
            }

            Darwin.chmod(socketPath, mode_t(0o600))
            Darwin.listen(fd, 5)

            log.notice("MCP socket listening at \(socketPath)")

            while !Task.isCancelled {
                var clientAddr = sockaddr_un()
                var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                let clientFD = withUnsafePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                        Darwin.accept(fd, UnsafeMutablePointer(mutating: addrPtr), &clientLen)
                    }
                }

                guard clientFD >= 0 else {
                    if errno == EINTR { continue }
                    log.error("MCP socket: accept failed: \(errno)")
                    break
                }

                Task { [weak self] in
                    await self?.handleConnection(clientFD: clientFD)
                }
            }

            Darwin.close(fd)
            self.socketFD = nil
        }
    }

    private func handleConnection(clientFD: Int32) async {
        var buffer = Data()
        let readFD = FileHandle(fileDescriptor: clientFD, closeOnDealloc: true)

        while !Task.isCancelled {
            do {
                let data = try readFD.read(upToCount: 65536)
                guard let data, !data.isEmpty else { break }

                buffer.append(data)

                while let newlineRange = buffer.firstRange(of: Data("\n".utf8)) {
                    let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                    buffer = buffer.subdata(in: newlineRange.upperBound..<buffer.endIndex)

                    guard !lineData.isEmpty else { continue }
                    let json = String(data: lineData, encoding: .utf8) ?? ""
                    let response = await handleJSON(json)
                    if let response, let responseData = response.data(using: .utf8) {
                        try readFD.write(contentsOf: responseData + Data("\n".utf8))
                    }
                }
            } catch {
                break
            }
        }
    }

    static var socketPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Orbit/orbit-mcp.sock").path
    }

    // MARK: - JSON-RPC Handling

    func handleJSON(_ json: String) async -> String? {
        guard let data = json.data(using: .utf8) else {
            return errorResponse(id: nil, code: -32700, message: "Parse error: invalid UTF-8")
        }

        guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
            return errorResponse(id: nil, code: -32700, message: "Parse error: invalid JSON-RPC")
        }

        guard request.jsonrpc == "2.0" else {
            return errorResponse(id: request.id, code: -32600, message: "Invalid JSON-RPC version")
        }

        // Notification (no id) — no response
        if request.id == nil || request.id == .null {
            await handleNotification(method: request.method, params: request.params)
            return nil
        }

        return await handleRequest(id: request.id!, method: request.method, params: request.params)
    }

    private func handleNotification(method: String, params: JSONValue?) async {
        switch method {
        case "notifications/initialized":
            isInitialized = true
            log.info("MCP client initialized")
        case "notifications/cancelled":
            log.info("MCP cancellation")
        default:
            log.debug("MCP notification: \(method)")
        }
    }

    private func handleRequest(id: JSONValue, method: String, params: JSONValue?) async -> String? {
        let response: JSONRPCResponse
        switch method {
        case "initialize":
            response = handleInitialize(id: id, params: params)
        case "tools/list":
            response = handleListTools(id: id)
        case "tools/call":
            response = await handleCallTool(id: id, params: params)
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
        return encodeResponse(response)
    }

    // MARK: - Initialize

    private func handleInitialize(id: JSONValue, params: JSONValue?) -> JSONRPCResponse {
        let clientInfo = params?.asObject?["clientInfo"]?.asObject ?? [:]
        let clientName = clientInfo["name"]?.asString ?? "unknown"
        let clientVersion = clientInfo["version"]?.asString ?? "?"
        log.info("MCP client: \(clientName) \(clientVersion)")

        isInitialized = true

        return JSONRPCResponse(
            jsonrpc: "2.0",
            id: id,
            result: .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([
                    "tools": .object([:])
                ]),
                "serverInfo": .object([
                    "name": .string("Orbit"),
                    "version": .string("1.0.0")
                ])
            ]),
            error: nil
        )
    }

    // MARK: - Tools List

    private func handleListTools(id: JSONValue) -> JSONRPCResponse {
        guard isInitialized else {
            return JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCErrorObj(code: -32000, message: "Server not initialized", data: nil))
        }

        let defs = toolRegistry.allDefinitions
        let tools: [JSONValue] = defs.map { def in
            let properties = Dictionary(uniqueKeysWithValues: def.inputSchema.parameters.map { param in
                (param.name, JSONValue.object([
                    "type": .string(param.type.rawValue),
                    "description": .string(param.description)
                ]))
            })
            return .object([
                "name": .string(def.id),
                "description": .string(def.description),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(def.inputSchema.parameters.filter(\.required).map { .string($0.name) })
                ])
            ])
        }

        return JSONRPCResponse(
            jsonrpc: "2.0",
            id: id,
            result: .object(["tools": .array(tools)]),
            error: nil
        )
    }

    // MARK: - Tools Call

    private func handleCallTool(id: JSONValue, params: JSONValue?) async -> JSONRPCResponse {
        guard isInitialized else {
            return JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCErrorObj(code: -32000, message: "Server not initialized", data: nil))
        }

        guard let paramsObj = params?.asObject,
              let name = paramsObj["name"]?.asString, !name.isEmpty
        else {
            return JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCErrorObj(code: -32602, message: "Missing tool name", data: nil))
        }

        guard let tool = toolRegistry.tool(named: name) else {
            return JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCErrorObj(code: -32602, message: "Tool not found: \(name)", data: nil))
        }

        let input: [String: String]
        if let args = paramsObj["arguments"]?.asObject {
            input = args.compactMapValues { $0.asString }
        } else {
            input = [:]
        }

        do {
            let result = try await tool.run(input: input)
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: id,
                result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(result)
                        ])
                    ])
                ]),
                error: nil
            )
        } catch {
            return JSONRPCResponse(
                jsonrpc: "2.0",
                id: id,
                result: nil,
                error: JSONRPCErrorObj(code: -32603, message: error.localizedDescription, data: nil)
            )
        }
    }

    // MARK: - Helpers

    private func errorResponse(id: JSONValue?, code: Int, message: String) -> String? {
        let response = JSONRPCResponse(
            jsonrpc: "2.0",
            id: id,
            result: nil,
            error: JSONRPCErrorObj(code: code, message: message, data: nil)
        )
        return encodeResponse(response)
    }

    private func encodeResponse(_ response: JSONRPCResponse) -> String? {
        guard let data = try? JSONEncoder().encode(response),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

}
