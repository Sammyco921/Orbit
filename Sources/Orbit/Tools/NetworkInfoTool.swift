import Foundation

final class NetworkInfoTool: Tool {
    var definition = ToolDefinition(
        id: "networkInfo",
        name: "Network Info",
        description: "Get current network information: WiFi SSID, IP address, VPN status",
        inputSchema: ToolSchema(parameters: [])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        if Platform.current == .linux {
            let ssid = try await LinuxCommands.networkSSID()
            let ip = try await LinuxCommands.ipAddress()
            return "WiFi SSID: \(ssid)\nIP: \(ip)"
        }

        let airportRaw = try? await scriptExecutor.run(executable: "/usr/sbin/networksetup", arguments: ["-getairportnetwork", "en0"])
        let ssid = airportRaw.flatMap { $0.components(separatedBy: ": ").dropFirst().first }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        let ipRaw = try? await scriptExecutor.run(executable: "/sbin/ipconfig", arguments: ["getifaddr", "en0"])
        let ip = ipRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        let vpnRaw = try? await scriptExecutor.run(executable: "/sbin/ifconfig", arguments: ["utun0"])
        let vpn: String
        if let vpnRaw, vpnRaw.contains("inet ") {
            let parts = vpnRaw.components(separatedBy: "inet ")
            if parts.count > 1 {
                vpn = parts[1].components(separatedBy: " ").first ?? "inactive"
            } else {
                vpn = "inactive"
            }
        } else {
            vpn = "inactive"
        }

        return "WiFi SSID: \(ssid)\nIP: \(ip)\nVPN: \(vpn)"
    }
}
