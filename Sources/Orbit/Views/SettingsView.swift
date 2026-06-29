import SwiftUI

enum LaunchStep {
    case idle
    case detecting
    case connecting
    case connected
    case failed(String)
}

public struct SettingsView: View {
    @Environment(Orchestrator.self) private var orchestrator

    @State private var isDiscovering = true
    @State private var runningServers: [RunningServer] = []
    @State private var discoveredModels: [DiscoveredModel] = []
    @State private var selectedModel: DiscoveredModel?
    @State private var isLaunching = false
    @State private var launchError: String?
    @State private var launchStep: LaunchStep = .idle

    @State private var discoveryResult: DiscoveryResult?
    @State private var isPulling = false
    @State private var pullMessages: [String] = []

    @State private var showChangeSheet = false
    @State private var showOnboarding = false
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    private let modelManager = LocalModelManager()

    enum ConnectionTestResult: Equatable {
        case success
        case failed(String)
    }

    public init() {}

    private var providerIsRemote: Bool {
        orchestrator.settings.providerType == .openAI || orchestrator.settings.providerType == .anthropic
    }

    private var providerIsLocal: Bool {
        orchestrator.settings.providerType == .local
    }

    private var hasKey: Bool {
        switch orchestrator.settings.providerType {
        case .openAI: !orchestrator.settings.openAIKey.isEmpty
        case .anthropic: !orchestrator.settings.anthropicKey.isEmpty
        default: false
        }
    }

    private var isReady: Bool {
        if case .connected = launchStep { return true }
        return !runningServers.isEmpty || (providerIsRemote && hasKey)
    }

    private var activeModelName: String? {
        if case .connected = launchStep, let m = selectedModel { return m.name }
        if !runningServers.isEmpty { return runningServers[0].detectedModel ?? runningServers[0].name }
        if providerIsRemote {
            let config = orchestrator.activeConversationConfig()
            return config?.model ?? ModelConfig.defaults[orchestrator.settings.providerType]
        }
        return nil
    }

    private var activeProviderLabel: String {
        if case .connected = launchStep { return "Running locally" }
        if !runningServers.isEmpty { return "Running locally" }
        if orchestrator.settings.providerType == .openAI { return "Connected to OpenAI" }
        if orchestrator.settings.providerType == .anthropic { return "Connected to Anthropic" }
        return ""
    }

    private var activeProviderBadge: String {
        providerIsLocal ? "Local" : "Cloud"
    }

    private var activeSecondaryInfo: String? {
        if case .connected = launchStep, let m = selectedModel {
            return m.serverURL
        }
        if let server = runningServers.first {
            return server.baseURL
        }
        return nil
    }

    private var isConnecting: Bool {
        if case .connecting = launchStep { return true }
        return false
    }

    private func cancelConnecting() {
        isLaunching = false
        launchStep = .idle
        launchError = nil
    }

    private func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        defer { isTestingConnection = false }

        let session = URLSession(configuration: .ephemeral)

        do {
            if case .connected = launchStep, let url = selectedModel?.serverURL ?? runningServers.first?.baseURL {
                let request = URLRequest(url: URL(string: "\(url)/api/tags")!, timeoutInterval: 5)
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    connectionTestResult = .failed("Server returned unexpected status")
                    return
                }
            } else if orchestrator.settings.providerType == .openAI {
                let key = orchestrator.settings.openAIKey
                guard !key.isEmpty else {
                    connectionTestResult = .failed("No API key configured")
                    return
                }
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models?limit=1")!, timeoutInterval: 5)
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    connectionTestResult = .failed("OpenAI API returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return
                }
            } else if orchestrator.settings.providerType == .anthropic {
                let key = orchestrator.settings.anthropicKey
                guard !key.isEmpty else {
                    connectionTestResult = .failed("No API key configured")
                    return
                }
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!, timeoutInterval: 5)
                request.setValue("\(key)", forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    connectionTestResult = .failed("Anthropic API returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return
                }
            } else {
                connectionTestResult = .failed("No active model to test")
                return
            }
            connectionTestResult = .success
        } catch {
            connectionTestResult = .failed(error.localizedDescription)
        }
    }

    // MARK: - Body

    public var body: some View {
        Form {
            modelStatusSection

            Section("Cross-Conversation Memory") {
                Toggle("Let the agent learn from all conversations", isOn: Bindable(orchestrator).settings.enableCrossConversationMemory)
                    .font(.caption)
                Text("When enabled, the agent remembers preferences, frequently used tools, and extracted facts across conversations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("API Server") {
                Toggle("Enable HTTP API", isOn: Bindable(orchestrator).settings.apiEnabled)
                    .font(.caption)
                if orchestrator.settings.apiEnabled {
                    SecureField("API Key", text: Bindable(orchestrator).settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: Bindable(orchestrator).settings.apiPort, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("The API listens on 127.0.0.1. Use the API key in the Authorization header.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Advanced") {
                Picker("Provider", selection: Bindable(orchestrator).settings.providerType) {
                    ForEach(ProviderType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)

                if orchestrator.settings.providerType == .openAI {
                    SecureField("OpenAI API Key", text: Bindable(orchestrator).settings.openAIKey)
                        .textFieldStyle(.roundedBorder)
                }

                if orchestrator.settings.providerType == .anthropic {
                    SecureField("Anthropic API Key", text: Bindable(orchestrator).settings.anthropicKey)
                        .textFieldStyle(.roundedBorder)
                }

                if orchestrator.settings.providerType == .local {
                    HStack {
                        Text("Server URL")
                        Spacer()
                        TextField("http://localhost:11434", text: Bindable(orchestrator).settings.localModelURL)
                            .frame(width: 180)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Model Name")
                        Spacer()
                        TextField("llama3", text: Bindable(orchestrator).settings.localModelName)
                            .frame(width: 180)
                            .textFieldStyle(.roundedBorder)
                    }
                    advancedLocalContent
                }
            }

            Section("Development") {
                Toggle("Development Mode", isOn: Bindable(orchestrator).settings.isDevelopmentMode)
                    .font(.caption)
                Text("When enabled, plugins are reloaded when settings change.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("System Integration") {
                Toggle("Launch at Login", isOn: Bindable(orchestrator).settings.launchAtLogin)
                    .font(.caption)
                Text("Orbit will start automatically when you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Onboarding") {
                HStack {
                    Text("Replay onboarding")
                        .font(.caption)
                    Spacer()
                    Button("Start Onboarding") {
                        orchestrator.settings.hasCompletedOnboarding = false
                        showOnboarding = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text("Show the first-run introduction screens again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Apply") {
                    orchestrator.applySettings()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Orbit Settings")
        .onAppear {
            startDiscovery()
        }
        .onChange(of: orchestrator.settings.providerType) { _, _ in
            startDiscovery()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingFlowView {
                showOnboarding = false
            }
            .frame(width: 520, height: 560)
        }
        .sheet(isPresented: $showChangeSheet) {
            ChangeModelSheet(
                isDiscovering: $isDiscovering,
                discoveredModels: $discoveredModels,
                runningServers: $runningServers,
                selectedModel: $selectedModel,
                discoveryResult: $discoveryResult,
                launchStep: $launchStep,
                isPulling: $isPulling,
                pullMessages: $pullMessages,
                modelManager: modelManager,
                startDiscovery: startDiscovery,
                launchSelected: launchSelected,
                pullModel: pullModel,
                formatSize: formatSize
            )
        }
    }

    // MARK: - Model Status Card

    @ViewBuilder
    private var modelStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    statusIcon
                        .font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        statusTitle
                            .font(.system(size: 14, weight: .semibold))
                        if isReady {
                            Text(activeProviderLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                providerBadge
                                if let model = activeModelName {
                                    Text(model)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .padding(.top, 1)
                            Text("Orbit is ready to process requests.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        } else {
                            statusDetail
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                Divider()

                HStack(spacing: 8) {
                    primaryStatusButton
                    if isReady {
                        testConnectionButton
                    } else {
                        demoModeButton
                    }
                    Spacer()
                    if isReady, activeSecondaryInfo != nil {
                        Text(activeSecondaryInfo!)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
            .background(Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orbitBorder, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } header: {
            Label(OrbitVoice.Settings.modelStatus, systemImage: "cpu")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    @ViewBuilder
    private var providerBadge: some View {
        Text(activeProviderBadge)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(providerIsLocal ? .orbitAccent : .orbitSuccess)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                (providerIsLocal ? Color.orbitAccent : Color.orbitSuccess).opacity(0.12)
            )
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var primaryStatusButton: some View {
        if isDiscovering {
            Button(OrbitVoice.Settings.scanning) {}
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)
        } else if isConnecting {
            Button("Cancel") {
                cancelConnecting()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if isReady {
            Button("Change Model") {
                showChangeSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button("Set Up Model") {
                showChangeSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var testConnectionButton: some View {
        if isTestingConnection {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
        } else if let result = connectionTestResult {
            switch result {
            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .failed(let msg):
                Button(OrbitVoice.Settings.failedRetry) {
                    Task { await testConnection() }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.orange)
                .help(msg)
            }
        } else {
            Button(OrbitVoice.Settings.testConnection) {
                Task { await testConnection() }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isDiscovering {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
        } else if case .connecting = launchStep {
            ProgressView()
                .controlSize(.small)
        } else if isReady {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18))
        } else {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusTitle: some View {
        if isDiscovering {
            Text(OrbitVoice.Settings.scanning)
        } else if case .connecting = launchStep {
            Text(OrbitVoice.Status.connecting)
        } else if isReady {
            Text(OrbitVoice.Settings.ready)
        } else {
            Text(OrbitVoice.Settings.needsSetup)
        }
    }

    @ViewBuilder
    private var demoModeButton: some View {
        Button {
            orchestrator.settings.providerType = .local
            orchestrator.settings.localModelURL = "http://localhost:11434"
            orchestrator.settings.localModelName = "demo"
            orchestrator.applySettings()
            launchStep = .connected
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                Text("Try Demo Mode")
                    .font(.caption2)
            }
            .foregroundStyle(.orbitAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orbitAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Run Orbit without a model using echo responses")
    }

    @ViewBuilder
    private var statusDetail: some View {
        if isDiscovering {
            Text("Looking for local model servers")
        } else if case .connecting = launchStep {
            Text("Connecting to model server")
        } else if !discoveredModels.isEmpty {
            Text("\(discoveredModels.count) model\(discoveredModels.count > 1 ? "s" : "") available \u{2014} select one to get started")
        } else if let result = discoveryResult, result.ollamaIsInstalled || result.ollamaAppIsInstalled {
            Text("Ollama installed \u{2014} pull a model to get started")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Install Ollama to run models locally.")
                    .font(.caption)
                Text("Or connect an API provider in Advanced settings.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("You can also try demo mode to test Orbit without a model.")
                    .font(.caption2)
                    .foregroundStyle(.orbitAccent)
            }
        }
    }

    // MARK: - Advanced Local Content

    @ViewBuilder
    private var advancedLocalContent: some View {
        if isDiscovering {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning for local models\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !runningServers.isEmpty {
            ForEach(runningServers) { server in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("\(server.detectedModel ?? server.name) on \(server.baseURL)")
                        .font(.caption)
                }
            }
        } else if !discoveredModels.isEmpty {
            ForEach(discoveredModels) { model in
                HStack {
                    Text(model.name)
                        .font(.caption)
                    if let size = model.size {
                        Text(formatSize(size))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Launch") {
                        selectedModel = model
                        Task { await launchSelected() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } else if let result = discoveryResult, result.ollamaIsInstalled || result.ollamaAppIsInstalled {
            if isPulling {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Pulling \(LocalModelManager.suggestedModel)\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let last = pullMessages.last {
                    Text(last)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                Button("Cancel") {
                    modelManager.cancelPull()
                    isPulling = false
                    pullMessages = []
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                HStack {
                    Text(OrbitVoice.Settings.noModelsDownloaded)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Install \(LocalModelManager.suggestedModel)") {
                        Task { await pullModel() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } else {
            HStack {
                Text("Ollama not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(OrbitVoice.Settings.installOllama) {
                    NSWorkspace.shared.open(URL(string: "https://ollama.ai")!)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    // MARK: - Discovery

    private func startDiscovery() {
        isDiscovering = true
        runningServers = []
        discoveredModels = []
        selectedModel = nil
        launchStep = .idle
        pullMessages = []
        isPulling = false
        connectionTestResult = nil

        Task {
            let result = await modelManager.discoverAll()
            discoveryResult = result
            runningServers = result.servers
            discoveredModels = result.models

            if result.servers.isEmpty, let first = result.models.first {
                selectedModel = first
            } else if let first = result.servers.first {
                selectedModel = DiscoveredModel(
                    id: first.baseURL,
                    name: first.detectedModel ?? first.name,
                    source: .serverDetected,
                    serverURL: first.baseURL,
                    size: nil
                )
            }
            isDiscovering = false
        }
    }

    // MARK: - Pull Model

    private func pullModel() async {
        isPulling = true
        pullMessages = []

        do {
            for try await message in modelManager.pullModel(name: LocalModelManager.suggestedModel) {
                await MainActor.run {
                    pullMessages.append(message)
                }
            }
            await MainActor.run {
                isPulling = false
                startDiscovery()
            }
        } catch {
            await MainActor.run {
                pullMessages.append("Error: \(error.localizedDescription)")
                isPulling = false
            }
        }
    }

    // MARK: - Launch

    private func launchSelected() async {
        guard let model = selectedModel else { return }
        switch model.source {
        case .ollamaInstalled:
            await launchOllamaModel(model)
        case .ggufFile:
            await launchGGUFModel(model)
        case .ollamaRunning, .serverDetected:
            connectToModel(name: model.name, url: model.serverURL ?? "http://localhost:11434")
        }
    }

    private func launchOllamaModel(_ model: DiscoveredModel) async {
        isLaunching = true
        launchStep = .connecting
        launchError = nil

        do {
            try await modelManager.launchOllamaServe()
            let ok = await modelManager.waitForServer(url: "http://localhost:11434")
            if ok {
                orchestrator.settings.localModelURL = "http://localhost:11434"
                orchestrator.settings.localModelName = model.name
                orchestrator.settings.localAPIType = LocalAPIType.ollama.rawValue
                orchestrator.settings.providerType = .local
                orchestrator.applySettings()
                launchStep = .connected
            } else {
                launchStep = .failed("Ollama started but not responding on port 11434")
            }
        } catch {
            launchStep = .failed(error.localizedDescription)
        }
        isLaunching = false
    }

    private func launchGGUFModel(_ model: DiscoveredModel) async {
        isLaunching = true
        launchStep = .connecting
        launchError = nil

        do {
            let path = model.id
            try await modelManager.launchLlamaCppServer(modelPath: path)
            let ok = await modelManager.waitForServer(url: "http://localhost:8080")
            if ok {
                orchestrator.settings.localModelURL = "http://localhost:8080"
                orchestrator.settings.localModelName = model.name
                orchestrator.settings.localAPIType = LocalAPIType.openAICompatible.rawValue
                orchestrator.settings.providerType = .local
                orchestrator.applySettings()
                launchStep = .connected
            } else {
                launchStep = .failed("llama.cpp started but not responding on port 8080")
            }
        } catch {
            launchStep = .failed(error.localizedDescription)
        }
        isLaunching = false
    }

    private func connectToModel(name: String, url: String) {
        orchestrator.settings.localModelURL = url
        orchestrator.settings.localModelName = name
        orchestrator.settings.providerType = .local
        orchestrator.applySettings()
        launchStep = .connected
    }

    private func selectAndConnect(_ model: DiscoveredModel, apiType: LocalAPIType, baseURL: String) {
        selectedModel = model
        let mappedType: LocalAPIType = apiType == .ollama ? .ollama : .openAICompatible
        orchestrator.settings.localModelURL = baseURL
        orchestrator.settings.localModelName = model.name
        orchestrator.settings.localAPIType = mappedType.rawValue
        orchestrator.settings.providerType = .local
        launchStep = .connecting

        Task {
            let connected = await modelManager.waitForServer(url: baseURL, timeout: 5)
            if connected {
                launchStep = .connected
                orchestrator.applySettings()
            } else {
                launchStep = .failed("Could not connect to \(baseURL)")
            }
        }
    }

    // MARK: - Helpers

    private func formatSize(_ bytes: Int64) -> String {
        if bytes > 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }
}

// MARK: - Change Model Sheet

private struct ChangeModelSheet: View {
    @Environment(Orchestrator.self) private var orchestrator
    @Environment(\.dismiss) private var dismiss

    @Binding var isDiscovering: Bool
    @Binding var discoveredModels: [DiscoveredModel]
    @Binding var runningServers: [RunningServer]
    @Binding var selectedModel: DiscoveredModel?
    @Binding var discoveryResult: DiscoveryResult?
    @Binding var launchStep: LaunchStep
    @Binding var isPulling: Bool
    @Binding var pullMessages: [String]

    let modelManager: LocalModelManager
    let startDiscovery: () -> Void
    let launchSelected: () async -> Void
    let pullModel: () async -> Void
    let formatSize: (Int64) -> String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Change Model")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            Form {
                Section("Provider") {
                    Picker("Provider", selection: Bindable(orchestrator).settings.providerType) {
                        ForEach(ProviderType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if orchestrator.settings.providerType == .openAI {
                        SecureField("OpenAI API Key", text: Bindable(orchestrator).settings.openAIKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    if orchestrator.settings.providerType == .anthropic {
                        SecureField("Anthropic API Key", text: Bindable(orchestrator).settings.anthropicKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if orchestrator.settings.providerType == .local {
                    Section("Local Models") {
                        localModelContent
                    }
                }

                Section {
                    Button("Apply") {
                        orchestrator.applySettings()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 400)
        .background(Color.orbitBackground)
    }

    @ViewBuilder
    private var localModelContent: some View {
        if isDiscovering {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning for local models\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !runningServers.isEmpty {
            ForEach(runningServers) { server in
                Button {
                    selectedModel = DiscoveredModel(
                        id: server.baseURL,
                        name: server.detectedModel ?? server.name,
                        source: .serverDetected,
                        serverURL: server.baseURL,
                        size: nil
                    )
                    Task { await launchSelected() }
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(server.detectedModel ?? server.name)
                                .font(.subheadline)
                            Text(server.baseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    Text(OrbitVoice.Settings.connected)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } else if !discoveredModels.isEmpty {
            ForEach(discoveredModels) { model in
                Button {
                    selectedModel = model
                    Task { await launchSelected() }
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name)
                                .font(.subheadline)
                            HStack(spacing: 4) {
                                Text(model.source.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let size = model.size {
                                    Text(formatSize(size))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } else if let result = discoveryResult, result.ollamaIsInstalled || result.ollamaAppIsInstalled {
            if isPulling {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Pulling \(LocalModelManager.suggestedModel)\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let last = pullMessages.last {
                        Text(last)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    Button("Cancel") {
                        modelManager.cancelPull()
                        isPulling = false
                        pullMessages = []
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No models downloaded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Install \(LocalModelManager.suggestedModel)") {
                        Task { await pullModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ollama is not installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(OrbitVoice.Settings.installOllama) {
                    NSWorkspace.shared.open(URL(string: "https://ollama.ai")!)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}
