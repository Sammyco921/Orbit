import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "plugin-sandbox")

struct PluginSandbox {
    let pluginDirectory: URL

    var profile: String {
        """
        (version 1)
        (deny default)
        (allow signal (target self))
        (allow sysctl-read)
        (allow process-fork)
        (allow file-read-metadata (literal "/"))
        (allow file-read* (subpath "/usr/lib") (subpath "/usr/share") (subpath "/System/Library"))
        (allow file-read* (subpath "/Library/Frameworks") (subpath "/System/Library/Frameworks"))
        (allow file-read* (subpath "\(pluginDirectory.path)"))
        (allow file-write* (subpath "\(pluginDirectory.path)"))
        (allow file-read* (subpath "\(NSTemporaryDirectory())"))
        (allow file-write* (subpath "\(NSTemporaryDirectory())"))
        (allow file-read* (subpath "/private/tmp"))
        (allow file-write* (subpath "/private/tmp"))
        (allow file-read* (subpath "/private/var/tmp"))
        (allow file-write* (subpath "/private/var/tmp"))
        (allow mach-lookup (global-name "com.apple.system.logger"))
        (allow mach-lookup (global-name "com.apple.system.notification_center"))
        """
    }

    var profilePath: String {
        pluginDirectory.appendingPathComponent(".orbit.sandbox").path
    }

    func writeProfile() throws {
        try profile.write(toFile: profilePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: profilePath)
    }
}
