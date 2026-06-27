import Foundation

final class SystemInfoTool: Tool {
    var definition = ToolDefinition(
        id: "systemInfo",
        name: "System Information",
        description: "Get detailed information about the Mac: OS version, uptime, memory, CPU, model, and cores",
        inputSchema: ToolSchema(parameters: [])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        if Platform.current == .linux {
            let os = try await LinuxCommands.osInfo()
            let cpu = try await LinuxCommands.cpuInfo()
            let mem = try await LinuxCommands.memoryInfo()
            let uptimeRaw = try await scriptExecutor.run(executable: "/usr/bin/uptime", arguments: [])
            let uptimeLine = uptimeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let uptime = uptimeLine.components(separatedBy: "up ").dropFirst().first?
                .components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "unknown"
            return """
            System: \(os)
            Uptime: \(uptime)
            Memory: \(mem.trimmingCharacters(in: .whitespacesAndNewlines))
            CPU: \(cpu)
            """
        }

        let swVers = try await scriptExecutor.run(executable: "/usr/bin/sw_vers", arguments: ["-productName"])
        let swVer = try await scriptExecutor.run(executable: "/usr/bin/sw_vers", arguments: ["-productVersion"])
        let build = try await scriptExecutor.run(executable: "/usr/bin/sw_vers", arguments: ["-buildVersion"])
        let uptimeRaw = try await scriptExecutor.run(executable: "/usr/bin/uptime", arguments: [])
        let memoryRaw = try await scriptExecutor.run(executable: "/usr/bin/vm_stat", arguments: [])
        let cpu = try await scriptExecutor.run(executable: "/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"])
        let model = try await scriptExecutor.run(executable: "/usr/sbin/sysctl", arguments: ["-n", "hw.model"])
        let cores = try await scriptExecutor.run(executable: "/usr/sbin/sysctl", arguments: ["-n", "hw.ncpu"])

        let uptimeLine = uptimeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let uptime = uptimeLine.components(separatedBy: "up ").dropFirst().first?
            .components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "unknown"

        let activePages = memoryRaw.components(separatedBy: "Pages active:").dropFirst().first?
            .trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ").first ?? "0"
        let memGB = (Double(activePages).flatMap { $0 * 16384 / 1_073_741_824 }).map { String(format: "%.1f GB active", $0) } ?? "unknown"

        return """
        System: \(swVers.trimmingCharacters(in: .whitespacesAndNewlines)) \(swVer.trimmingCharacters(in: .whitespacesAndNewlines)) (\(build.trimmingCharacters(in: .whitespacesAndNewlines)))
        Uptime: \(uptime)
        Memory: \(memGB)
        CPU: \(cpu.trimmingCharacters(in: .whitespacesAndNewlines))
        Model: \(model.trimmingCharacters(in: .whitespacesAndNewlines))
        Cores: \(cores.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }
}
