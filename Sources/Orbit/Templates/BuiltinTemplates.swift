import Foundation

// MARK: - Built-in Workflow Templates

enum BuiltinTemplates {
    static let emailDigest = WorkflowTemplate(
        id: "email-digest",
        name: "Email Digest",
        description: "Sends a daily summary of recent important messages to you via Slack or email. Searches Gmail for important mail from the last 24 hours and delivers a formatted digest.",
        author: "Orbit",
        version: "1.0.0",
        tags: ["email", "digest", "daily", "gmail", "slack"],
        category: .emailDigest,
        variables: [
            TemplateVariable(
                name: "deliveryEmail",
                description: "Email address to deliver the digest to",
                required: true,
                prompt: "Enter the email address where you want to receive your daily digest"
            ),
            TemplateVariable(
                name: "lookbackHours",
                description: "Hours to look back for important messages",
                required: false,
                defaultValue: "24",
                prompt: "How many hours of history should the digest cover?"
            ),
            TemplateVariable(
                name: "maxResults",
                description: "Maximum number of messages to include in the digest",
                required: false,
                defaultValue: "20",
                prompt: "What's the maximum number of messages to include?"
            ),
        ],
        steps: [
            Step(
                name: "Search Important Messages",
                stepType: .action,
                toolName: "searchMail",
                input: [
                    "query": "is:important newer_than:{{lookbackHours}}h OR is:unread newer_than:{{lookbackHours}}h",
                    "maxResults": "{{maxResults}}"
                ]
            ),
            Step(
                name: "Send Digest",
                stepType: .action,
                toolName: "sendMail",
                input: [
                    "to": "{{deliveryEmail}}",
                    "subject": "Daily Email Digest",
                    "body": "Here is your daily email digest covering the last {{lookbackHours}} hours.\n\n{{steps.Step_1.result}}"
                ]
            )
        ],
        triggers: [
            WorkflowTrigger(type: .scheduled, schedule: "0 8 * * *"),
            WorkflowTrigger(type: .manual)
        ],
        isBuiltIn: true
    )

    static let subscriptionTracker = WorkflowTemplate(
        id: "subscription-tracker",
        name: "Subscription Tracker",
        description: "Scans Gmail for subscription receipts, invoices, and recurring charges. Keeps a running list of all active subscriptions with amounts and billing cycles. Runs weekly to catch new subscriptions.",
        author: "Orbit",
        version: "1.0.0",
        tags: ["subscriptions", "billing", "finance", "gmail"],
        category: .subscriptionTracker,
        variables: [
            TemplateVariable(
                name: "notificationEmail",
                description: "Email address to send subscription alerts to",
                required: true,
                prompt: "Enter the email for subscription alerts"
            ),
            TemplateVariable(
                name: "reminderThresholdDays",
                description: "Days before billing date to send a reminder",
                required: false,
                defaultValue: "3",
                prompt: "How many days before billing should we remind you?"
            ),
        ],
        steps: [
            Step(
                name: "Search Subscription Emails",
                stepType: .action,
                toolName: "searchMail",
                input: [
                    "query": "subject:(receipt OR invoice OR \"your subscription\" OR \"recurring payment\" OR \"charged\") newer_than:7d",
                    "maxResults": "50"
                ]
            ),
            Step(
                name: "Index Discovered Subscriptions",
                stepType: .action,
                toolName: "discoveryIndex",
                input: ["mode": "incremental"]
            ),
            Step(
                name: "Send Subscription Summary",
                stepType: .action,
                toolName: "sendMail",
                input: [
                    "to": "{{notificationEmail}}",
                    "subject": "Weekly Subscription Summary",
                    "body": "Here are the subscriptions found this week:\n\n{{steps.Step_1.result}}\n\nActive subscriptions in discovery:\n{{steps.Step_2.result}}"
                ]
            )
        ],
        triggers: [
            WorkflowTrigger(type: .scheduled, schedule: "0 9 * * 1"),
            WorkflowTrigger(type: .manual)
        ],
        isBuiltIn: true
    )

    static let invoiceFinder = WorkflowTemplate(
        id: "invoice-finder",
        name: "Invoice Finder",
        description: "Searches Gmail and Google Drive for invoices and receipts. Runs discovery indexing to catalog invoices and delivers a monthly report of all invoices found.",
        author: "Orbit",
        version: "1.0.0",
        tags: ["invoices", "finance", "gmail", "drive"],
        category: .invoiceFinder,
        variables: [
            TemplateVariable(
                name: "reportEmail",
                description: "Email address to send the invoice report to",
                required: true,
                prompt: "Enter the email for the invoice report"
            ),
            TemplateVariable(
                name: "searchMonths",
                description: "Number of months of history to search",
                required: false,
                defaultValue: "3",
                prompt: "How many months back should we search for invoices?"
            ),
        ],
        steps: [
            Step(
                name: "Search Invoice Emails",
                stepType: .action,
                toolName: "searchMail",
                input: [
                    "query": "subject:(invoice OR receipt OR \"payment confirmation\") newer_than:{{searchMonths}}m",
                    "maxResults": "100"
                ]
            ),
            Step(
                name: "Index Invoices via Discovery",
                stepType: .action,
                toolName: "discoveryIndex",
                input: ["mode": "full"]
            ),
            Step(
                name: "List Invoices from Discovery",
                stepType: .action,
                toolName: "discoveryList",
                input: ["type": "invoices"]
            ),
            Step(
                name: "Send Invoice Report",
                stepType: .action,
                toolName: "sendMail",
                input: [
                    "to": "{{reportEmail}}",
                    "subject": "Monthly Invoice Report",
                    "body": "Invoices found in the last {{searchMonths}} months:\n\n{{steps.Step_3.result}}"
                ]
            )
        ],
        triggers: [
            WorkflowTrigger(type: .scheduled, schedule: "0 10 1 * *"),
            WorkflowTrigger(type: .manual)
        ],
        isBuiltIn: true
    )

    static let githubBackup = WorkflowTemplate(
        id: "github-backup",
        name: "GitHub Backup",
        description: "Lists all repositories from your GitHub account, creates discovery records for projects and repos, and sends a summary. Useful for keeping an inventory of your GitHub activity.",
        author: "Orbit",
        version: "1.0.0",
        tags: ["github", "backup", "repos", "projects"],
        category: .githubBackup,
        variables: [
            TemplateVariable(
                name: "reportEmail",
                description: "Email to send the backup summary to",
                required: true,
                prompt: "Enter the email for the GitHub backup summary"
            ),
            TemplateVariable(
                name: "maxRepos",
                description: "Maximum number of repositories to include",
                required: false,
                defaultValue: "50",
                prompt: "How many repositories should we track?"
            ),
        ],
        steps: [
            Step(
                name: "Search Repositories",
                stepType: .action,
                toolName: "searchRepos",
                input: [
                    "query": "user:{{githubUsername}} fork:true",
                    "maxResults": "{{maxRepos}}"
                ]
            ),
            Step(
                name: "List Open Pull Requests",
                stepType: .action,
                toolName: "listPRs",
                input: [
                    "maxResults": "50"
                ]
            ),
            Step(
                name: "Index GitHub Projects",
                stepType: .action,
                toolName: "discoveryIndex",
                input: ["mode": "incremental"]
            ),
            Step(
                name: "Send Backup Summary",
                stepType: .action,
                toolName: "sendMail",
                input: [
                    "to": "{{reportEmail}}",
                    "subject": "GitHub Repository Backup Summary",
                    "body": "GitHub Backup Report\n\nRepositories found:\n{{steps.Step_1.result}}\n\nOpen PRs:\n{{steps.Step_2.result}}"
                ]
            )
        ],
        triggers: [
            WorkflowTrigger(type: .scheduled, schedule: "0 6 * * 0"),
            WorkflowTrigger(type: .manual)
        ],
        isBuiltIn: true
    )

    static let all: [WorkflowTemplate] = [
        emailDigest,
        subscriptionTracker,
        invoiceFinder,
        githubBackup,
    ]
}
