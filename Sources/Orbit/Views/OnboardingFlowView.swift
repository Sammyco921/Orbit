import SwiftUI

struct OnboardingFlowView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var currentStep = 0
    @State private var detectedProvider: DetectedProvider?
    @State private var apiKeyOpenAI = ""
    @State private var apiKeyAnthropic = ""
    @State private var selectedProvider: ProviderType = .local
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isDetecting = true

    let onComplete: () -> Void

    private enum ConnectionStatus: Equatable {
        case idle, testing, success(String), failed(String)
        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.testing, .testing): return true
            case (.success(let a), .success(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    private struct DetectedProvider {
        let name: String
        let baseURL: String
        let apiType: LocalAPIType
        let model: String
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack {
                Spacer()
                Button("Skip") {
                    complete()
                }
                .buttonStyle(.plain)
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitTertiary)
                .padding(.trailing, Spacing.lg)
            }

            Spacer().frame(height: 40)

            VStack(spacing: 28) {
                stepContent
                    .frame(maxWidth: 420)
                    .id(currentStep)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
            }
            .padding(32)
            .background(Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orbitBorder, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.lg)

            Spacer().frame(height: 24)

            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Spacer()

                Button(currentStep >= stepCount - 1 ? "Start Using Orbit" : "Continue") {
                    if currentStep >= stepCount - 1 {
                        complete()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(continueDisabled)
            }
            .frame(maxWidth: 420)

            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orbitBackground)
        .task { await detectProviders() }
    }

    private var stepCount: Int {
        detectedProvider != nil ? 3 : 4
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0: welcomeStep
        case 1: providerStep
        case 2: connectionStep
        case 3: readyStep
        default: welcomeStep
        }
    }

    private var continueDisabled: Bool {
        if currentStep == 1, detectedProvider == nil {
            return apiKeyOpenAI.isEmpty && apiKeyAnthropic.isEmpty
        }
        return false
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "orbit")
                .font(.system(size: 36))
                .foregroundStyle(.orbitAccent)

            Text("Welcome to Orbit")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orbitPrimary)

            Text("A system that turns intent into execution. Type what you need — Orbit handles the rest.")
                .font(.orbitBody)
                .foregroundStyle(.orbitSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Step 1: Provider Setup

    private var providerStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 28))
                .foregroundStyle(.orbitAccent)

            Text("Choose Your AI Provider")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orbitPrimary)

            if isDetecting {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning for local models...")
                    .font(.orbitBodySmall)
                    .foregroundStyle(.orbitTertiary)
            } else if let provider = detectedProvider {
                localDetectedView(provider)
            } else {
                manualSetupView
            }
        }
    }

    private func localDetectedView(_ provider: DetectedProvider) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.orbitSuccess)
                Text("Detected: \(provider.name)")
                    .font(.orbitBodySmall)
                    .foregroundStyle(.orbitSecondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.orbitSuccess.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Model: \(provider.model)")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)

            Picker("Provider", selection: $selectedProvider) {
                Text("Local (\(provider.name))").tag(ProviderType.local)
                Text("OpenAI").tag(ProviderType.openAI)
                Text("Anthropic").tag(ProviderType.anthropic)
            }
            .pickerStyle(.segmented)

            if selectedProvider == .openAI {
                TextField("OpenAI API Key", text: $apiKeyOpenAI)
                    .textFieldStyle(.roundedBorder)
                    .font(.orbitBodySmall)
            } else if selectedProvider == .anthropic {
                TextField("Anthropic API Key", text: $apiKeyAnthropic)
                    .textFieldStyle(.roundedBorder)
                    .font(.orbitBodySmall)
            }
        }
    }

    private var manualSetupView: some View {
        VStack(spacing: 12) {
            Text("No local provider detected. Connect a remote provider or start Ollama.")
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitSecondary)
                .multilineTextAlignment(.center)

            Picker("Provider", selection: $selectedProvider) {
                Text("OpenAI").tag(ProviderType.openAI)
                Text("Anthropic").tag(ProviderType.anthropic)
            }
            .pickerStyle(.segmented)

            if selectedProvider == .openAI {
                SecureField("sk-...", text: $apiKeyOpenAI)
                    .textFieldStyle(.roundedBorder)
                    .font(.orbitBodySmall)
            } else {
                SecureField("sk-ant-...", text: $apiKeyAnthropic)
                    .textFieldStyle(.roundedBorder)
                    .font(.orbitBodySmall)
            }
        }
    }

    // MARK: - Step 2: Connection Test

    private var connectionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(.orbitAccent)

            Text("Test Your Connection")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orbitPrimary)

            Text("Let's verify your provider is reachable before you get started.")
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitSecondary)
                .multilineTextAlignment(.center)

            Button(action: { Task { await testConnection() } }) {
                HStack {
                    if connectionStatus == .testing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(connectionButtonLabel)
                }
                .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(connectionStatus == .testing)

            switch connectionStatus {
            case .success(let msg):
                Label(msg, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.orbitSuccess)
                    .font(.orbitBodySmall)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.orbitError)
                    .font(.orbitBodySmall)
            default:
                EmptyView()
            }
        }
    }

    private var connectionButtonLabel: String {
        switch connectionStatus {
        case .idle: return "Test Connection"
        case .testing: return "Testing..."
        case .success: return "Connection OK — Test Again"
        case .failed: return "Retry Connection"
        }
    }

    // MARK: - Step 3: Ready

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orbitSuccess)

            Text("You're Ready")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orbitPrimary)

            Text("Orbit is configured and ready. Try typing something like \"List the files in this project\" or \"What's my system status?\"")
                .font(.orbitBody)
                .foregroundStyle(.orbitSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func detectProviders() async {
        isDetecting = true
        defer { isDetecting = false }

        let modelManager = LocalModelManager()
        let result = await modelManager.discoverAll()

        if let server = result.servers.first {
            detectedProvider = DetectedProvider(
                name: server.name,
                baseURL: server.baseURL,
                apiType: server.apiType,
                model: server.detectedModel ?? LocalModelManager.suggestedModel
            )
            orchestrator.settings.localModelURL = server.baseURL
            orchestrator.settings.localAPIType = server.apiType.rawValue
            orchestrator.settings.localModelName = detectedProvider?.model ?? LocalModelManager.suggestedModel
            orchestrator.settings.providerType = .local
        }
    }

    private func testConnection() async {
        connectionStatus = .testing

        if selectedProvider == .local {
            orchestrator.settings.providerType = .local
            if let config = detectedProvider {
                orchestrator.settings.localModelURL = config.baseURL
            }
        } else if selectedProvider == .openAI {
            orchestrator.settings.providerType = .openAI
            orchestrator.settings.openAIKey = apiKeyOpenAI
        } else {
            orchestrator.settings.providerType = .anthropic
            orchestrator.settings.anthropicKey = apiKeyAnthropic
        }

        orchestrator.runtime.llmService.resetProvider()
        let provider = orchestrator.runtime.llmService.currentProvider()

        do {
            _ = try await provider.complete(messages: [
                LLMMessage(role: .user, content: "Reply with exactly: OK")
            ])
            connectionStatus = .success("Provider responded successfully")
        } catch {
            connectionStatus = .failed("Connection failed: \(error.localizedDescription)")
        }
    }

    private func complete() {
        // Save any API keys that were entered
        if !apiKeyOpenAI.isEmpty {
            orchestrator.settings.openAIKey = apiKeyOpenAI
            orchestrator.settings.providerType = .openAI
        }
        if !apiKeyAnthropic.isEmpty {
            orchestrator.settings.anthropicKey = apiKeyAnthropic
            orchestrator.settings.providerType = .anthropic
        }
        orchestrator.settings.hasCompletedOnboarding = true
        onComplete()
    }
}

private struct OnboardingStep {
    let icon: String
    let title: String
    let body: String
}
