import SwiftUI
import AppKit

struct InputBarView: View {
    @Binding var text: String
    @Environment(\.uxOrchestrator) private var uxOrchestrator
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Multiline input
            TextField("Ask Orbit to do something...", text: $text, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(.orbitPrimary)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .lineLimit(1...8)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 8)
                .background(Color.orbitBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.orbitBorder, lineWidth: 1)
                )
                .disabled(isExecuting)
                .background(KeyEventHandler(onReturn: submit))

            // Execute / Stop button
            if isExecuting {
                stopButton
            } else {
                executeButton
            }
        }
    }

    private var isExecuting: Bool {
        guard let orch = uxOrchestrator else { return false }
        switch orch.state {
        case .interpreting, .planning, .executing: return true
        default: return false
        }
    }

    private var executeButton: some View {
        Button {
            submit()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty
                    ? .orbitTertiary : .orbitAccent)
        }
        .buttonStyle(.plain)
        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        .help("Execute (Return) · Shift+Return for newline")
    }

    private var stopButton: some View {
        Button {
            uxOrchestrator?.cancel()
        } label: {
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orbitError)
        }
        .buttonStyle(.plain)
        .help("Stop execution")
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        uxOrchestrator?.submit(intent: trimmed)
        text = ""
        isFocused = false
    }
}

// Intercepts Return key (without Shift) to submit; Shift+Return inserts newline.
private struct KeyEventHandler: NSViewRepresentable {
    let onReturn: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onReturn = onReturn
        context.coordinator.installIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onReturn: (() -> Void)?
        private var monitor: Any?

        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 36, !event.modifierFlags.contains(.shift) {
                    onReturn?()
                    return nil
                }
                return event
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}
