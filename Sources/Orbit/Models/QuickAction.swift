import Foundation

enum QuickActionCategory: String, CaseIterable {
    case development = "Development"
    case git = "Git"
    case project = "Project"
    case content = "Content"
    case research = "Research"
    case memory = "Memory"
    case system = "System"

    var icon: String {
        switch self {
        case .development: "hammer"
        case .git: "arrow.triangle.branch"
        case .project: "folder"
        case .content: "doc.text"
        case .research: "magnifyingglass"
        case .memory: "brain"
        case .system: "gearshape"
        }
    }
}

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let keywords: [String]
    let category: QuickActionCategory
    let intent: String
    let isInstant: Bool

    init(title: String, subtitle: String, icon: String, keywords: [String], category: QuickActionCategory, intent: String, isInstant: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.keywords = keywords
        self.category = category
        self.intent = intent
        self.isInstant = isInstant
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        if title.lowercased().contains(q) { return true }
        if subtitle.lowercased().contains(q) { return true }
        if keywords.contains(where: { $0.lowercased().contains(q) }) { return true }
        return false
    }
}

enum QuickActionRegistry {
    static let allActions: [QuickAction] = [
        QuickAction(
            title: "Run Tests",
            subtitle: "Build and run the test suite",
            icon: "testtube.2",
            keywords: ["test", "build", "check", "pass", "suite"],
            category: .development,
            intent: "Run the test suite and show results"
        ),
        QuickAction(
            title: "Build Project",
            subtitle: "Compile and build the project",
            icon: "hammer",
            keywords: ["build", "compile", "make", "xcodebuild"],
            category: .development,
            intent: "Build the project"
        ),
        QuickAction(
            title: "Lint Project",
            subtitle: "Run linter on the codebase",
            icon: "checkmark.circle",
            keywords: ["lint", "format", "style", "check", "swiftlint"],
            category: .development,
            intent: "Run the linter on the codebase"
        ),
        QuickAction(
            title: "Git Status",
            subtitle: "Show current git status",
            icon: "arrow.triangle.branch",
            keywords: ["git", "status", "branch", "current"],
            category: .git,
            intent: "Run git status and show the current branch"
        ),
        QuickAction(
            title: "Git Diff",
            subtitle: "Show unstaged changes",
            icon: "doc.text",
            keywords: ["git", "diff", "changes", "unstaged", "modified"],
            category: .git,
            intent: "Show git diff for unstaged changes"
        ),
        QuickAction(
            title: "Push Changes",
            subtitle: "Commit and push to remote",
            icon: "icloud.and.arrow.up",
            keywords: ["git", "push", "commit", "remote", "origin"],
            category: .git,
            intent: "Commit and push all changes to the remote repository"
        ),
        QuickAction(
            title: "Pull Latest",
            subtitle: "Pull latest changes from remote",
            icon: "icloud.and.arrow.down",
            keywords: ["git", "pull", "remote", "update", "latest"],
            category: .git,
            intent: "Pull the latest changes from the remote repository"
        ),
        QuickAction(
            title: "Analyze Project",
            subtitle: "Scan project structure and dependencies",
            icon: "magnifyingglass.circle",
            keywords: ["analyze", "scan", "structure", "dependencies", "overview"],
            category: .project,
            intent: "Analyze the current project structure including dependencies"
        ),
        QuickAction(
            title: "Search Files",
            subtitle: "Find files matching a pattern",
            icon: "doc.text.magnifyingglass",
            keywords: ["search", "find", "files", "locate", "grep"],
            category: .project,
            intent: "Search for files matching my specified pattern"
        ),
        QuickAction(
            title: "Dependencies",
            subtitle: "List project dependencies",
            icon: "cube.box",
            keywords: ["dependencies", "packages", "libs", "libraries", "spm"],
            category: .project,
            intent: "List all project dependencies and their versions"
        ),
        QuickAction(
            title: "Check Memory",
            subtitle: "View system memory usage",
            icon: "memorychip",
            keywords: ["memory", "ram", "usage", "system", "resource"],
            category: .system,
            intent: "Check the system memory usage"
        ),
        QuickAction(
            title: "Show Logs",
            subtitle: "View recent application logs",
            icon: "list.bullet.rectangle",
            keywords: ["log", "logs", "recent", "console", "output"],
            category: .system,
            intent: "Show the most recent application logs"
        ),
        QuickAction(
            title: "Open in Xcode",
            subtitle: "Open project in Xcode",
            icon: "chevron.left.forwardslash.chevron.right",
            keywords: ["xcode", "open", "project", "ide"],
            category: .system,
            intent: "",
            isInstant: true
        ),
        QuickAction(
            title: "Open in Finder",
            subtitle: "Reveal project in Finder",
            icon: "folder",
            keywords: ["finder", "reveal", "open", "show", "project"],
            category: .system,
            intent: "",
            isInstant: true
        ),

        // MARK: - Content Creation
        QuickAction(
            title: "Create Document",
            subtitle: "Generate a .docx Word document with content",
            icon: "doc.text",
            keywords: ["document", "word", "docx", "create", "write"],
            category: .content,
            intent: "Create a Word document titled 'Document' with the content I provide"
        ),
        QuickAction(
            title: "Create Spreadsheet",
            subtitle: "Generate an .xlsx Excel spreadsheet",
            icon: "tablecells",
            keywords: ["spreadsheet", "excel", "xlsx", "csv", "sheet", "data"],
            category: .content,
            intent: "Create a spreadsheet with the data I provide"
        ),
        QuickAction(
            title: "Create PDF",
            subtitle: "Generate a PDF document",
            icon: "doc.richtext",
            keywords: ["pdf", "document", "create", "generate"],
            category: .content,
            intent: "Create a PDF document with the content I describe"
        ),
        QuickAction(
            title: "Create Presentation",
            subtitle: "Generate a .pptx PowerPoint presentation",
            icon: "rectangle.on.rectangle",
            keywords: ["presentation", "powerpoint", "pptx", "slides", "slide deck"],
            category: .content,
            intent: "Create a presentation with slides about the topic I describe"
        ),

        // MARK: - Research
        QuickAction(
            title: "Deep Research",
            subtitle: "In-depth multi-source research on any topic",
            icon: "magnifyingglass.circle",
            keywords: ["research", "deep", "investigate", "comprehensive", "thorough", "study"],
            category: .research,
            intent: "Deeply research the topic I specify and provide a comprehensive report"
        ),
        QuickAction(
            title: "Web Search",
            subtitle: "Search the web and get results with page content",
            icon: "globe",
            keywords: ["search", "web", "internet", "look up", "find online", "google"],
            category: .research,
            intent: "Search the web for information about what I describe"
        ),

        // MARK: - Memory
        QuickAction(
            title: "Remember This",
            subtitle: "Store a fact or note in persistent project memory",
            icon: "brain",
            keywords: ["remember", "save", "store", "fact", "note", "preference", "memory"],
            category: .memory,
            intent: "Remember this information for future reference"
        ),
        QuickAction(
            title: "Recall Memory",
            subtitle: "Search stored project memories",
            icon: "brain.head.profile",
            keywords: ["recall", "remember", "search memory", "what do you know", "past", "facts"],
            category: .memory,
            intent: "Search my stored memories for relevant information"
        ),

        // MARK: - Schedule
        QuickAction(
            title: "Schedule Task",
            subtitle: "Set up a recurring task or reminder",
            icon: "clock.arrow.circlepath",
            keywords: ["schedule", "recurring", "timer", "interval", "every", "reminder", "cron"],
            category: .system,
            intent: "Schedule a task to run at a regular interval"
        ),
    ]

    static func filtered(by query: String) -> [(action: QuickAction, category: QuickActionCategory)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return allActions.map { ($0, $0.category) }
        }
        return allActions
            .filter { $0.matches(trimmed) }
            .map { ($0, $0.category) }
    }
}
