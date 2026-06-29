import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "visual-tools")

// MARK: - Screen Describe Tool

final class ScreenDescribeTool: Tool {
    let screenService: ScreenUnderstandingService

    var definition = ToolDefinition(
        id: "screenDescribe",
        name: "Describe Screen",
        description: "Capture and describe the current screen — detects UI elements, buttons, text fields, links, and visible text using OCR",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "Optional: specific question about what's on screen (e.g., 'what buttons are visible?', 'find the search field')", type: .string, required: false)
        ]),
        requiredPermission: .requiresApproval
    )

    init(screenService: ScreenUnderstandingService) {
        self.screenService = screenService
    }

    func run(input: [String: String]) async throws -> String {
        let snapshot = try await screenService.captureCurrentScreen()
        let description = screenService.describeScreen(snapshot)

        if let query = input["query"], !query.isEmpty {
            // Answer a specific query about the screen
            let answer = answerQuery(query, snapshot: snapshot, description: description)
            return "Screen Analysis:\n\n\(description)\n\nQuery: \(query)\n\(answer)"
        }

        return description
    }

    private func answerQuery(_ query: String, snapshot: ScreenSnapshot, description: String) -> String {
        let q = query.lowercased()

        if q.contains("button") {
            let buttons = snapshot.elements.filter { $0.type == .button && $0.isEnabled }
            if buttons.isEmpty { return "No buttons detected." }
            return "Found \(buttons.count) button(s):\n" + buttons.map { "  • \($0.shortDescription)" }.joined(separator: "\n")
        }

        if q.contains("text field") || q.contains("input") || q.contains("form") {
            let fields = snapshot.elements.filter { $0.type == .textField && $0.isEnabled }
            if fields.isEmpty { return "No text fields detected." }
            return "Found \(fields.count) text field(s):\n" + fields.map { "  • \($0.shortDescription)" }.joined(separator: "\n")
        }

        if q.contains("link") {
            let links = snapshot.elements.filter { $0.type == .link && $0.isEnabled }
            if links.isEmpty { return "No links detected." }
            return "Found \(links.count) link(s):\n" + links.map { "  • \($0.shortDescription)" }.joined(separator: "\n")
        }

        if q.contains("text") || q.contains("visible") || q.contains("what") || q.contains("see") {
            return description
        }

        // Try to find a matching element
        if let match = screenService.findElement(matching: query, in: snapshot) {
            return "Found matching element: \(match.shortDescription) at position (\(Int(match.frame.midX)), \(Int(match.frame.midY)))"
        }

        return "Could not find an element matching '\(query)'. Full screen description above."
    }
}

// MARK: - Visual Click Tool

final class VisualClickTool: Tool {
    let screenService: ScreenUnderstandingService

    var definition = ToolDefinition(
        id: "visualClick",
        name: "Visual Click",
        description: "Click a UI element by describing it (e.g., 'the submit button', 'search field', 'OK'). Uses screen understanding to find the element and click it.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "target", description: "Description of the element to click (e.g., 'submit', 'OK button', 'search field')", type: .string, required: true),
            ToolParameter(name: "button", description: "Mouse button: 'left', 'right', or 'center' (default: left)", type: .string, required: false)
        ]),
        requiredPermission: .requiresApproval
    )

    init(screenService: ScreenUnderstandingService) {
        self.screenService = screenService
    }

    func run(input: [String: String]) async throws -> String {
        guard let target = input["target"], !target.isEmpty else {
            return "No target specified."
        }

        let snapshot = try await screenService.captureCurrentScreen()

        guard let element = screenService.findElement(matching: target, in: snapshot) else {
            // Fall back to trying OCR text match
            let ocrMatch = findOCRMatch(target, in: snapshot.ocrText)
            if let ocrMatch {
                return "Found text '\(target)' but it's not an interactive element. Try using the target description instead."
            }
            throw OrbitError.elementNotFound(target)
        }

        let clickPoint = element.center
        let button = input["button"]?.lowercased() ?? "left"

        // Execute click using AppleScript
        let scriptExecutor = ScriptExecutor()
        let osaButton: String
        switch button {
        case "right": osaButton = "button 2"
        case "center": osaButton = "button 3"
        default: osaButton = "button 1"
        }

        try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
        tell application "System Events"
            set currentPos to position of mouse
            set position of mouse to {\(Int(clickPoint.x)), \(Int(clickPoint.y))}
            delay 0.1
            click \(osaButton)
            set position of mouse to currentPos
        end tell
        """])

        return "Clicked \(element.shortDescription) at (\(Int(clickPoint.x)), \(Int(clickPoint.y)))"
    }

    private func findOCRMatch(_ query: String, in ocrText: String) -> String? {
        let q = query.lowercased()
        let lines = ocrText.components(separatedBy: .newlines)
        return lines.first { $0.lowercased().contains(q) }
    }
}

// MARK: - Visual Type Tool

final class VisualTypeTool: Tool {
    let screenService: ScreenUnderstandingService

    var definition = ToolDefinition(
        id: "visualType",
        name: "Visual Type",
        description: "Type text into a specific field on screen by describing it (e.g., 'search box', 'email address field'). Clicks the field first, then types.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "text", description: "Text to type into the field", type: .string, required: true),
            ToolParameter(name: "target", description: "Description of the text field to type into (e.g., 'search box', 'name field'). Uses the first text field if omitted.", type: .string, required: false),
            ToolParameter(name: "submit", description: "Set to 'true' to press Enter after typing", type: .string, required: false)
        ]),
        requiredPermission: .requiresApproval
    )

    init(screenService: ScreenUnderstandingService) {
        self.screenService = screenService
    }

    func run(input: [String: String]) async throws -> String {
        guard let text = input["text"], !text.isEmpty else {
            return "No text provided."
        }

        let snapshot = try await screenService.captureCurrentScreen()

        let targetField: VisualElement
        if let target = input["target"], !target.isEmpty {
            guard let found = screenService.findElement(matching: target, in: snapshot) else {
                throw OrbitError.elementNotFound(target)
            }
            targetField = found
        } else {
            // Find the first enabled text field
            let fields = screenService.detectFormFields(in: snapshot).filter { $0.type == .textField && $0.isEnabled }
            guard let first = fields.first else {
                throw OrbitError.formFillFailed("No text fields detected on screen")
            }
            targetField = first
        }

        let clickPoint = targetField.center
        let scriptExecutor = ScriptExecutor()

        // Click the field first
        try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
        tell application "System Events"
            set position of mouse to {\(Int(clickPoint.x)), \(Int(clickPoint.y))}
            delay 0.1
            click button 1
        end tell
        """])

        // Small delay for field to focus
        try await Task.sleep(for: .milliseconds(200))

        // Type the text
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
        tell application "System Events"
            keystroke "\(escaped)"
        end tell
        """])

        var result = "Typed \(text.count) characters into \(targetField.shortDescription)"

        // Optionally submit
        if input["submit"]?.lowercased() == "true" {
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "System Events"
                keystroke return
            end tell
            """])
            result += " and pressed Enter"
        }

        return result
    }
}

// MARK: - Form Fill Tool

final class VisualFormFillTool: Tool {
    let screenService: ScreenUnderstandingService

    var definition = ToolDefinition(
        id: "visualFormFill",
        name: "Fill Form",
        description: "Detect form fields on the current screen and fill them with provided values. Pass values as a JSON dictionary matching field labels.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "values", description: "JSON object mapping field descriptions to values, e.g., {\"first name\": \"John\", \"email\": \"john@example.com\"}", type: .string, required: true),
            ToolParameter(name: "submit", description: "Set to 'true' to submit the form after filling", type: .string, required: false)
        ]),
        requiredPermission: .requiresApproval
    )

    init(screenService: ScreenUnderstandingService) {
        self.screenService = screenService
    }

    func run(input: [String: String]) async throws -> String {
        guard let valuesJSON = input["values"], !valuesJSON.isEmpty,
              let data = valuesJSON.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return "Invalid values format. Provide a JSON object with field descriptions and values."
        }

        let snapshot = try await screenService.captureCurrentScreen()
        let fields = screenService.detectFormFields(in: snapshot).filter { $0.isEnabled }
        guard !fields.isEmpty else {
            throw OrbitError.formFillFailed("No form fields detected")
        }

        let scriptExecutor = ScriptExecutor()
        var filled = 0

        for (description, value) in values {
            // Find a matching field
            let matched = fields.filter { field in
                let searchText = "\(field.label) \(field.textContent ?? "")".lowercased()
                return searchText.contains(description.lowercased()) || description.lowercased().contains(field.type.displayName.lowercased())
            }

            if let field = matched.first {
                let pt = field.center
                try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
                tell application "System Events"
                    set position of mouse to {\(Int(pt.x)), \(Int(pt.y))}
                    delay 0.05
                    click button 1
                end tell
                """])
                try await Task.sleep(for: .milliseconds(150))

                if field.type == .checkbox {
                    try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
                    tell application "System Events"
                        click button 1
                    end tell
                    """])
                } else if field.type == .dropdown {
                    try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
                    tell application "System Events"
                        keystroke "\(value.replacingOccurrences(of: "\"", with: "\\\""))"
                        delay 0.1
                        keystroke return
                    end tell
                    """])
                } else {
                    let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
                    try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
                    tell application "System Events"
                        keystroke "\(escaped)"
                    end tell
                    """])
                }
                filled += 1
            }
        }

        var result = "Filled \(filled) of \(values.count) fields"

        if input["submit"]?.lowercased() == "true" {
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "System Events"
                keystroke return
            end tell
            """])
            result += " and submitted form"
        }

        return result
    }
}
