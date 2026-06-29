import SwiftUI

struct WorkflowListView: View {
    let store: WorkflowStore
    let engine: WorkflowEngine
    @State private var workflows: [WorkflowDefinition] = []
    @State private var showEditor = false
    @State private var editingWorkflow: WorkflowDefinition?
    @State private var showNewSheet = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workflows")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("New Workflow") {
                    showNewSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            if workflows.isEmpty {
                emptyState
            } else {
                List(workflows) { wf in
                    WorkflowRow(workflow: wf, engine: engine, store: store, onEdit: {
                        editingWorkflow = wf
                        showEditor = true
                    }, onChanged: reload)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 560, height: 420)
        .onAppear(perform: reload)
        .sheet(isPresented: $showNewSheet) {
            newWorkflowSheet
        }
        .sheet(isPresented: $showEditor) {
            if let wf = editingWorkflow {
                WorkflowEditorView(store: store, workflow: wf, onChanged: {
                    editingWorkflow = nil
                    reload()
                })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No workflows yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Create multi-step workflows that chain tool calls together.\nWorkflows can be invoked by the agent as a single tool.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newWorkflowSheet: some View {
        VStack(spacing: 16) {
            Text("New Workflow")
                .font(.title2)
                .fontWeight(.semibold)
            TextField("Workflow name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Button("Cancel") { showNewSheet = false }
                    .buttonStyle(.bordered)
                Button("Create") {
                    let wf = WorkflowDefinition(name: newName.trimmingCharacters(in: .whitespaces))
                    store.saveDefinition(wf)
                    newName = ""
                    showNewSheet = false
                    reload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func reload() {
        workflows = store.allDefinitions()
    }
}

private struct WorkflowRow: View {
    let workflow: WorkflowDefinition
    let engine: WorkflowEngine
    let store: WorkflowStore
    let onEdit: () -> Void
    let onChanged: () -> Void

    @State private var showRunOutput = false
    @State private var runOutput = ""

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(workflow.steps.count) steps · \(workflow.variables.count) variables")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !workflow.description.isEmpty {
                    Text(workflow.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button { runNow() } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .foregroundColor(.green)
            .help("Run Now")
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit")
            Button { delete() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .help("Delete")
        }
        .padding(.vertical, 6)
        .alert("Workflow Output", isPresented: $showRunOutput) {
            Button("OK") {}
        } message: {
            Text(runOutput)
        }
    }

    private func runNow() {
        Task {
            do {
                let execution = try await engine.execute(definition: workflow)
                var output = "Status: \(execution.status.rawValue)"
                if let err = execution.error {
                    output += "\nError: \(err)"
                }
                for (stepId, result) in execution.stepResults {
                    output += "\n\nStep \(stepId.prefix(8)):\n\(result.prefix(300))"
                }
                runOutput = output
            } catch {
                runOutput = "Failed: \(error.localizedDescription)"
            }
            showRunOutput = true
        }
    }

    private func delete() {
        store.deleteDefinition(id: workflow.id)
        onChanged()
    }
}
