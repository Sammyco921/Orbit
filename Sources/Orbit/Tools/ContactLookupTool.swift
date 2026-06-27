import Foundation

final class ContactLookupTool: Tool {
    var definition = ToolDefinition(
        id: "contactLookup",
        name: "Look Up Contact",
        description: "Search for a contact in the system address book",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "name", description: "Name or partial name to search for", type: .string, required: true)
        ]),
        supportedPlatforms: ["macos"]
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let name = input["name"], !name.isEmpty else {
            return "No name provided to search for."
        }

        let safeName = Self.appleScriptEscape(name)
        let script = """
        tell application "Contacts"
            set matchedPeople to every person whose name contains "\(safeName)"
            if (count of matchedPeople) is 0 then
                return "No contacts found for '\(safeName)'"
            end if
            set output to ""
            repeat with p in matchedPeople
                set personName to name of p
                set personPhones to ""
                repeat with phone in phones of p
                    set personPhones to personPhones & ", " & (value of phone) as string
                end repeat
                set personEmails to ""
                repeat with email in emails of p
                    set personEmails to personEmails & ", " & (value of email) as string
                end repeat
                set output to output & personName & " | Phone: " & personPhones & " | Email: " & personEmails & linefeed
            end repeat
            return output
        end tell
        """
        return try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", script])
    }

    private static func appleScriptEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\" & quote & \"")
    }
}
