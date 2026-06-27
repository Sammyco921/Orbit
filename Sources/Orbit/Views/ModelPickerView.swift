import SwiftUI

struct ModelPickerView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var showingParameters = false

    var body: some View {
        let config = orchestrator.activeConversationConfig()
        let label: String = {
            if let c = config {
                return "\(c.providerType.displayName) · \(c.model)"
            }
            return "\(orchestrator.settings.providerType.displayName) (global)"
        }()

        HStack(spacing: 4) {
            Menu(label) {
                Section("OpenAI") {
                    modelButton("gpt-4o", provider: .openAI, current: config)
                    modelButton("gpt-4o-mini", provider: .openAI, current: config)
                    modelButton("gpt-4-turbo", provider: .openAI, current: config)
                }
                Section("Anthropic") {
                    modelButton("claude-sonnet-4-20250514", provider: .anthropic, current: config)
                    modelButton("claude-haiku-3-5-sonnet-20241022", provider: .anthropic, current: config)
                    modelButton("claude-opus-4-20250514", provider: .anthropic, current: config)
                }
                Section("Local") {
                    modelButton(orchestrator.settings.localModelName, provider: .local, current: config)
                    Divider()
                    modelButton("qwen3:4b", provider: .local, current: config)
                }
                Divider()
                Button("Use Global Default") {
                    setConfig(nil)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                showingParameters.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Model parameters")
            .popover(isPresented: $showingParameters) {
                parametersPopover
            }
        }
    }

    @ViewBuilder
    private var parametersPopover: some View {
        let config = orchestrator.activeConversationConfig()
        let params = config?.parameters ?? ModelParameters()

        VStack(alignment: .leading, spacing: 12) {
            Text("Model Parameters")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                        .font(.caption)
                    Spacer()
                    Text(params.temperature.map { String(format: "%.2f", $0) } ?? "default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: binding(for: \.temperature, default: 1.0),
                    in: 0...2,
                    step: 0.05
                ) {
                    Text("Temperature")
                } onEditingChanged: { _ in
                    saveParams()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Tokens")
                        .font(.caption)
                    Spacer()
                    Text(params.maxTokens.map { "\($0)" } ?? "default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding<Double>(
                        get: { Double(params.maxTokens ?? 4096) },
                        set: { newMax in
                            var p = currentParams()
                            p.maxTokens = Int(newMax)
                            p.maxTokens = max(256, min(p.maxTokens ?? 4096, 16384))
                            setParams(p)
                        }
                    ),
                    in: 256...16384,
                    step: 256
                ) {
                    Text("Max Tokens")
                } onEditingChanged: { _ in
                    saveParams()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Top P")
                        .font(.caption)
                    Spacer()
                    Text(params.topP.map { String(format: "%.2f", $0) } ?? "default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: binding(for: \.topP, default: 1.0),
                    in: 0...1,
                    step: 0.05
                ) {
                    Text("Top P")
                } onEditingChanged: { _ in
                    saveParams()
                }
            }

            Divider()

            Button("Reset to Defaults") {
                guard let id = orchestrator.activeConversationId,
                      let idx = orchestrator.conversations.firstIndex(where: { $0.id == id })
                else { return }
                orchestrator.conversations[idx].modelConfig?.parameters = nil
                orchestrator.saveConversations()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.accentColor)
        }
        .padding()
        .frame(width: 240)
    }

    private func currentParams() -> ModelParameters {
        guard let id = orchestrator.activeConversationId,
              let idx = orchestrator.conversations.firstIndex(where: { $0.id == id })
        else { return ModelParameters() }
        return orchestrator.conversations[idx].modelConfig?.parameters ?? ModelParameters()
    }

    private func setParams(_ params: ModelParameters) {
        guard let id = orchestrator.activeConversationId,
              let idx = orchestrator.conversations.firstIndex(where: { $0.id == id })
        else { return }
        if orchestrator.conversations[idx].modelConfig == nil {
            orchestrator.conversations[idx].modelConfig = ModelConfig(
                providerType: orchestrator.settings.providerType,
                model: ModelConfig.localDefault(from: orchestrator.settings)
            )
        }
        orchestrator.conversations[idx].modelConfig?.parameters = params
    }

    private func defaultModel(for type: ProviderType) -> String {
        type == .local
            ? ModelConfig.localDefault(from: orchestrator.settings)
            : (ModelConfig.defaults[type] ?? "gpt-4o")
    }

    private func saveParams() {
        orchestrator.saveConversations()
    }

    private func binding(for keyPath: WritableKeyPath<ModelParameters, Double?>, default defaultValue: Double) -> Binding<Double> {
        Binding<Double>(
            get: {
                guard let id = orchestrator.activeConversationId,
                      let idx = orchestrator.conversations.firstIndex(where: { $0.id == id })
                else { return defaultValue }
                return orchestrator.conversations[idx].modelConfig?.parameters?[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                guard let id = orchestrator.activeConversationId,
                      let idx = orchestrator.conversations.firstIndex(where: { $0.id == id })
                else { return }
                if orchestrator.conversations[idx].modelConfig == nil {
                    orchestrator.conversations[idx].modelConfig = ModelConfig(
                        providerType: orchestrator.settings.providerType,
                        model: defaultModel(for: orchestrator.settings.providerType)
                    )
                }
                guard var config = orchestrator.conversations[idx].modelConfig else { return }
                let params = config.parameters ?? ModelParameters()
                config.parameters = params
                var p = params
                p[keyPath: keyPath] = newValue
                config.parameters = p
                orchestrator.conversations[idx].modelConfig = config
                orchestrator.saveConversations()
                orchestrator.provider = nil
            }
        )
    }

    private func modelButton(_ model: String, provider: ProviderType, current: ModelConfig?) -> some View {
        let isSelected = current?.providerType == provider && current?.model == model
        let globalModel: String = {
            if provider == .local {
                return ModelConfig.localDefault(from: orchestrator.settings)
            }
            return ModelConfig.defaults[provider] ?? ""
        }()
        let isGlobalDefault = current == nil
            && orchestrator.settings.providerType == provider
            && globalModel == model

        return Button {
            setConfig(ModelConfig(providerType: provider, model: model))
        } label: {
            HStack {
                Text(model)
                if isSelected {
                    Image(systemName: "checkmark")
                } else if isGlobalDefault {
                    Text("default").foregroundColor(.secondary).font(.caption)
                }
            }
        }
    }

    private func setConfig(_ config: ModelConfig?) {
        guard let id = orchestrator.activeConversationId,
              let idx = orchestrator.conversations.firstIndex(where: { $0.id == id })
        else { return }
        orchestrator.conversations[idx].modelConfig = config
        orchestrator.saveConversations()
        orchestrator.provider = nil
    }
}
