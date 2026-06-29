import SwiftUI

struct GoalDashboardView: View {
    let autonomyService: AutonomyService
    @State private var goals: [PersistedGoal] = []
    @State private var showCreate = false
    @State private var newDescription = ""
    @State private var newCriteria = ""
    @State private var newInterval = ""
    @State private var newPriority = 5
    @State private var newMaxRuns = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Behavioral Goals")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("New Goal") {
                    showCreate = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            if goals.isEmpty {
                emptyState
            } else {
                List(goals) { goal in
                    GoalRow(goal: goal, autonomyService: autonomyService, onChanged: reload)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 520, height: 400)
        .onAppear(perform: reload)
        .sheet(isPresented: $showCreate) {
            createSheet
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No goals yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Create a recurring behavior goal like \"Check my email every hour\"")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var createSheet: some View {
        VStack(spacing: 16) {
            Text("New Goal")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.caption).foregroundColor(.secondary)
                    TextField("What should the agent do?", text: $newDescription)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Completion Criteria (optional)").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. Summarize and save to a file", text: $newCriteria)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Interval (minutes, optional)").font(.caption).foregroundColor(.secondary)
                        TextField("e.g. 60", text: $newInterval)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Max Runs (optional)").font(.caption).foregroundColor(.secondary)
                        TextField("e.g. 10", text: $newMaxRuns)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Priority: \(newPriority)").font(.caption).foregroundColor(.secondary)
                    Slider(value: Binding(get: { Double(newPriority) }, set: { newPriority = Int($0) }), in: 0...10, step: 1)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showCreate = false
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    createGoal()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDescription.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func createGoal() {
        let interval = Double(newInterval.trimmingCharacters(in: .whitespaces))
        let maxRuns = Int(newMaxRuns.trimmingCharacters(in: .whitespaces))
        let criteria = newCriteria.trimmingCharacters(in: .whitespaces)
        _ = autonomyService.createGoal(
            description: newDescription.trimmingCharacters(in: .whitespaces),
            criteria: criteria.isEmpty ? nil : criteria,
            priority: newPriority,
            intervalMinutes: interval,
            maxRuns: maxRuns
        )
        newDescription = ""
        newCriteria = ""
        newInterval = ""
        newMaxRuns = ""
        newPriority = 5
        showCreate = false
        reload()
    }

    private func reload() {
        goals = autonomyService.goals()
    }
}

private struct GoalRow: View {
    let goal: PersistedGoal
    let autonomyService: AutonomyService
    let onChanged: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    statusBadge(goal.status)

                    if let interval = goal.intervalMinutes {
                        Text("Every \(Int(interval))m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("\(goal.runCount) runs")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let next = goal.nextRunAt, goal.status == .active {
                        Text("Next: \(next, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if goal.status == .active {
                Button { pause() } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(.plain)
                .help("Pause")
            } else if goal.status == .paused {
                Button { resume() } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.plain)
                .help("Resume")
            }

            if goal.status != .completed {
                Button { complete() } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.plain)
                .foregroundColor(.green)
                .help("Mark Complete")
            }

            Button { delete() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .help("Delete")
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func statusBadge(_ status: GoalStatus) -> some View {
        let color: Color = switch status {
        case .active: .green
        case .paused: .orange
        case .completed: .blue
        case .failed: .red
        }
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }

    private func pause() {
        autonomyService.pauseGoal(id: goal.id)
        onChanged()
    }

    private func resume() {
        autonomyService.resumeGoal(id: goal.id)
        onChanged()
    }

    private func complete() {
        autonomyService.completeGoal(id: goal.id)
        onChanged()
    }

    private func delete() {
        autonomyService.deleteGoal(id: goal.id)
        onChanged()
    }
}
