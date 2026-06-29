import SwiftUI

struct MenuBarPanelView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var quickInput = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusSection
            Divider()
            quickInputSection
            pendingApprovalsSection
            liveExecutionPreview
            recentActivitySection
            Divider()
            quickActionsSection
            Divider()
            footerSection
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            schedulerIcon
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 1) {
                Text("Orbit")
                    .font(.system(size: 13, weight: .semibold))
                schedulerLabel
                    .font(.orbitCaptionSmall)
            }

            Spacer()

            Button("Open Orbit") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .font(.orbitCaption)
            .foregroundStyle(Color.orbitAccent)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: 6) {
            schedulerIcon
                .font(.system(size: 10))
            schedulerLabel
                .font(.orbitCaptionSmall)
            Spacer()
            schedulerActions
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var schedulerIcon: some View {
        if let rt = orchestrator.backgroundRuntime {
            let status = rt.menuBarStatus
            switch status {
            case .idle: Image(systemName: "circle.fill").foregroundStyle(.green)
            case .running: Image(systemName: "circle.fill").foregroundStyle(.yellow)
            case .queued: Image(systemName: "clock.fill").foregroundStyle(.blue)
            case .paused: Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            case .connecting: Image(systemName: "circle.dashed").foregroundStyle(.gray)
            }
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(.gray)
        }
    }

    private var schedulerLabel: some View {
        if let rt = orchestrator.backgroundRuntime {
            Text(schedulerLabelText(for: rt.menuBarStatus))
                .foregroundStyle(.orbitSecondary)
        } else {
            Text("Connecting...")
                .foregroundStyle(.orbitTertiary)
        }
    }

    private func schedulerLabelText(for status: MenuBarStatus) -> String {
        switch status {
        case .idle: return OrbitVoice.Status.idle
        case .running: return OrbitVoice.Status.running
        case .queued(let count): return OrbitVoice.Label.queueCount(count)
        case .paused(let count): return OrbitVoice.Label.pauseCount(count)
        case .failed: return OrbitVoice.Status.error
        case .connecting: return OrbitVoice.Status.connecting
        }
    }

    @ViewBuilder
    private var schedulerActions: some View {
        if let rt = orchestrator.backgroundRuntime {
            let status = rt.menuBarStatus
            if case .running = status {
                if let runningJob = rt.scheduler.currentRunningJob {
                    Button("Pause") { rt.pauseJob(jobId: runningJob.jobId) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Stop") { rt.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            } else if case .paused = status, let paused = rt.scheduler.allActiveJobs.first(where: { $0.state == .paused }) {
                Button("Resume") { rt.resumeJob(jobId: paused.jobId) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.green)
                Button("Cancel") { rt.cancelJob(jobId: paused.jobId) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            } else if case .queued = status {
                Button("Cancel All") { rt.scheduler.cancelAllQueued() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            }
        }
    }

    private var isRunning: Bool {
        guard let bg = orchestrator.backgroundRuntime else { return false }
        if case .running = bg.menuBarStatus { return true }
        switch bg.state {
        case .interpreting, .planning, .executing: return true
        default: return false
        }
    }

    // MARK: - Quick Input

    private var quickInputSection: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Quick task...", text: $quickInput)
                .textFieldStyle(.plain)
                .font(.orbitBodySmall)
                .focused($isFocused)
                .onSubmit(sendQuick)

            Button(action: sendQuick) {
                Image(systemName: "arrow.up")
                    .font(.orbitCaption)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.orbitAccent)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
            .buttonStyle(.plain)
            .disabled(quickInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Spacing.sm)
        .background(Color.orbitSurface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Live Execution Preview

    @ViewBuilder
    private var liveExecutionPreview: some View {
        if let rt = orchestrator.backgroundRuntime {
            let schedulerStatus = rt.scheduler.status
            switch schedulerStatus {
            case .running(let job):
                Divider()
                schedulerRunningPreview(job: job)
            case .queued(let count):
                Divider()
                schedulerQueuedPreview(count: count)
            case .paused(let count):
                Divider()
                schedulerPausedPreview(count: count)
            default:
                // Fall back to interactive UX preview
                if let story = rt.currentStory,
                   case .executing(let current, let total) = rt.state {
                    Divider()
                    interactiveRunningPreview(story: story, current: current, total: total)
                }
            }
        }
    }

    @ViewBuilder
    private func schedulerRunningPreview(job: ExecutionJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                Text("Running:")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
            }

            Text(job.intent)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitPrimary)
                .lineLimit(2)

            if job.currentStepIndex > 0 {
                HStack(spacing: 4) {
                    Text("Step \(job.currentStepIndex)")
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitAccent)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func schedulerQueuedPreview(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8))
                .foregroundStyle(.blue)
            Text("\(count) job(s) queued — waiting for execution")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func schedulerPausedPreview(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
            Text("\(count) job(s) paused")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func interactiveRunningPreview(story: ExecutionStory, current: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                Text("Running:")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
            }

            Text(story.intent)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitPrimary)
                .lineLimit(2)

            HStack(spacing: 4) {
                Text("Step \(current + 1) of \(total)")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitAccent)

                if current < story.steps.count,
                   let tokens = story.steps[current].streamedTokens,
                   !tokens.isEmpty {
                    Text("\u{00B7}")
                        .foregroundStyle(.orbitTertiary)
                    Text(String(tokens.suffix(120)).trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
    }

    // MARK: - Pending Approvals

    @ViewBuilder
    private var pendingApprovalsSection: some View {
        if let pending = PendingApproval.shared.pendingRequest {
            Divider()
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Approval Needed")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(Color.orbitWarning)
                    .textCase(.uppercase)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.orbitCaption)
                        .foregroundStyle(Color.orbitWarning)
                    Text(pending.toolName)
                        .font(.orbitCaption)
                    Spacer()
                    Button("Review") {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)
            }
        }
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        if !orchestrator.timelineLog.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Recent Activity")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(Color.orbitTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)

                ForEach(orchestrator.timelineLog.suffix(3)) { entry in
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(activityColor(entry.outcome))
                            .frame(width: 6, height: 6)
                        Text(entry.stepName)
                            .font(.orbitCaption)
                            .foregroundStyle(Color.orbitSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 1)
                }
            }
            .padding(.bottom, Spacing.xs)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 0) {
            quickAction(icon: "plus.circle", label: "New Task\u{2026}") {
                NSApp.activate(ignoringOtherApps: true)
            }

            quickAction(icon: "stop.circle", label: "Cancel Current Job") {
                if let rt = orchestrator.backgroundRuntime,
                   let running = rt.scheduler.currentRunningJob {
                    rt.cancelJob(jobId: running.jobId)
                } else {
                    orchestrator.backgroundRuntime?.cancel()
                }
            }
            .foregroundStyle(isRunning ? Color.orbitError : Color.orbitTertiary)
            .disabled(!isRunning)

            quickAction(icon: "pause.circle", label: "Pause / Resume") {
                guard let rt = orchestrator.backgroundRuntime else { return }
                if let running = rt.scheduler.currentRunningJob {
                    rt.pauseJob(jobId: running.jobId)
                } else if let paused = rt.scheduler.allActiveJobs.first(where: { $0.state == .paused }) {
                    rt.resumeJob(jobId: paused.jobId)
                }
            }
            .foregroundStyle(isRunning || (orchestrator.backgroundRuntime?.scheduler.pausedCount ?? 0) > 0 ? Color.orbitAccent : Color.orbitTertiary)
            .disabled(orchestrator.backgroundRuntime == nil)

            quickAction(icon: "macwindow", label: "Open Main Window") {
                NSApp.activate(ignoringOtherApps: true)
            }

            quickAction(icon: "gearshape", label: "Open Settings") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .navigateToSettings, object: nil)
            }

            quickAction(icon: "clock.arrow.circlepath", label: "View Latest Execution") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .navigateToHistory, object: nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func quickAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.orbitBodySmall)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Quit") {
                orchestrator.backgroundRuntime?.shutDown()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.orbitCaption)
            .foregroundStyle(Color.orbitSecondary)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Actions

    private func sendQuick() {
        let text = quickInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        quickInput = ""
        orchestrator.backgroundRuntime?.submitBackground(intent: text)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func activityColor(_ outcome: String) -> Color {
        switch outcome {
        case "succeeded": .orbitSuccess
        case "failed": .orbitError
        case "denied": .orbitWarning
        default: .orbitTertiary
        }
    }
}

// MARK: - Navigation Notifications

extension Notification.Name {
    static let navigateToSettings = Notification.Name("com.orbit.navigateToSettings")
    static let navigateToHistory = Notification.Name("com.orbit.navigateToHistory")
}
