import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "shared-memory")

actor SharedMemoryService {
    private struct VersionedEntry: Sendable {
        let value: AnySendable
        let version: UInt64
        let lastWriter: String?
        let updatedAt: Date
    }

    private var stores: [String: [String: VersionedEntry]] = [:]
    private var accessLog: [String: [Date]] = [:]
    private var nextVersion: UInt64 = 1

    // MARK: - Scoped Read/Write

    func write<T: Codable & Sendable>(_ value: T, key: String, scope: String, writer: String? = nil) {
        let entry = VersionedEntry(
            value: AnySendable(value: value),
            version: nextVersion,
            lastWriter: writer,
            updatedAt: Date()
        )
        nextVersion += 1
        if stores[scope] == nil { stores[scope] = [:] }
        stores[scope]?[key] = entry
        log.debug("SharedMemory write [\(scope)] \(key) v\(entry.version) by \(writer ?? "unknown")")
    }

    /// Optimistic write: only succeeds if the key hasn't been modified since the given version.
    /// Returns the current version on failure so the caller can retry with fresh data.
    func writeIfUnchanged<T: Codable & Sendable>(_ value: T, key: String, scope: String, expectedVersion: UInt64, writer: String? = nil) -> UInt64? {
        if let existing = stores[scope]?[key], existing.version != expectedVersion {
            log.warning("SharedMemory collision [\(scope)] \(key): expected v\(expectedVersion) but current is v\(existing.version) by \(existing.lastWriter ?? "?")")
            return existing.version
        }
        let entry = VersionedEntry(
            value: AnySendable(value: value),
            version: nextVersion,
            lastWriter: writer,
            updatedAt: Date()
        )
        nextVersion += 1
        if stores[scope] == nil { stores[scope] = [:] }
        stores[scope]?[key] = entry
        log.debug("SharedMemory writeIfUnchanged [\(scope)] \(key) v\(entry.version) by \(writer ?? "unknown")")
        return nil
    }

    func read<T: Codable & Sendable>(key: String, scope: String, as type: T.Type) -> T? {
        guard let entry = stores[scope]?[key] else { return nil }
        return entry.value.value as? T
    }

    /// Returns the value and its version for optimistic concurrency control.
    func readWithVersion<T: Codable & Sendable>(key: String, scope: String, as type: T.Type) -> (value: T, version: UInt64)? {
        guard let entry = stores[scope]?[key], let v = entry.value.value as? T else { return nil }
        return (v, entry.version)
    }

    func readAll<T: Codable & Sendable>(scope: String, as type: T.Type) -> [String: T] {
        guard let scopeStore = stores[scope] else { return [:] }
        var result: [String: T] = [:]
        for (key, entry) in scopeStore {
            if let val = entry.value.value as? T { result[key] = val }
        }
        return result
    }

    func delete(key: String, scope: String) {
        stores[scope]?.removeValue(forKey: key)
    }

    func clear(scope: String) {
        stores.removeValue(forKey: scope)
    }

    func clearAll() {
        stores.removeAll()
    }

    // MARK: - Query

    func keys(scope: String) -> [String] {
        stores[scope].map { Array($0.keys) } ?? []
    }

    func snapshot() -> [String: [String: String]] {
        stores.mapValues { scopeStore in
            scopeStore.mapValues { "\($0.value.value)" }
        }
    }

    func metadata(key: String, scope: String) -> (version: UInt64, lastWriter: String?, updatedAt: Date)? {
        guard let entry = stores[scope]?[key] else { return nil }
        return (entry.version, entry.lastWriter, entry.updatedAt)
    }

    // MARK: - Checkpoint Support

    func exportState() -> Data? {
        let serializable = stores.compactMapValues { scopeStore -> [String: Data]? in
            var result: [String: Data] = [:]
            for (key, entry) in scopeStore {
                if let data = try? JSONEncoder().encode(AnyCodableWrapper(value: entry.value.value)) {
                    result[key] = data
                }
            }
            return result.isEmpty ? nil : result
        }
        return try? JSONEncoder().encode(serializable)
    }

    func importState(_ data: Data) {
        guard let dict = try? JSONDecoder().decode([String: [String: Data]].self, from: data) else { return }
        for (scope, entries) in dict {
            for (key, valueData) in entries {
                if let wrapper = try? JSONDecoder().decode(AnyCodableWrapper.self, from: valueData) {
                    if stores[scope] == nil { stores[scope] = [:] }
                    stores[scope]?[key] = VersionedEntry(
                        value: AnySendable(value: wrapper.value),
                        version: nextVersion,
                        lastWriter: nil,
                        updatedAt: Date()
                    )
                    nextVersion += 1
                }
            }
        }
    }
}

// MARK: - Type Erasure Helpers

private struct AnySendable: Sendable {
    let value: Any
}

private struct AnyCodableWrapper: Codable {
    let value: Any

    init(value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s } else if let i = try? container.decode(Int.self) { value = i } else if let d = try? container.decode(Double.self) { value = d } else if let b = try? container.decode(Bool.self) { value = b } else if let arr = try? container.decode([String].self) { value = arr } else if let dict = try? container.decode([String: String].self) { value = dict } else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let s = value as? String { try container.encode(s) } else if let i = value as? Int { try container.encode(i) } else if let d = value as? Double { try container.encode(d) } else if let b = value as? Bool { try container.encode(b) } else if let arr = value as? [String] { try container.encode(arr) } else if let dict = value as? [String: String] { try container.encode(dict) } else { try container.encodeNil() }
    }
}
