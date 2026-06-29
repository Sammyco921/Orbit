import Foundation
import GRDB

// MARK: - Schema & Migration Framework

extension OrbitDatabase {
    func runMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS conversations (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL,
                    isPinned INTEGER NOT NULL DEFAULT 0,
                    hasGeneratedTitle INTEGER NOT NULL DEFAULT 0,
                    isArchived INTEGER NOT NULL DEFAULT 0,
                    modelConfigJSON TEXT DEFAULT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    conversationId TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    imagesJSON TEXT DEFAULT NULL,
                    planJSON TEXT DEFAULT NULL,
                    artifactsJSON TEXT DEFAULT NULL
                )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversationId, timestamp)")
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS memory_items (
                    id TEXT PRIMARY KEY,
                    conversationId TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                    messageId TEXT,
                    type TEXT NOT NULL DEFAULT 'message',
                    role TEXT,
                    content TEXT NOT NULL,
                    embedding BLOB,
                    createdAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS conversation_summaries (
                    conversationId TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
                    summary TEXT NOT NULL,
                    messageCount INTEGER NOT NULL DEFAULT 0,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_memory_items_conv ON memory_items(conversationId, createdAt)")
        }
        migrator.registerMigration("v3") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS checkpoints (
                    id TEXT PRIMARY KEY,
                    goalDescription TEXT NOT NULL,
                    messagesJSON TEXT NOT NULL,
                    stepCount INTEGER NOT NULL DEFAULT 0,
                    toolFailuresJSON TEXT NOT NULL DEFAULT '{}',
                    conversationId TEXT,
                    createdAt REAL NOT NULL
                )
            """)
        }
        migrator.registerMigration("v4") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workspaces (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    icon TEXT NOT NULL DEFAULT 'folder',
                    path TEXT,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                ALTER TABLE conversations ADD COLUMN workspaceId TEXT DEFAULT NULL REFERENCES workspaces(id) ON DELETE SET NULL
            """)
        }
        migrator.registerMigration("v5") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
                    content,
                    content='memory_items',
                    content_rowid='rowid'
                )
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS memory_items_ai AFTER INSERT ON memory_items BEGIN
                    INSERT INTO memory_fts (rowid, content) VALUES (new.rowid, new.content);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS memory_items_ad AFTER DELETE ON memory_items BEGIN
                    INSERT INTO memory_fts (memory_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS memory_items_au AFTER UPDATE ON memory_items BEGIN
                    INSERT INTO memory_fts (memory_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
                    INSERT INTO memory_fts (rowid, content) VALUES (new.rowid, new.content);
                END
            """)
        }
        migrator.registerMigration("v6") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS memory_centroids (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    centroid BLOB NOT NULL,
                    num_items INTEGER NOT NULL DEFAULT 0
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS memory_clusters (
                    item_id TEXT NOT NULL UNIQUE REFERENCES memory_items(id) ON DELETE CASCADE,
                    centroid_id INTEGER NOT NULL REFERENCES memory_centroids(id) ON DELETE CASCADE
                )
            """)
        }
        migrator.registerMigration("v7") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS global_memory_items (
                    id TEXT PRIMARY KEY,
                    type TEXT NOT NULL DEFAULT 'fact',
                    role TEXT,
                    content TEXT NOT NULL,
                    embedding BLOB,
                    source TEXT,
                    createdAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS tool_usage_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    toolName TEXT NOT NULL,
                    conversationId TEXT,
                    outcome TEXT NOT NULL DEFAULT 'success',
                    durationMs REAL,
                    createdAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_tool_usage_name ON tool_usage_log(toolName, createdAt)
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS user_facts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    fact TEXT NOT NULL,
                    category TEXT NOT NULL DEFAULT 'preference',
                    confidence REAL NOT NULL DEFAULT 0.5,
                    source TEXT,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS user_preferences (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
        }
        migrator.registerMigration("v8") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS knowledge_bases (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT,
                    sourceType TEXT NOT NULL,
                    sourcePath TEXT,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS knowledge_items (
                    id TEXT PRIMARY KEY,
                    knowledgeBaseId TEXT NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
                    filePath TEXT,
                    chunkIndex INTEGER,
                    content TEXT NOT NULL,
                    embedding BLOB,
                    createdAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_knowledge_items_kb ON knowledge_items(knowledgeBaseId)
            """)
            try db.execute(sql: """
                ALTER TABLE workspaces ADD COLUMN knowledgeBaseIdsJSON DEFAULT NULL
            """)
        }
        migrator.registerMigration("v9") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS execution_log (
                    id TEXT PRIMARY KEY,
                    sessionId TEXT NOT NULL,
                    toolName TEXT NOT NULL,
                    inputJSON TEXT,
                    outputJSON TEXT,
                    outcome TEXT NOT NULL,
                    errorDetail TEXT,
                    approvalId TEXT,
                    conversationId TEXT,
                    durationMs REAL DEFAULT 0,
                    createdAt REAL NOT NULL,
                    userContext TEXT
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_execution_log_session ON execution_log(sessionId, createdAt)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_execution_log_tool ON execution_log(toolName, createdAt)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_execution_log_conv ON execution_log(conversationId, createdAt)
            """)
        }
        migrator.registerMigration("v10") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS goals (
                    id TEXT PRIMARY KEY,
                    description TEXT NOT NULL,
                    criteria TEXT,
                    status TEXT NOT NULL DEFAULT 'active',
                    priority INTEGER NOT NULL DEFAULT 5,
                    intervalMinutes REAL,
                    lastRunAt REAL,
                    nextRunAt REAL,
                    lastOutcome TEXT,
                    runCount INTEGER NOT NULL DEFAULT 0,
                    maxRuns INTEGER,
                    tags TEXT,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL,
                    conversationId TEXT
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_goals_status ON goals(status, nextRunAt)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_goals_priority ON goals(priority DESC)
            """)
        }
        migrator.registerMigration("v11") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workflow_definitions (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    stepsJSON TEXT NOT NULL DEFAULT '[]',
                    variablesJSON TEXT NOT NULL DEFAULT '[]',
                    triggersJSON TEXT NOT NULL DEFAULT '[]',
                    tags TEXT,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workflow_executions (
                    id TEXT PRIMARY KEY,
                    workflowId TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'running',
                    startedAt REAL NOT NULL,
                    completedAt REAL,
                    stepResultsJSON TEXT NOT NULL DEFAULT '{}',
                    variablesJSON TEXT NOT NULL DEFAULT '{}',
                    error TEXT
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_workflow_exec_wf ON workflow_executions(workflowId, startedAt)
            """)
        }
        migrator.registerMigration("v12") { db in
            try db.execute(sql: """
                DROP TABLE IF EXISTS tool_usage_log
            """)
        }
        migrator.registerMigration("v13") { db in
            try db.execute(sql: """
                ALTER TABLE workflow_definitions ADD COLUMN nextRunAt REAL
            """)
            try db.execute(sql: """
                UPDATE workflow_definitions SET nextRunAt = ? WHERE triggersJSON LIKE '%"scheduled"%' AND nextRunAt IS NULL
            """, arguments: [Date().timeIntervalSince1970])
        }
        migrator.registerMigration("v14") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS browser_sessions (
                    id TEXT PRIMARY KEY,
                    workspaceId TEXT,
                    url TEXT,
                    cookiesJSON TEXT NOT NULL,
                    localStorageJSON TEXT,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_browser_sessions_ws ON browser_sessions(workspaceId)
            """)
        }
        migrator.registerMigration("v15") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS oauth_credentials (
                    id TEXT PRIMARY KEY,
                    providerId TEXT NOT NULL,
                    accountName TEXT,
                    workspaceId TEXT,
                    tokenJSON TEXT NOT NULL,
                    scopesJSON TEXT NOT NULL,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_oauth_creds_provider ON oauth_credentials(providerId, workspaceId)
            """)
        }
        migrator.registerMigration("v16") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS discovered_accounts (
                    id TEXT PRIMARY KEY,
                    service TEXT NOT NULL,
                    accountName TEXT NOT NULL,
                    accountEmail TEXT,
                    accountURL TEXT,
                    sourceMessageId TEXT,
                    discoveredAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_disc_acct_svc ON discovered_accounts(service)
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS discovered_subscriptions (
                    id TEXT PRIMARY KEY,
                    service TEXT NOT NULL,
                    name TEXT NOT NULL,
                    amount REAL,
                    currency TEXT,
                    billingCycle TEXT,
                    nextBillingDate TEXT,
                    sourceMessageId TEXT,
                    discoveredAt REAL NOT NULL,
                    isActive INTEGER NOT NULL DEFAULT 1
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_disc_sub_active ON discovered_subscriptions(isActive)
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS discovered_documents (
                    id TEXT PRIMARY KEY,
                    service TEXT NOT NULL,
                    externalId TEXT NOT NULL,
                    title TEXT NOT NULL,
                    summary TEXT,
                    url TEXT,
                    mimeType TEXT,
                    discoveredAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_disc_doc_ext ON discovered_documents(service, externalId)
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS discovered_invoices (
                    id TEXT PRIMARY KEY,
                    service TEXT NOT NULL,
                    vendor TEXT NOT NULL,
                    amount REAL NOT NULL,
                    currency TEXT,
                    invoiceDate TEXT NOT NULL,
                    dueDate TEXT,
                    isRecurring INTEGER NOT NULL DEFAULT 0,
                    sourceMessageId TEXT,
                    sourceFileId TEXT,
                    discoveredAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_disc_inv_date ON discovered_invoices(invoiceDate)
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS discovered_projects (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT,
                    associatedReposJSON TEXT NOT NULL DEFAULT '[]',
                    associatedDocsJSON TEXT NOT NULL DEFAULT '[]',
                    associatedEmailsJSON TEXT NOT NULL DEFAULT '[]',
                    discoveredAt REAL NOT NULL
                )
            """)
        }

        migrator.registerMigration("v17") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS monitoring_metrics (
                    id TEXT PRIMARY KEY,
                    bucket TEXT NOT NULL,
                    metricName TEXT NOT NULL,
                    metricValue REAL NOT NULL,
                    recordedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_mon_metrics_name ON monitoring_metrics(metricName, recordedAt)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_mon_metrics_bucket ON monitoring_metrics(bucket)
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS monitoring_alerts (
                    id TEXT PRIMARY KEY,
                    alertType TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    title TEXT NOT NULL,
                    message TEXT NOT NULL,
                    sourceId TEXT,
                    sourceType TEXT,
                    recordedAt REAL NOT NULL,
                    acknowledged INTEGER NOT NULL DEFAULT 0
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_mon_alerts_severity ON monitoring_alerts(severity, recordedAt)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_mon_alerts_ack ON monitoring_alerts(acknowledged, recordedAt)
            """)
        }

        migrator.registerMigration("v18") { db in
            let columns = try? db.columns(in: "checkpoints").map(\.name)
            if !(columns?.contains("agentStatesJSON") ?? false) {
                try db.execute(sql: "ALTER TABLE checkpoints ADD COLUMN agentStatesJSON TEXT")
            }
            if !(columns?.contains("planJSON") ?? false) {
                try db.execute(sql: "ALTER TABLE checkpoints ADD COLUMN planJSON TEXT")
            }
            if !(columns?.contains("completedSubGoalsJSON") ?? false) {
                try db.execute(sql: "ALTER TABLE checkpoints ADD COLUMN completedSubGoalsJSON TEXT")
            }
            if !(columns?.contains("subGoalRetryCountsJSON") ?? false) {
                try db.execute(sql: "ALTER TABLE checkpoints ADD COLUMN subGoalRetryCountsJSON TEXT")
            }
        }

        migrator.registerMigration("v19") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS installed_templates (
                    id TEXT PRIMARY KEY,
                    templateId TEXT NOT NULL,
                    workflowId TEXT NOT NULL,
                    installedAt REAL NOT NULL,
                    variablesJSON TEXT NOT NULL DEFAULT '{}'
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_installed_templates_template ON installed_templates(templateId)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_installed_templates_workflow ON installed_templates(workflowId)
            """)
        }

        migrator.registerMigration("v20") { db in
            let columns = try? db.columns(in: "checkpoints").map(\.name)
            if !(columns?.contains("sharedMemoryData") ?? false) {
                try db.execute(sql: "ALTER TABLE checkpoints ADD COLUMN sharedMemoryData BLOB")
            }
        }

        migrator.registerMigration("v21") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS execution_jobs (
                    jobId TEXT PRIMARY KEY,
                    storyId TEXT NOT NULL,
                    intent TEXT NOT NULL,
                    state TEXT NOT NULL DEFAULT 'CREATED',
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL,
                    currentStepIndex INTEGER NOT NULL DEFAULT 0,
                    executionMode TEXT NOT NULL DEFAULT 'interactive',
                    retryCount INTEGER NOT NULL DEFAULT 0,
                    lastHeartbeatAt REAL,
                    queuePosition INTEGER NOT NULL DEFAULT 0
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS job_steps (
                    stepId TEXT PRIMARY KEY,
                    jobId TEXT NOT NULL REFERENCES execution_jobs(jobId) ON DELETE CASCADE,
                    orderIndex INTEGER NOT NULL,
                    stepJSON TEXT NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_job_steps_job ON job_steps(jobId, orderIndex)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_execution_jobs_state ON execution_jobs(state, queuePosition)
            """)
        }

        migrator.registerMigration("v22") { db in
            try db.execute(sql: """
                ALTER TABLE global_memory_items ADD COLUMN workspaceId TEXT
            """)
        }

        try migrator.migrate(db)
    }

    var migrationNeeded: Bool {
        let count = try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations") ?? 0
        }
        return (count ?? 0) < 22
    }

    func addMigration(_ name: String, migrate: @escaping (Database) throws -> Void) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(name, migrate: migrate)
        try migrator.migrate(db)
    }
}
