import Foundation

/// Detected operating system platform
enum Platform: Equatable, Sendable {
    case macOS
    case linux

    static var current: Platform {
#if os(macOS)
        .macOS
#elseif os(Linux)
        .linux
#else
        .macOS
#endif
    }

    var isMacOS: Bool { self == .macOS }
    var isLinux: Bool { self == .linux }

    var name: String {
        switch self {
        case .macOS: return "macOS"
        case .linux: return "Linux"
        }
    }
}

/// Errors for platform-specific operations
