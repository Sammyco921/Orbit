import SwiftUI

struct WorkflowEditorView: View {
    let store: WorkflowStore
    @State var workflow: WorkflowDefinition
    let onChanged: () -> Void

    @State private var selectedTab = 0
    @State private var showAddStep = false
    @State private var showAddVariable = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Workflow Name", text: $workflow.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Save") {
                    store.saveDefinition(workflow)
                    onChanged()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)

            TextField("Description", text: $workflow.description)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Picker("", selection: $selectedTab) {
                Text("Steps (\(workflow.steps.count))").tag(0)
                Text("Variables (\(workflow.variables.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            switch selectedTab {
            case 0: stepsView
            case 1: variablesView
            default: Color.clear
            }
        }
        .frame(width: 500, height: 450)
    }

    // MARK: - Steps

    private var stepsView: some View {
        VStack(spacing: 0) {
            if workflow.steps.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No steps yet")
                        .foregroundColor(.secondary)
                    Text("Add tool calls that execute in sequence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                        StepRow(
                            step: step,
                            index: index,
                            onUpdate: { updated in
                                workflow.steps[index] = updated
                            },
                            onDelete: {
                                workflow.steps.remove(at: index)
                            },
                            onMoveUp: {
                                guard index > 0 else { return }
                                workflow.steps.swapAt(index, index - 1)
                            },
                            onMoveDown: {
                                guard index < workflow.steps.count - 1 else { return }
                                workflow.steps.swapAt(index, index + 1)
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }

            Divider()
            Button("Add Step") {
                showAddStep = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(8)
        }
        .sheet(isPresented: $showAddStep) {
            addStepSheet
        }
    }

    private var addStepSheet: some View {
        StepEditorView(
            step: Step(name: "", toolName: ""),
            isNew: true,
            onSave: { step in
                workflow.steps.append(step)
                showAddStep = false
            },
            onCancel: { showAddStep = false }
        )
    }

    // MARK: - Variables

    private var variablesView: some View {
        VStack(spacing: 0) {
            if workflow.variables.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No variables defined")
                        .foregroundColor(.secondary)
                    Text("Variables let you pass dynamic values into your workflow")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(workflow.variables.enumerated()), id: \.element.name) { index, v in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(v.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if v.required {
                                        Text("Required")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 4)
                                            .background(Color.red.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                }
                                if let desc = v.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let def = v.defaultValue {
                                    Text("Default: \(def)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button { workflow.variables.remove(at: index) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }

            Divider()
            Button("Add Variable") {
                showAddVariable = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(8)
        }
        .sheet(isPresented: $showAddVariable) {
            addVariableSheet
        }
    }

    private var addVariableSheet: some View {
        VariableEditorView(onSave: { variable in
            workflow.variables.append(variable)
            showAddVariable = false
        }, onCancel: { showAddVariable = false })
    }
}

// MARK: - Step Row

private struct StepRow: View {
    @State var step: Step
    let index: Int
    let onUpdate: (Step) -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var showEditor = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.name.isEmpty ? (step.toolName ?? "") : step.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(step.toolName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button { showEditor = true } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showEditor) {
            StepEditorView(
                step: step,
                isNew: false,
                onSave: { updated in
                    step = updated
                    onUpdate(updated)
                    showEditor = false
                },
                onCancel: { showEditor = false }
            )
        }
    }
}

// MARK: - Step Editor

private struct StepEditorView: View {
    @State var step: Step
    let isNew: Bool
    let onSave: (Step) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(isNew ? "Add Step" : "Edit Step")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step Name").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. Fetch Data", text: $step.name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool Name").font(.caption).foregroundColor(.secondary)
                    let toolNameBinding = Binding<String>(
                        get: { step.toolName ?? "" },
                        set: { step.toolName = $0 }
                    )
                    TextField("e.g. readFile", text: toolNameBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Input Mapping (variable → tool parameter)").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. content:text, path:filePath", text: Binding(
                        get: { step.inputMapping.map { "\($0.key):\($0.value)" }.joined(separator: ", ") },
                        set: { parseMapping($0, into: &step.inputMapping) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Output Mapping (tool key → variable)").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. content:result, path:savedPath", text: Binding(
                        get: { step.outputMapping.map { "\($0.key):\($0.value)" }.joined(separator: ", ") },
                        set: { parseMapping($0, into: &step.outputMapping) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Condition (optional, e.g. $variableName or $var == value)").font(.caption).foregroundColor(.secondary)
                    let conditionBinding = Binding<String>(
                        get: { step.condition ?? "" },
                        set: { step.condition = $0.isEmpty ? nil : $0 }
                    )
                    TextField("Leave empty to always run", text: conditionBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Retry Count").font(.caption).foregroundColor(.secondary)
                        TextField("0", value: $step.retryCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeout (seconds)").font(.caption).foregroundColor(.secondary)
                        let timeoutBinding = Binding<Double>(
                            get: { step.timeoutSeconds ?? 0 },
                            set: { step.timeoutSeconds = $0 == 0 ? nil : $0 }
                        )
                        TextField("Optional", value: timeoutBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button(isNew ? "Add" : "Save") {
                    onSave(step)
                }
                .buttonStyle(.borderedProminent)
                .disabled(step.name.trimmingCharacters(in: .whitespaces).isEmpty || (step.toolName ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func parseMapping(_ text: String, into dict: inout [String: String]) {
        dict = [:]
        let pairs = text.components(separatedBy: ",")
        for pair in pairs {
            let parts = pair.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                dict[parts[0]] = parts[1]
            }
        }
    }
}

// MARK: - Variable Editor

private struct VariableEditorView: View {
    @State private var name = ""
    @State private var description = ""
    @State private var defaultValue = ""
    @State private var required = false
    let onSave: (WorkflowVariable) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Variable")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Variable Name").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. userInput", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description (optional)").font(.caption).foregroundColor(.secondary)
                    TextField("What is this variable for?", text: $description)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Value (optional)").font(.caption).foregroundColor(.secondary)
                    TextField("", text: $defaultValue)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Required", isOn: $required)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Add") {
                    let v = WorkflowVariable(
                        name: name.trimmingCharacters(in: .whitespaces),
                        defaultValue: defaultValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : defaultValue,
                        description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description,
                        required: required
                    )
                    onSave(v)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
