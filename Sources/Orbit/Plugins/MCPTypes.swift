import Foundation

// MARK: - JSON-RPC 2.0 Types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let result: JSONValue?
    let error: JSONRPCErrorObj?
}

struct JSONRPCErrorObj: Codable {
    let code: Int
    let message: String
    let data: JSONValue?
}

enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { self = .string(str); return }
        if let int = try? container.decode(Int.self) { self = .int(int); return }
        if let bool = try? container.decode(Bool.self) { self = .bool(bool); return }
        if let obj = try? container.decode([String: JSONValue].self) { self = .object(obj); return }
        if let arr = try? container.decode([JSONValue].self) { self = .array(arr); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Unknown JSON value"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var asString: String? { if case .string(let v) = self { v } else { nil } }
    var asInt: Int? { if case .int(let v) = self { v } else { nil } }
    var asObject: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    var asArray: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
}
