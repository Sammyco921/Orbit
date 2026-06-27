import SwiftUI
import OSLog
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.orbit", category: "plugin-browser")

struct PluginBrowserView: View {
    @Environment(Orchestrator.self) var orchestrator

    @State private var selectedTab = Tab.installed
    @State private var isShowingInstaller = false
    @State private var selection: String?
    @State private var registryPlugins: [RegistryPlugin] = []
    @State private var isFetching = false
    @State private var registryError: String?
    @State private var registryErrorDetail: String?
    @State private var searchText = ""
    @State private var selectedCategory: String?

    // Permission approval
    @State private var pendingPlugin: RegistryPlugin?
    @State private var showPermissionSheet = false

    // Error alerts
    @State private var showErrorAlert = false
    @State private var errorAlertMessage = ""

    enum Tab: String, CaseIterable {
        case installed = "Installed"
        case browse = "Browse"

        var icon: String {
            switch self {
            case .installed: return "tray.full"
            case .browse: return "globe"
            }
        }
    }

    private var plugins: [Plugin] {
        orchestrator.runtime.pluginManager.plugins
    }

    private var availableUpdates: [PluginUpdateInfo] {
        orchestrator.runtime.pluginManager.availableUpdates
    }

    private var allCategories: [String] {
        let cats = registryPlugins.compactMap { $0.categories }.flatMap { $0 }
        return Array(Set(cats)).sorted()
    }

    private var filteredRegistryPlugins: [RegistryPlugin] {
        var result = registryPlugins
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.description.lowercased().contains(q) ||
                $0.id.lowercased().contains(q)
            }
        }
        if let cat = selectedCategory {
            result = result.filter { $0.categories?.contains(cat) ?? false }
        }
        result.sort { a, b in
            let aInstalled = plugins.contains(where: { $0.id == a.id })
            let bInstalled = plugins.contains(where: { $0.id == b.id })
            if aInstalled != bInstalled { return aInstalled }
            return a.name < b.name
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedTab {
            case .installed:
                installedView
            case .browse:
                browseView
            }
        }
        .frame(minWidth: 520, minHeight: 400)
        .fileImporter(isPresented: $isShowingInstaller, allowedContentTypes: [.json, .folder]) { result in
            handleInstall(result)
        }
        .task {
            if registryPlugins.isEmpty {
                await fetchRegistry()
            }
        }
        .alert("Install Plugin", isPresented: $showPermissionSheet, presenting: pendingPlugin) { regPlugin in
            Button("Cancel", role: .cancel) {
                pendingPlugin = nil
            }
            Button("Install") {
                pendingPlugin = nil
                Task { await installFromRegistry(regPlugin) }
            }
        } message: { regPlugin in
            Text(permissionSummary(for: regPlugin))
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorAlertMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Plugins").font(.headline)
            Spacer()

            if !availableUpdates.isEmpty {
                Button("\(availableUpdates.count) Update\(availableUpdates.count > 1 ? "s" : "")") {
                    Task { await applyAllUpdates() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button("Install…", systemImage: "plus") {
                isShowingInstaller = true
            }
            .buttonStyle(.borderless)
            .help("Install a plugin from plugin.json or a plugin directory")
        }
        .padding()
    }

    // MARK: - Installed Tab

    @ViewBuilder
    private var installedView: some View {
        if plugins.isEmpty {
            emptyInstalledState
        } else {
            installedList
        }
    }

    private var emptyInstalledState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Plugins Installed")
                .font(.title3)
            Text("Browse the Orbit Official registry or install a plugin.json file.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Browse Registry") {
                selectedTab = .browse
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var installedList: some View {
        List(selection: $selection) {
            if !availableUpdates.isEmpty {
                Section("Updates Available") {
                    ForEach(availableUpdates, id: \.pluginId) { update in
                        updateRow(update)
                    }
                }
            }
            ForEach(plugins) { plugin in
                PluginRow(plugin: plugin, updateInfo: availableUpdates.first { $0.pluginId == plugin.id })
                    .contextMenu {
                        Button(plugin.isEnabled ? "Disable" : "Enable") {
                            togglePlugin(plugin)
                        }
                        if let update = availableUpdates.first(where: { $0.pluginId == plugin.id }) {
                            Button("Update to v\(update.availableVersion)") {
                                Task { await applyUpdate(update) }
                            }
                        }
                        if plugin.isRunning {
                            Button("Reload") {
                                orchestrator.runtime.pluginManager.unloadPlugin(plugin)
                                orchestrator.runtime.pluginManager.loadPlugin(plugin)
                            }
                        }
                        Divider()
                        Button("Uninstall", role: .destructive) {
                            orchestrator.runtime.pluginManager.uninstallPlugin(plugin)
                        }
                    }
            }
        }
    }

    private func updateRow(_ update: PluginUpdateInfo) -> some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(update.pluginId).fontWeight(.medium)
                Text("\(update.currentVersion) → \(update.availableVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Update") {
                Task { await applyUpdate(update) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Browse Tab

    @ViewBuilder
    private var browseView: some View {
        VStack(spacing: 0) {
            // Search + filter bar
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search plugins...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                if !allCategories.isEmpty {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All").tag(nil as String?)
                        ForEach(allCategories, id: \.self) { cat in
                            Text(cat).tag(cat as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await fetchRegistry(force: true) }
                }
                .buttonStyle(.borderless)
                .disabled(isFetching)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isFetching {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading registry...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if registryError != nil {
                registryErrorView
            } else if filteredRegistryPlugins.isEmpty {
                emptyRegistryState
            } else {
                registryList
            }
        }
    }

    private var registryErrorView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Could not load registry")
                .font(.title3)
            if let detail = registryErrorDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text(registryError ?? "Unknown error")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Retry") {
                    Task { await fetchRegistry(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
    }

    private var emptyRegistryState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No plugins match your search")
                .font(.title3)
            Text("Try a different search term or category.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var registryList: some View {
        List {
            ForEach(filteredRegistryPlugins) { regPlugin in
                RegistryPluginRow(
                    regPlugin: regPlugin,
                    isInstalled: plugins.contains(where: { $0.id == regPlugin.id }),
                    installAction: { beginInstall(regPlugin) }
                )
            }
        }
    }

    // MARK: - Actions

    private func fetchRegistry(force: Bool = false) async {
        isFetching = true
        registryError = nil
        registryErrorDetail = nil
        do {
            let index = try await orchestrator.runtime.pluginManager.registryService.fetchIndex(forceRefresh: force)
            registryPlugins = index.plugins
        } catch let error as PluginRegistryError {
            registryError = "Could not load registry"
            registryErrorDetail = error.localizedDescription
        } catch {
            registryError = "Could not load registry"
            registryErrorDetail = error.localizedDescription
        }
        isFetching = false
    }

    private func beginInstall(_ regPlugin: RegistryPlugin) {
        // Check Orbit version compatibility
        let registry = orchestrator.runtime.pluginManager.registryService.officialRegistry
        guard registry.isCompatible(requiredOrbitVersion: regPlugin.requiredOrbitVersion) else {
            showErrorAlertMessage("This plugin requires Orbit \(regPlugin.requiredOrbitVersion ?? "?") or later. You have \(OfficialPluginRegistry.currentOrbitVersion).")
            return
        }

        // If already approved, install directly
        if hasApprovedPermissions(for: regPlugin.id) {
            Task { await installFromRegistry(regPlugin) }
            return
        }

        // Show permission approval sheet
        pendingPlugin = regPlugin
        showPermissionSheet = true
    }

    private func installFromRegistry(_ regPlugin: RegistryPlugin) async {
        do {
            try await orchestrator.runtime.pluginManager.installFromRegistry(id: regPlugin.id, approvedPermissions: regPlugin.permissions)
        } catch let error as PluginRegistryError {
            showErrorAlertMessage(error.localizedDescription)
        } catch {
            showErrorAlertMessage(error.localizedDescription)
        }
    }

    private func applyUpdate(_ update: PluginUpdateInfo) async {
        do {
            try await orchestrator.runtime.pluginManager.applyUpdate(update)
        } catch let error as PluginRegistryError {
            showErrorAlertMessage(error.localizedDescription)
        } catch {
            showErrorAlertMessage(error.localizedDescription)
        }
    }

    private func applyAllUpdates() async {
        for update in availableUpdates {
            await applyUpdate(update)
        }
    }

    private func togglePlugin(_ plugin: Plugin) {
        if plugin.isEnabled {
            orchestrator.runtime.pluginManager.disablePlugin(plugin)
        } else {
            orchestrator.runtime.pluginManager.enablePlugin(plugin)
        }
    }

    private func handleInstall(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        do {
            if isDir.boolValue {
                try orchestrator.runtime.pluginManager.installPlugin(fromDirectory: url)
            } else {
                try orchestrator.runtime.pluginManager.installPlugin(from: url)
            }
            orchestrator.runtime.pluginManager.discover()
        } catch {
            log.error("Failed to install plugin: \(error.localizedDescription)")
        }
    }

    private func showErrorAlertMessage(_ message: String) {
        errorAlertMessage = message
        showErrorAlert = true
    }

    private func permissionSummary(for plugin: RegistryPlugin) -> String {
        var parts = ["\"\(plugin.name)\" requires the following permissions:\n"]
        for permission in plugin.permissions {
            parts.append("• \(permission.title): \(permission.summary)")
        }
        parts.append("\nDo you want to install this plugin?")
        return parts.joined(separator: "\n")
    }
}

// MARK: - Plugin Row (installed)

private struct PluginRow: View {
    let plugin: Plugin
    let updateInfo: PluginUpdateInfo?

    var body: some View {
        HStack {
            Image(systemName: plugin.isRunning ? "circle.fill" : "circle.slash")
                .foregroundStyle(plugin.isRunning ? .green : .secondary)
                .help(plugin.isRunning ? "Running" : "Stopped")

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name).fontWeight(.medium)
                Text(plugin.manifest.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let update = updateInfo {
                Button("v\(update.availableVersion)") {
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Update available: \(update.currentVersion) → \(update.availableVersion)")
            }

            if !plugin.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("v\(plugin.manifest.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(plugin.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Registry Plugin Row

private struct RegistryPluginRow: View {
    let regPlugin: RegistryPlugin
    let isInstalled: Bool
    let installAction: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(regPlugin.name).fontWeight(.medium)
                    Text("Orbit Official")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .cornerRadius(4)
                }
                Text(regPlugin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let author = regPlugin.author {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let cats = regPlugin.categories, !cats.isEmpty {
                        ForEach(cats.prefix(3), id: \.self) { cat in
                            Text(cat)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(3)
                        }
                    }
                    if let requiredVersion = regPlugin.requiredOrbitVersion {
                        Text("Orbit \(requiredVersion)+")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Text("v\(regPlugin.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Installed")
            } else {
                Button("Install", action: installAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
