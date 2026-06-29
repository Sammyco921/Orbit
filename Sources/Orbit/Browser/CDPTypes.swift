import Foundation

// MARK: - CDP Message Types

struct CDPRequest: Encodable {
    let id: Int
    let method: String
    let params: [String: Any]?

    enum CodingKeys: CodingKey {
        case id, method, params
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        if let params {
            let data = try JSONSerialization.data(withJSONObject: params)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                try container.encode(CDPAnyValue(dict), forKey: .params)
            }
        }
    }
}

struct CDPResponse: Decodable {
    let id: Int?
    let result: [String: Any]?
    let error: CDPErrorResponse?
    let method: String?
    let params: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case id, result, error, method, params
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        error = try container.decodeIfPresent(CDPErrorResponse.self, forKey: .error)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        if let rawResult = try? container.decode(CDPAnyValue.self, forKey: .result) {
            result = rawResult.value as? [String: Any]
        } else {
            result = nil
        }
        if let rawParams = try? container.decode(CDPAnyValue.self, forKey: .params) {
            params = rawParams.value as? [String: Any]
        } else {
            params = nil
        }
    }

    var isEvent: Bool { method != nil && id == nil }
    var isResponse: Bool { id != nil }
}

struct CDPErrorResponse: Decodable, Error {
    let code: Int
    let message: String
}

// MARK: - JSON Helper for [String: Any]

private struct CDPAnyValue: Decodable, Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: CDPAnyValue].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([CDPAnyValue].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { CDPAnyValue($0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { CDPAnyValue($0) })
        }
    }
}
