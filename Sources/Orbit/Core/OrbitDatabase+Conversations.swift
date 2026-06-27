import Foundation
import GRDB

// MARK: - Conversation & Message CRUD

extension OrbitDatabase {
    func loadAllConversations(workspaceId: UUID? = nil, messageLimit: Int = 100) throws -> [Conversation] {
        try db.read { db in
            let rows: [Row]
            if let wsId = workspaceId {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM conversations WHERE workspaceId = ? ORDER BY updatedAt DESC", arguments: [wsId.uuidString])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM conversations ORDER BY updatedAt DESC")
            }

            let convIds = rows.compactMap { ($0["id"] as? String).flatMap { UUID(uuidString: $0)?.uuidString } }
            guard !convIds.isEmpty else { return [] }

            let placeholders = convIds.map { _ in "?" }.joined(separator: ",")
            let allMessageRows = try Row.fetchAll(db, sql: "SELECT * FROM messages WHERE conversationId IN (\(placeholders)) ORDER BY conversationId, timestamp", arguments: StatementArguments(convIds))

            var messagesByConv: [String: [Message]] = [:]
            for msgRow in allMessageRows {
                guard let convId = msgRow["conversationId"] as? String else { continue }
                let message = try buildMessage(from: msgRow)
                messagesByConv[convId, default: []].append(message)
            }

            for (convId, msgs) in messagesByConv where msgs.count > messageLimit {
                messagesByConv[convId] = Array(msgs.suffix(messageLimit))
            }

            return try rows.map { row in
                guard let idStr: String = row["id"], let id = UUID(uuidString: idStr) else {
                    throw OrbitError.databaseCorruption("Missing or invalid conversation id")
                }
                guard let title: String = row["title"] else {
                    throw OrbitError.databaseCorruption("Missing title for conversation \(idStr)")
                }
                guard let createdAtInterval: TimeInterval = row["createdAt"] else {
                    throw OrbitError.databaseCorruption("Missing createdAt for conversation \(idStr)")
                }
                guard let updatedAtInterval: TimeInterval = row["updatedAt"] else {
                    throw OrbitError.databaseCorruption("Missing updatedAt for conversation \(idStr)")
                }
                let isPinned = intFromRow(row, key: "isPinned") != 0
                let hasGeneratedTitle = intFromRow(row, key: "hasGeneratedTitle") != 0
                let isArchived = intFromRow(row, key: "isArchived") != 0
                let modelConfig: ModelConfig? = decodeJSON(row["modelConfigJSON"] as? String)
                let workspaceId: UUID? = (row["workspaceId"] as? String).flatMap { UUID(uuidString: $0) }
                let messages = messagesByConv[id.uuidString] ?? []
                return Conversation(id: id, title: title, messages: messages, createdAt: Date(timeIntervalSince1970: createdAtInterval), updatedAt: Date(timeIntervalSince1970: updatedAtInterval), isPinned: isPinned, hasGeneratedTitle: hasGeneratedTitle, modelConfig: modelConfig, isArchived: isArchived, workspaceId: workspaceId)
            }
        }
    }

    func loadMessages(conversationId: UUID, limit: Int = 50, offset: Int = 0) throws -> [Message] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM messages WHERE conversationId = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?", arguments: [conversationId.uuidString, limit, offset])
            return try rows.map { try buildMessage(from: $0) }
        }
    }

    func searchConversations(query: String, workspaceId: UUID? = nil) throws -> [Conversation] {
        let pattern = "%\(query)%"
        return try db.read { db in
            let rows: [Row]
            if crypto != nil {
                if let wsId = workspaceId {
                    rows = try Row.fetchAll(db, sql: """
                        SELECT DISTINCT c.* FROM conversations c
                        WHERE c.title LIKE ? AND c.workspaceId = ?
                        ORDER BY c.updatedAt DESC
                    """, arguments: [pattern, wsId.uuidString])
                } else {
                    rows = try Row.fetchAll(db, sql: """
                        SELECT DISTINCT c.* FROM conversations c
                        WHERE c.title LIKE ?
                        ORDER BY c.updatedAt DESC
                    """, arguments: [pattern])
                }
            } else {
                if let wsId = workspaceId {
                    rows = try Row.fetchAll(db, sql: """
                        SELECT DISTINCT c.* FROM conversations c
                        LEFT JOIN messages m ON m.conversationId = c.id
                        WHERE (c.title LIKE ? OR m.content LIKE ?) AND c.workspaceId = ?
                        ORDER BY c.updatedAt DESC
                    """, arguments: [pattern, pattern, wsId.uuidString])
                } else {
                    rows = try Row.fetchAll(db, sql: """
                        SELECT DISTINCT c.* FROM conversations c
                        LEFT JOIN messages m ON m.conversationId = c.id
                        WHERE c.title LIKE ? OR m.content LIKE ?
                        ORDER BY c.updatedAt DESC
                    """, arguments: [pattern, pattern])
                }
            }
            let convIds = rows.compactMap { ($0["id"] as? String).flatMap { UUID(uuidString: $0)?.uuidString } }
            guard !convIds.isEmpty else { return [] }

            let placeholders = convIds.map { _ in "?" }.joined(separator: ",")
            let allMessageRows = try Row.fetchAll(db, sql: "SELECT * FROM messages WHERE conversationId IN (\(placeholders)) ORDER BY conversationId, timestamp", arguments: StatementArguments(convIds))

            var messagesByConv: [String: [Message]] = [:]
            for msgRow in allMessageRows {
                guard let convId = msgRow["conversationId"] as? String else { continue }
                let message = try buildMessage(from: msgRow)
                messagesByConv[convId, default: []].append(message)
            }

            return try rows.map { row in
                guard let idStr: String = row["id"], let id = UUID(uuidString: idStr) else {
                    throw OrbitError.databaseCorruption("Missing or invalid conversation id")
                }
                guard let title: String = row["title"] else {
                    throw OrbitError.databaseCorruption("Missing title for conversation \(idStr)")
                }
                guard let createdAtInterval: TimeInterval = row["createdAt"] else {
                    throw OrbitError.databaseCorruption("Missing createdAt for conversation \(idStr)")
                }
                guard let updatedAtInterval: TimeInterval = row["updatedAt"] else {
                    throw OrbitError.databaseCorruption("Missing updatedAt for conversation \(idStr)")
                }
                let isPinned = intFromRow(row, key: "isPinned") != 0
                let hasGeneratedTitle = intFromRow(row, key: "hasGeneratedTitle") != 0
                let isArchived = intFromRow(row, key: "isArchived") != 0
                let modelConfig: ModelConfig? = decodeJSON(row["modelConfigJSON"] as? String)
                let workspaceId: UUID? = (row["workspaceId"] as? String).flatMap { UUID(uuidString: $0) }
                let messages = messagesByConv[id.uuidString] ?? []
                return Conversation(id: id, title: title, messages: messages, createdAt: Date(timeIntervalSince1970: createdAtInterval), updatedAt: Date(timeIntervalSince1970: updatedAtInterval), isPinned: isPinned, hasGeneratedTitle: hasGeneratedTitle, modelConfig: modelConfig, isArchived: isArchived, workspaceId: workspaceId)
            }
        }
    }

    func saveConversation(_ conversation: Conversation) throws {
        try db.write { db in
            try insertConversation(conversation, into: db)
        }
    }

    func replaceAllConversations(_ conversations: [Conversation]) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM messages")
            try db.execute(sql: "DELETE FROM conversations")
            for conversation in conversations {
                try insertConversation(conversation, into: db)
            }
        }
    }

    func incrementalSave(conversation: Conversation) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO conversations (id, title, createdAt, updatedAt, isPinned, hasGeneratedTitle, isArchived, modelConfigJSON, workspaceId)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                conversation.id.uuidString,
                conversation.title,
                conversation.createdAt.timeIntervalSince1970,
                conversation.updatedAt.timeIntervalSince1970,
                conversation.isPinned ? 1 : 0,
                conversation.hasGeneratedTitle ? 1 : 0,
                conversation.isArchived ? 1 : 0,
                encodeJSON(conversation.modelConfig),
                conversation.workspaceId?.uuidString
            ])
            for message in conversation.messages {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO messages (id, conversationId, role, content, timestamp, imagesJSON, planJSON, artifactsJSON)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    message.id.uuidString,
                    conversation.id.uuidString,
                    message.role.rawValue,
                    message.content,
                    message.timestamp.timeIntervalSince1970,
                    encodeJSON(message.images),
                    encodeJSON(message.plan),
                    encodeJSON(message.artifacts)
                ])
            }
        }
    }

    func deleteConversation(_ id: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE conversationId = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM conversations WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func insertConversation(_ conversation: Conversation, into db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO conversations (id, title, createdAt, updatedAt, isPinned, hasGeneratedTitle, isArchived, modelConfigJSON, workspaceId)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            conversation.id.uuidString,
            conversation.title,
            conversation.createdAt.timeIntervalSince1970,
            conversation.updatedAt.timeIntervalSince1970,
            conversation.isPinned ? 1 : 0,
            conversation.hasGeneratedTitle ? 1 : 0,
            conversation.isArchived ? 1 : 0,
            encodeJSON(conversation.modelConfig),
            conversation.workspaceId?.uuidString
        ])

        try db.execute(sql: "DELETE FROM messages WHERE conversationId = ?", arguments: [conversation.id.uuidString])
        for message in conversation.messages {
            let encryptedContent: String
            if let c = crypto {
                let data = try c.encrypt(message.content)
                encryptedContent = data.base64EncodedString()
            } else {
                encryptedContent = message.content
            }
            try db.execute(sql: """
                INSERT INTO messages (id, conversationId, role, content, timestamp, imagesJSON, planJSON, artifactsJSON)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                message.id.uuidString,
                conversation.id.uuidString,
                message.role.rawValue,
                encryptedContent,
                message.timestamp.timeIntervalSince1970,
                encodeJSON(message.images),
                encodeJSON(message.plan),
                encodeJSON(message.artifacts)
            ])
        }
    }

    private func buildMessage(from row: Row) throws -> Message {
        guard let midStr: String = row["id"] else {
            throw OrbitError.databaseCorruption("Missing message id")
        }
        guard let mid = UUID(uuidString: midStr) else {
            throw OrbitError.databaseCorruption("Invalid message id: \(midStr)")
        }
        guard let roleRaw: String = row["role"] else {
            throw OrbitError.databaseCorruption("Missing role for message \(midStr)")
        }
        guard let role = Message.Role(rawValue: roleRaw) else {
            throw OrbitError.databaseCorruption("Invalid role '\(roleRaw)' for message \(midStr)")
        }
        guard let storedContent: String = row["content"] else {
            throw OrbitError.databaseCorruption("Missing content for message \(midStr)")
        }
        let content: String
        if let c = crypto, let data = Data(base64Encoded: storedContent) {
            content = try c.decrypt(data)
        } else {
            content = storedContent
        }
        guard let timestampInterval: TimeInterval = row["timestamp"] else {
            throw OrbitError.databaseCorruption("Missing timestamp for message \(midStr)")
        }
        let timestamp = Date(timeIntervalSince1970: timestampInterval)
        let images: [ImageAttachment] = decodeJSON(row["imagesJSON"] as? String) ?? []
        let plan: Plan? = decodeJSON(row["planJSON"] as? String)
        let artifacts: [Artifact] = decodeJSON(row["artifactsJSON"] as? String) ?? []
        return Message(id: mid, role: role, content: content, images: images, timestamp: timestamp, plan: plan, artifacts: artifacts)
    }
}
