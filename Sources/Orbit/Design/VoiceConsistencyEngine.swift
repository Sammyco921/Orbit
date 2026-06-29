import Foundation

// MARK: - Voice Consistency Engine

/// Centralized microcopy definitions. Every user-facing string in the app
/// must derive from this engine. No duplicate or inconsistent phrasing.
///
/// Voice principles:
/// - Calm, confident, minimal
/// - "Orbit" as the subject ("Orbit is working on...")
/// - Progress as "Step X of Y"
/// - Outcomes: "Completed successfully" / "Failed at step X"
/// - Configuration: "Set up model" / "Change model" (never variants)
enum OrbitVoice {
    // MARK: - Status

    enum Status {
        static let idle = "Idle"
        static let running = "Running"
        static let interpreting = "Interpreting"
        static let planning = "Planning"
        static let executing = "Executing"
        static let completed = "Completed"
        static let failed = "Failed"
        static let cancelled = "Cancelled"
        static let paused = "Paused"
        static let queued = "Queued"
        static let connecting = "Connecting"

        static let done = "Done"
        static let error = "Error"

        static func stepProgress(current: Int, total: Int) -> String {
            "Step \(current + 1) of \(total)"
        }
    }

    // MARK: - Actions

    enum Action {
        static let cancel = "Cancel"
        static let stop = "Stop"
        static let pause = "Pause"
        static let resume = "Resume"
        static let retry = "Retry"
        static let save = "Save"
        static let delete = "Delete"
        static let edit = "Edit"
        static let create = "Create"
        static let apply = "Apply"
        static let refresh = "Refresh"
        static let submit = "Submit"
        static let open = "Open"
        static let close = "Close"
        static let back = "Back"
        static let next = "Next"
        static let skip = "Skip"
        static let done = "Done"
        static let quit = "Quit"
        static let install = "Install"
        static let uninstall = "Uninstall"
        static let update = "Update"
        static let enable = "Enable"
        static let disable = "Disable"
        static let deny = "Deny"
        static let allow = "Allow"
        static let allowOnce = "Allow Once"
        static let allowSession = "Always Allow for Session"
        static let copy = "Copy"
        static let export = "Export"
        static let rerun = "Re-run"
        static let editAndRerun = "Edit and re-run"
    }

    // MARK: - Intent

    enum Intent {
        static func working(on text: String) -> String {
            "Orbit is working on: \(text)"
        }

        static let analyzing = "Orbit is analyzing your request"
        static let interpreting = "Orbit interprets your intent"
        static let planning = "Orbit is building a plan"
        static let idle = "Orbit is ready for your next task"
        static let waitingForModel = "Orbit needs a model to continue"
        static let noActiveTask = "No active task"

        static let interpretingDescription = "Orbit interprets your intent, builds a plan, and executes it step by step in real time."

        static let quickInputPlaceholder = "Ask Orbit to do something..."
        static let editPlaceholder = "Edit your request..."
        static let searchPlaceholder = "Search..."
        static let namePlaceholder = "Name"
        static let descriptionPlaceholder = "Description (optional)"
    }

    // MARK: - Execution

    enum Execution {
        static let taskComplete = "Completed successfully"
        static let taskFailed = "Failed"
        static let taskCancelled = "Cancelled"

        static func failedAtStep(_ index: Int, _ name: String) -> String {
            "Failed at step \(index + 1): \(name)"
        }

        static let running = "Now running"
        static let working = "Working on this..."
        static let continuing = "Continuing..."
        static let finalizing = "Finalizing..."
        static let timedOut = "Timed out"
        static let stepCompleted = "Completed"

        static let summaryHeader = "Summary of execution so far"
        static let result = "Result"
        static let copied = "Copied"

        static let noActiveTask = "No active task"
        static let noActiveTaskDescription = "Orbit interprets your intent, builds a plan,\nand executes it step by step in real time."
    }

    // MARK: - Empty States

    enum Empty {
        static let noExecutions = "No executions yet"
        static let noExecutionsDescription = "Execution history will appear here after you run a task."
        static let noExecutionsAction = "Run your first task"

        static let noWorkspaces = "No tasks yet"
        static let noWorkspacesDescription = "Create a workspace to organize your tasks and conversations."
        static let noWorkspacesAction = "New Workspace"

        static let noArtifacts = "No artifacts"
        static let noArtifactsDescription = "Artifacts are created when tools generate files."

        static let noJobs = "No queued jobs"
        static let noJobsDescription = "Submit a task to start."
        static let noJobsAction = "Submit a task"

        static let noAgents = "No active agents"
        static let noAgentsDescription = "Agent teams are created when you run a task in multi-agent mode."

        static let noIntegrations = "No integrations"
        static let noIntegrationsDescription = "Connect external services to extend Orbit's capabilities."

        static let noKnowledgeBases = "No knowledge bases"
        static let noKnowledgeBasesDescription = "Add a file, folder, git repo, or URL to index."

        static let noGoals = "No goals yet"
        static let noGoalsAction = "Create a recurring behavior goal"

        static let noPlugins = "No plugins installed"
        static let noPluginsDescription = "Browse the Orbit Official registry or install a plugin.json file."

        static let noWorkflows = "No workflows yet"
        static let noWorkflowsAction = "Create a multi-step workflow"

        static let noModelConfigured = "No model configured"
        static let noModelConfiguredDescription = "Orbit needs a model to continue. Set up a local or cloud model."
        static let setupModel = "Set up model"
        static let changeModel = "Change model"

        static let noActivity = "No activity yet"
        static let noExecutionData = "No execution data available"
    }

    // MARK: - Settings

    enum Settings {
        static let modelStatus = "Model Status"
        static let ready = "Ready"
        static let needsSetup = "Needs setup"
        static let scanning = "Scanning..."
        static let testConnection = "Test Connection"
        static let connected = "Connected"
        static let failedRetry = "Failed — Retry"
        static let noAPIKey = "No API key configured"
        static let installOllama = "Install Ollama"
        static let noModelsDownloaded = "No models downloaded"
        static let pullModel = "Pull model..."
    }

    // MARK: - Navigation

    enum Navigation {
        static let workspace = "Workspace"
        static let history = "History"
        static let agents = "Agents"
        static let integrations = "Integrations"
        static let plugins = "Plugins"
        static let settings = "Settings"
        static let artifacts = "Artifacts"
        static let tools = "Tools"
        static let goals = "Goals"
        static let projects = "PROJECTS"
        static let quickChats = "QUICK CHATS"
        static let execution = "EXECUTION"
        static let inspector = "Inspector"
        static let navigation = "NAVIGATION"
    }

    // MARK: - Labels

    enum Label {
        static func queueCount(_ count: Int) -> String {
            "\(count) queued"
        }

        static func pauseCount(_ count: Int) -> String {
            "\(count) paused"
        }

        static func stepCount(_ count: Int) -> String {
            "\(count) step(s)"
        }

        static func runCount(_ count: Int) -> String {
            "\(count) runs"
        }
    }

    // MARK: - Onboarding

    enum Onboarding {
        static let welcome = "Welcome to Orbit"
        static let welcomeBody = "A system that turns intent into execution. Type what you need — Orbit handles the rest."

        static let howItWorks = "How It Works"
        static let howItWorksBody = "You give an intent. Orbit interprets your request, builds a plan, and executes it step by step — all visible to you in real time."

        static let safety = "Safety Built In"
        static let safetyBody = "Every tool execution requires your permission. Nothing runs silently. Every action is audited and replayable from history."

        static let localOrCloud = "Local or Cloud"
        static let localOrCloudBody = "Run models locally through Ollama, or connect to OpenAI and Anthropic. Switch providers anytime in Settings."

        static let ready = "You're Ready"
        static let readyBody = "Orbit is set up and waiting. Try typing \"List the files in this project\" to run your first task."

        static let enterOrbit = "Enter Orbit"
        static let continue_ = "Continue"
    }

    // MARK: - Errors

    enum Error {
        static func generic(_ detail: String) -> String {
            "Something went wrong: \(detail)"
        }

        static let modelDisconnected = "Model disconnected during execution"
        static let toolEmptyResult = "Tool returned an empty result"
        static let artifactMissing = "Artifact not found or corrupted"
        static let partialReplay = "Partial replay — some steps could not be reconstructed"
        static let jobFailedMidStream = "Job failed during execution"
        static let cancelledMidStep = "Cancelled during step execution"

        static func recoverySuggestion(for error: String) -> String {
            switch error {
            case Self.modelDisconnected: return "Check your model connection and try again."
            case Self.toolEmptyResult: return "Try re-running with a more specific intent."
            case Self.artifactMissing: return "The file may have been moved or deleted."
            case Self.partialReplay: return "You can re-run the job from the beginning."
            case Self.jobFailedMidStream: return "Check the error details and refine your intent."
            case Self.cancelledMidStep: return "No action needed. You can submit a new intent."
            default: return "Try again or contact support."
            }
        }
    }
}
