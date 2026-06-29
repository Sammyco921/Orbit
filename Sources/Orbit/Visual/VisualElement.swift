import Foundation

/// Types of UI elements that can be detected on screen
enum VisualElementType: String, Codable, Sendable {
    case button
    case textField
    case label
    case link
    case checkbox
    case radioButton
    case dropdown
    case slider
    case image
    case table
    case staticText
    case unknown

    var displayName: String {
        switch self {
        case .button: return "Button"
        case .textField: return "Text Field"
        case .label: return "Label"
        case .link: return "Link"
        case .checkbox: return "Checkbox"
        case .radioButton: return "Radio Button"
        case .dropdown: return "Dropdown"
        case .slider: return "Slider"
        case .image: return "Image"
        case .table: return "Table"
        case .staticText: return "Text"
        case .unknown: return "Element"
        }
    }

    static func from(axRole: String) -> VisualElementType {
        switch axRole {
        case "AXButton": return .button
        case "AXTextField", "AXTextArea", "AXComboBox": return .textField
        case "AXStaticText": return .staticText
        case "AXLink": return .link
        case "AXCheckBox": return .checkbox
        case "AXRadioButton": return .radioButton
        case "AXPopUpButton", "AXComboBox": return .dropdown
        case "AXSlider": return .slider
        case "AXImage": return .image
        case "AXTable", "AXOutline": return .table
        default: return .unknown
        }
    }
}

/// A UI element detected on screen with its location and properties
struct VisualElement: Identifiable, Sendable {
    let id: UUID
    let type: VisualElementType
    let label: String
    let frame: CGRect
    let textContent: String?
    let isEnabled: Bool
    let axRole: String?

    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    var shortDescription: String {
        let text = textContent ?? label
        if text.isEmpty { return "\(type.displayName) at (\(Int(frame.midX)), \(Int(frame.midY)))" }
        return "\(type.displayName): \"\(text.prefix(60))\""
    }
}

/// A snapshot of what's on screen at a point in time
struct ScreenSnapshot: Sendable {
    let timestamp: Date
    let elements: [VisualElement]
    let ocrText: String
    let frontmostApp: String?

    var description: String {
        var lines: [String] = []
        if let app = frontmostApp {
            lines.append("Frontmost App: \(app)")
        }
        lines.append("OCR Text: \(ocrText.prefix(200))")
        lines.append("Detected Elements (\(elements.count)):")
        for elem in elements {
            lines.append("  \(elem.shortDescription)")
        }
        return lines.joined(separator: "\n")
    }
}

/// A recorded visual action for playback
struct RecordedAction: Codable, Sendable {
    let id: UUID
    let type: RecordedActionType
    let timestamp: Date
    let screenshotPath: String?
    let elementDescription: String?
    let coordinates: CGPoint?
    let text: String?
    let delay: TimeInterval

    enum RecordedActionType: String, Codable, Sendable {
        case click
        case type
        case scroll
        case wait
        case screenshot
    }
}

/// A sequence of recorded actions that can be replayed
struct ActionRecording: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let actions: [RecordedAction]
}

extension CGPoint: Codable, Sendable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try container.decode(CGFloat.self, forKey: .x), y: try container.decode(CGFloat.self, forKey: .y))
    }
    private enum CodingKeys: String, CodingKey { case x, y }
}

extension CGRect: Codable, Sendable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin.x, forKey: .x)
        try container.encode(origin.y, forKey: .y)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(CGFloat.self, forKey: .x),
            y: try container.decode(CGFloat.self, forKey: .y),
            width: try container.decode(CGFloat.self, forKey: .width),
            height: try container.decode(CGFloat.self, forKey: .height)
        )
    }
    private enum CodingKeys: String, CodingKey { case x, y, width, height }
}
