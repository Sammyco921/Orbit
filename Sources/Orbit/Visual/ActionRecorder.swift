import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "action-recorder")

/// Records and replays sequences of visual actions (clicks, typing, screenshots)
final class ActionRecorder {
    private let screenService: ScreenUnderstandingService
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var isRecording = false
    private(set) var currentRecording: [RecordedAction] = []
    private var recordingsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.orbit/recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(screenService: ScreenUnderstandingService) {
        self.screenService = screenService
    }

    /// Start recording visual actions
    func startRecording() {
        isRecording = true
        currentRecording = []
        log.notice("Started recording visual actions")
    }

    /// Record a click action
    func recordClick(elementDescription: String, at point: CGPoint) {
        guard isRecording else { return }
        let action = RecordedAction(
            id: UUID(),
            type: .click,
            timestamp: Date(),
            screenshotPath: nil,
            elementDescription: elementDescription,
            coordinates: point,
            text: nil,
            delay: 0
        )
        currentRecording.append(action)
    }

    /// Record a type action
    func recordType(text: String, targetDescription: String?) {
        guard isRecording else { return }
        let action = RecordedAction(
            id: UUID(),
            type: .type,
            timestamp: Date(),
            screenshotPath: nil,
            elementDescription: targetDescription,
            coordinates: nil,
            text: text,
            delay: 0
        )
        currentRecording.append(action)
    }

    /// Record a wait/delay
    func recordWait(seconds: TimeInterval) {
        guard isRecording else { return }
        let action = RecordedAction(
            id: UUID(),
            type: .wait,
            timestamp: Date(),
            screenshotPath: nil,
            elementDescription: nil,
            coordinates: nil,
            text: nil,
            delay: seconds
        )
        currentRecording.append(action)
    }

    /// Record a screenshot
    func recordScreenshot() async throws {
        guard isRecording else { return }
        let snapshot = try await screenService.captureCurrentScreen()
        let action = RecordedAction(
            id: UUID(),
            type: .screenshot,
            timestamp: Date(),
            screenshotPath: nil,
            elementDescription: snapshot.description,
            coordinates: nil,
            text: nil,
            delay: 0
        )
        currentRecording.append(action)
    }

    /// Stop recording and return the recording
    func stopRecording(name: String) -> ActionRecording {
        isRecording = false
        let recording = ActionRecording(
            id: UUID(),
            name: name,
            createdAt: Date(),
            actions: currentRecording
        )
        currentRecording = []
        log.notice("Stopped recording: \(name) (\(recording.actions.count) actions)")
        return recording
    }

    /// Save a recording to disk
    func saveRecording(_ recording: ActionRecording) throws {
        let data = try encoder.encode(recording)
        let url = recordingsDirectory.appendingPathComponent("\(recording.id).json")
        try data.write(to: url)
    }

    /// Load all saved recordings
    func loadRecordings() throws -> [ActionRecording] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return try contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let recording = try? decoder.decode(ActionRecording.self, from: data) else { return nil }
                return recording
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Delete a recording
    func deleteRecording(_ recording: ActionRecording) throws {
        let url = recordingsDirectory.appendingPathComponent("\(recording.id).json")
        try FileManager.default.removeItem(at: url)
    }

    /// Replay a recording
    func replay(_ recording: ActionRecording) async throws {
        let scriptExecutor = ScriptExecutor(timeoutSeconds: 10)

        for action in recording.actions {
            if Task.isCancelled { break }

            if action.delay > 0 {
                try await Task.sleep(for: .milliseconds(Int(action.delay * 1000)))
                continue
            }

            switch action.type {
            case .click:
                guard let point = action.coordinates else { continue }
                try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
                tell application "System Events"
                    set position of mouse to {\(Int(point.x)), \(Int(point.y))}
                    delay 0.1
                    click button 1
                end tell
                """])
                log.notice("Replay: clicked at (\(Int(point.x)), \(Int(point.y)))")

            case .type:
                guard let text = action.text else { continue }
                let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
                try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
                tell application "System Events"
                    keystroke "\(escaped)"
                end tell
                """])
                log.notice("Replay: typed \(text.count) chars")

            case .screenshot:
                try await screenService.captureCurrentScreen()

            case .wait:
                try await Task.sleep(for: .milliseconds(500))
            case .scroll:
                log.notice("Replay: scroll action (not yet implemented)")
            }
        }
    }
}
