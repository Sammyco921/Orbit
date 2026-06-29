import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "jobstore")

/// Persistent substrate for execution jobs.
///
/// All job state transitions and step mutations flow through this store.
/// Jobs survive app restart and are queryable independently of UI.
final class JobStore {
    private let db: DatabaseQueue
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    // MARK: - Initialization

    init(database: OrbitDatabase) {
        self.db = database.db
    }

    init(inMemory: Bool = true) {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=MEMORY")
        }
        do {
            db = try DatabaseQueue(configuration: config)
            try createSchema(db: db)
        } catch {
            log.critical("Failed to initialize in-memory JobStore: \(error.localizedDescription)")
            fatalError("JobStore initialization failed: \(error.localizedDescription)")
        }
    }

    private func createSchema(db: DatabaseQueue) throws {
        try db.write { database in
            try database.execute(sql: """
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
            try database.execute(sql: """
                CREATE TABLE IF NOT EXISTS job_steps (
                    stepId TEXT PRIMARY KEY,
                    jobId TEXT NOT NULL REFERENCES execution_jobs(jobId) ON DELETE CASCADE,
                    orderIndex INTEGER NOT NULL,
                    stepJSON TEXT NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
            try database.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_job_steps_job ON job_steps(jobId, orderIndex)
            """)
            try database.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_execution_jobs_state ON execution_jobs(state, queuePosition)
            """)
        }
    }

    // MARK: - Create

    @discardableResult
    func createJob(intent: String, executionMode: ExecutionMode = .interactive) throws -> ExecutionJob {
        let nextPos = (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(queuePosition), 0) + 1 FROM execution_jobs")
        }) ?? 1
        let job = ExecutionJob(intent: intent, executionMode: executionMode, queuePosition: nextPos)
        try db.write { database in
            try database.execute(sql: """
                INSERT INTO execution_jobs (jobId, storyId, intent, state, createdAt, updatedAt, currentStepIndex, executionMode, retryCount, lastHeartbeatAt, queuePosition)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                job.jobId.uuidString,
                job.storyId.uuidString,
                job.intent,
                job.state.rawValue,
                job.createdAt.timeIntervalSince1970,
                job.updatedAt.timeIntervalSince1970,
                job.currentStepIndex,
                job.executionMode.rawValue,
                job.retryCount,
                job.lastHeartbeatAt?.timeIntervalSince1970 as (any DatabaseValueConvertible)?,
                job.queuePosition,
            ])
        }
        log.notice("Created job \(job.jobId) — \(intent.prefix(60))")
        return job
    }

    // MARK: - Scheduling Queries

    func fetchQueuedJobs() -> [ExecutionJob] {
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: "SELECT * FROM execution_jobs WHERE state = 'QUEUED' ORDER BY queuePosition ASC, createdAt ASC")
        }) else {
            return []
        }
        return rows.map(jobFromRow)
    }

    func popNextQueuedJob() -> ExecutionJob? {
        guard let job: ExecutionJob = try? db.read({ database in
            try Row.fetchOne(database, sql: "SELECT * FROM execution_jobs WHERE state = 'QUEUED' ORDER BY queuePosition ASC, createdAt ASC LIMIT 1")
                .map { self.jobFromRow($0) }
        }) else { return nil }
        try? markJobRunning(jobId: job.jobId)
        return fetchJob(job.jobId)
    }

    func fetchRunningJob() -> ExecutionJob? {
        try? db.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM execution_jobs WHERE state = 'RUNNING' LIMIT 1") else { return nil }
            return jobFromRow(row)
        }
    }

    func fetchPausedJobs() -> [ExecutionJob] {
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: "SELECT * FROM execution_jobs WHERE state = 'PAUSED' ORDER BY updatedAt DESC")
        }) else { return [] }
        return rows.map(jobFromRow)
    }

    func markJobQueued(jobId: UUID) throws {
        try updateJobState(jobId: jobId, state: .queued)
    }

    func markJobPaused(jobId: UUID) throws {
        try updateJobState(jobId: jobId, state: .paused)
    }

    // MARK: - Heartbeat

    func updateHeartbeat(jobId: UUID) throws {
        try db.write { database in
            try database.execute(sql: "UPDATE execution_jobs SET lastHeartbeatAt = ?, updatedAt = ? WHERE jobId = ?", arguments: [
                Date().timeIntervalSince1970, Date().timeIntervalSince1970, jobId.uuidString,
            ])
        }
    }

    /// Jobs are considered stale if they've been running for >30s without a heartbeat
    /// (in practice, heartbeat should fire every ~5s during active execution)
    private static let staleHeartbeatThreshold: TimeInterval = 30

    func fetchStaleRunningJobs() -> [ExecutionJob] {
        let deadline = Date().addingTimeInterval(-Self.staleHeartbeatThreshold).timeIntervalSince1970
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: """
                SELECT * FROM execution_jobs
                WHERE state = 'RUNNING' AND (lastHeartbeatAt IS NULL OR lastHeartbeatAt < ?)
                ORDER BY updatedAt DESC
            """, arguments: [deadline])
        }) else { return [] }
        return rows.map(jobFromRow)
    }

    func fetchAllActiveJobs() -> [ExecutionJob] {
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: "SELECT * FROM execution_jobs WHERE state IN ('QUEUED', 'RUNNING', 'PAUSED') ORDER BY queuePosition ASC, createdAt ASC")
        }) else { return [] }
        return rows.map(jobFromRow)
    }

    // MARK: - Read

    func fetchJob(_ jobId: UUID) -> ExecutionJob? {
        try? db.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM execution_jobs WHERE jobId = ?", arguments: [jobId.uuidString]) else {
                return nil
            }
            return self.jobFromRow(row)
        }
    }

    func fetchActiveJobs() -> [ExecutionJob] {
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: "SELECT * FROM execution_jobs WHERE state IN ('CREATED', 'PLANNED', 'RUNNING') ORDER BY createdAt DESC")
        }) else {
            return []
        }
        return rows.map(jobFromRow)
    }

    func fetchJobHistory(limit: Int = 50) -> [ExecutionJob] {
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: "SELECT * FROM execution_jobs WHERE state IN ('COMPLETED', 'FAILED', 'CANCELLED') ORDER BY updatedAt DESC LIMIT ?", arguments: [limit])
        }) else {
            return []
        }
        return rows.map(jobFromRow)
    }

    func fetchSteps(jobId: UUID) -> [StoryStep] {
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: "SELECT * FROM job_steps WHERE jobId = ? ORDER BY orderIndex ASC", arguments: [jobId.uuidString])
        }) else {
            return []
        }
        return rows.compactMap { row in
            guard let json = row["stepJSON"] as? String,
                  let data = json.data(using: .utf8),
                  let step = try? jsonDecoder.decode(StoryStep.self, from: data)
            else { return nil }
            return step
        }
    }

    // MARK: - Update Job State

    func updateJobState(jobId: UUID, state: JobState, guardTransition: Bool = true) throws {
        try db.write { database in
            if guardTransition {
                let currentRaw = try String.fetchOne(database, sql: "SELECT state FROM execution_jobs WHERE jobId = ?", arguments: [jobId.uuidString])
                if let currentRaw, let current = JobState(rawValue: currentRaw) {
                    guard current.canTransition(to: state) else {
                        log.warning("Blocked invalid transition \(current.rawValue) → \(state.rawValue) for job \(jobId)")
                        return
                    }
                }
            }
            try database.execute(sql: "UPDATE execution_jobs SET state = ?, updatedAt = ? WHERE jobId = ?",
                arguments: [state.rawValue, Date().timeIntervalSince1970, jobId.uuidString])
        }
    }

    func updateJobStepIndex(jobId: UUID, stepIndex: Int) throws {
        try db.write { database in
            try database.execute(sql: "UPDATE execution_jobs SET currentStepIndex = ?, updatedAt = ? WHERE jobId = ?", arguments: [
                stepIndex, Date().timeIntervalSince1970, jobId.uuidString,
            ])
        }
    }

    func markJobRunning(jobId: UUID) throws {
        try updateJobState(jobId: jobId, state: .running)
    }

    func markJobFailed(jobId: UUID, reason: String? = nil) throws {
        try updateJobState(jobId: jobId, state: .failed)
    }

    func markJobCancelled(jobId: UUID) throws {
        try updateJobState(jobId: jobId, state: .cancelled)
    }

    func markJobCompleted(jobId: UUID) throws {
        try updateJobState(jobId: jobId, state: .completed)
    }

    // MARK: - Steps

    func appendStep(jobId: UUID, step: StoryStep) throws {
        guard let json = try? jsonEncoder.encode(step),
              let jsonString = String(data: json, encoding: .utf8) else {
            log.error("Failed to encode step for job \(jobId)")
            return
        }
        try db.write { database in
            try database.execute(sql: """
                INSERT OR REPLACE INTO job_steps (stepId, jobId, orderIndex, stepJSON, updatedAt)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                step.id.uuidString, jobId.uuidString, step.order, jsonString, Date().timeIntervalSince1970,
            ])
        }
    }

    func updateStep(jobId: UUID, stepIndex: Int, mutation: (inout StoryStep) -> Void) throws {
        try db.write { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT stepId, stepJSON FROM job_steps WHERE jobId = ? AND orderIndex = ?", arguments: [jobId.uuidString, stepIndex]),
                  let json = row["stepJSON"] as? String,
                  let data = json.data(using: .utf8),
                  var step = try? jsonDecoder.decode(StoryStep.self, from: data)
            else { return }
            mutation(&step)
            let updated = try jsonEncoder.encode(step)
            guard let updatedJSON = String(data: updated, encoding: .utf8) else { return }
            try database.execute(sql: "UPDATE job_steps SET stepJSON = ?, updatedAt = ? WHERE stepId = ?", arguments: [
                updatedJSON, Date().timeIntervalSince1970, row["stepId"] as! String,
            ])
        }
    }

    func updateStepOutput(jobId: UUID, stepIndex: Int, output: String) throws {
        try updateStep(jobId: jobId, stepIndex: stepIndex) { step in
            step.output = output
        }
    }

    func updateStepStreamedTokens(jobId: UUID, stepIndex: Int, tokens: String) throws {
        try updateStep(jobId: jobId, stepIndex: stepIndex) { step in
            step.streamedTokens = tokens
        }
    }

    // MARK: - Delete

    func deleteJob(jobId: UUID) throws {
        try db.write { database in
            try database.execute(sql: "DELETE FROM job_steps WHERE jobId = ?", arguments: [jobId.uuidString])
            try database.execute(sql: "DELETE FROM execution_jobs WHERE jobId = ?", arguments: [jobId.uuidString])
        }
    }

    // MARK: - Recovery

    /// On app restart: requeue RUNNING jobs with fresh heartbeats, fail stale ones.
    /// Returns jobs that were requeued.
    func recoverRunningJobsOnLaunch() -> [ExecutionJob] {
        let stale = fetchStaleRunningJobs()
        for job in stale {
            try? updateJobState(jobId: job.jobId, state: .failed)
            log.warning("Stale job \(job.jobId) (no heartbeat) marked FAILED on recovery")
        }
        let fresh = fetchFreshRunningJobs()
        for job in fresh {
            try? updateJobState(jobId: job.jobId, state: .queued)
            log.notice("Job \(job.jobId) (recent heartbeat) requeued on recovery")
        }
        return fresh
    }

    /// Running jobs that still have a recent heartbeat (considered recoverable)
    private func fetchFreshRunningJobs() -> [ExecutionJob] {
        let deadline = Date().addingTimeInterval(-Self.staleHeartbeatThreshold).timeIntervalSince1970
        guard let rows = try? db.read({ database in
            try Row.fetchAll(database, sql: """
                SELECT * FROM execution_jobs
                WHERE state = 'RUNNING' AND lastHeartbeatAt >= ?
                ORDER BY updatedAt DESC
            """, arguments: [deadline])
        }) else { return [] }
        return rows.map(jobFromRow)
    }

    // MARK: - Helpers

    private func jobFromRow(_ row: Row) -> ExecutionJob {
        guard let jobIdStr = row["jobId"] as? String,
              let jobId = UUID(uuidString: jobIdStr),
              let storyIdStr = row["storyId"] as? String,
              let storyId = UUID(uuidString: storyIdStr),
              let intent = row["intent"] as? String,
              let createdAt = (row["createdAt"] as? Double).map(Date.init(timeIntervalSince1970:)),
              let updatedAt = (row["updatedAt"] as? Double).map(Date.init(timeIntervalSince1970:)),
              let currentStepIndex = row["currentStepIndex"] as? Int,
              let retryCount = row["retryCount"] as? Int
        else {
            log.critical("Database row corrupted — missing or invalid columns in execution_jobs")
            fatalError("Corrupt database row: \(row)")
        }
        let state = (row["state"] as? String).flatMap(JobState.init(rawValue:)) ?? .created
        let executionMode = (row["executionMode"] as? String).flatMap(ExecutionMode.init(rawValue:)) ?? .interactive
        return ExecutionJob(
            jobId: jobId,
            storyId: storyId,
            intent: intent,
            state: state,
            createdAt: createdAt,
            updatedAt: updatedAt,
            currentStepIndex: currentStepIndex,
            executionMode: executionMode,
            retryCount: retryCount,
            lastHeartbeatAt: (row["lastHeartbeatAt"] as? Double).map(Date.init(timeIntervalSince1970:)),
            queuePosition: row["queuePosition"] as? Int ?? 0
        )
    }
}
