import Foundation

enum Sandboxer {
    private static let allowedPrefixes: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            home,
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Orbit",
            NSTemporaryDirectory(),
            NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first,
        ].compactMap { $0 }
    }()

    private static let blockedPatterns: [String] = [
        "/.ssh",
        "/.aws",
        "/.gnupg",
        "/.config",
        "/.kube",
        "/.netrc",
        "/.gitconfig",
        "/.git-credentials",
        "/Library/Keychains",
        "/Library/Preferences/SystemConfiguration",
    ]

    static func sandboxPath(_ path: String) -> String? {
        let resolved = (path as NSString).standardizingPath
        let resolvedURL = URL(fileURLWithPath: resolved)
        guard let realPath = try? resolvedURL.resourceValues(forKeys: [.pathKey]).path ?? resolved
        else { return nil }

        guard allowedPrefixes.contains(where: { realPath == $0 || realPath.hasPrefix($0 + "/") })
        else { return nil }

        for pattern in blockedPatterns {
            if realPath.contains(pattern) {
                return nil
            }
        }

        return realPath
    }
}
