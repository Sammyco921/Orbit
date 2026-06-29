import Foundation
import OSLog
import ServiceManagement

private let log = Logger(subsystem: "com.orbit", category: "launch-at-login")

public final class LaunchAtLoginService {
    public static let shared = LaunchAtLoginService()

    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.orbit.Orbit"

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
        log.notice("Launch-at-login registered")
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
        log.notice("Launch-at-login unregistered")
    }

    public func toggle() throws {
        if isEnabled {
            try unregister()
        } else {
            try register()
        }
    }
}
