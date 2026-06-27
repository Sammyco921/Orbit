import Foundation

final class MusicControlTool: Tool {
    var definition = ToolDefinition(
        id: "musicControl",
        name: "Music Control",
        description: "Control music playback: play, pause, next, previous, or get current track info",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "action", description: "'play', 'pause', 'next', 'previous', 'stop', or 'nowPlaying' for current track info", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let action = input["action"]?.lowercased() ?? "nowPlaying"

        if Platform.current == .linux {
            switch action {
            case "play", "pause":
                try await LinuxCommands.musicPlayPause()
                return action == "play" ? "Playing" : "Paused"
            case "next":
                try await LinuxCommands.musicNext()
                return "Next track"
            case "previous":
                try await LinuxCommands.musicPrevious()
                return "Previous track"
            case "stop":
                try await LinuxCommands.musicPlayPause()
                return "Stopped"
            default:
                return "Now Playing info not available on Linux"
            }
        }

        switch action {
        case "play":
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"Music\" to play"])
            return "Playing"

        case "pause":
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"Music\" to pause"])
            return "Paused"

        case "next":
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"Music\" to next track"])
            return "Next track"

        case "previous":
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"Music\" to previous track"])
            return "Previous track"

        case "stop":
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"Music\" to stop"])
            return "Stopped"

        default:
            let info = try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "Music"
                if player state is not stopped then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    return "Now Playing: " & trackName & " by " & artistName & " (" & albumName & ")"
                else
                    return "No music playing"
                end if
            end tell
            """])
            return info.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
