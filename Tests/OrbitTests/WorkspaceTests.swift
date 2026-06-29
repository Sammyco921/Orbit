import Testing
import Foundation
@testable import Orbit

// MARK: - Workspace model

@Test func workspaceDefaults() {
    let ws = Workspace(name: "Test")
    #expect(ws.name == "Test")
    #expect(ws.icon == "folder")
    #expect(ws.path == nil)
}

@Test func workspaceCustomIcon() {
    let ws = Workspace(name: "Dev", icon: "hammer")
    #expect(ws.icon == "hammer")
}

// MARK: - DB workspace CRUD

@Test func dbSaveAndLoadWorkspace() throws {
    let db = try OrbitDatabase(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test_ws_\(UUID().uuidString).sqlite"))
    defer { try? FileManager.default.removeItem(at: db.storageURL) }

    let ws = Workspace(name: "My Project", icon: "star")
    try db.saveWorkspace(ws)

    let loaded = try db.loadAllWorkspaces()
    #expect(loaded.count == 1)
    #expect(loaded[0].name == "My Project")
    #expect(loaded[0].icon == "star")
}

@Test func dbDeleteWorkspaceNullifiesConversations() throws {
    let db = try OrbitDatabase(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test_ws_del_\(UUID().uuidString).sqlite"))
    defer { try? FileManager.default.removeItem(at: db.storageURL) }

    let ws = Workspace(name: "Temp")
    try db.saveWorkspace(ws)

    let conv = Conversation(workspaceId: ws.id)
    try db.saveConversation(conv)

    try db.deleteWorkspace(ws.id)

    let loaded = try db.loadAllConversations()
    #expect(loaded[0].workspaceId == nil, "workspaceId should be null after workspace deletion")
}

@Test func dbFilterConversationsByWorkspace() throws {
    let db = try OrbitDatabase(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test_ws_filter_\(UUID().uuidString).sqlite"))
    defer { try? FileManager.default.removeItem(at: db.storageURL) }

    let ws1 = Workspace(name: "A")
    let ws2 = Workspace(name: "B")
    try db.saveWorkspace(ws1)
    try db.saveWorkspace(ws2)

    try db.saveConversation(Conversation(workspaceId: ws1.id))
    try db.saveConversation(Conversation(workspaceId: ws2.id))

    let ws1Convs = try db.loadAllConversations(workspaceId: ws1.id)
    #expect(ws1Convs.count == 1)
    #expect(ws1Convs[0].workspaceId == ws1.id)

    let ws2Convs = try db.loadAllConversations(workspaceId: ws2.id)
    #expect(ws2Convs.count == 1)
    #expect(ws2Convs[0].workspaceId == ws2.id)
}

// MARK: - Conversation model

@Test func conversationDefaultsToNoWorkspace() {
    let conv = Conversation()
    #expect(conv.workspaceId == nil)
}

@Test func conversationWithWorkspaceId() {
    let wsId = UUID()
    let conv = Conversation(workspaceId: wsId)
    #expect(conv.workspaceId == wsId)
}

// MARK: - WorkspaceService

@Test func workspaceServiceCreatesAndLists() {
    let service = WorkspaceService()

    let ws = service.createWorkspace(name: "Test")
    #expect(service.workspaces.count == 1)
    #expect(service.activeWorkspaceId == ws.id)
    #expect(service.activeWorkspace?.name == "Test")
}

@Test func workspaceServiceDeleteSelectsNext() {
    let service = WorkspaceService()
    let ws1 = service.createWorkspace(name: "A")
    let ws2 = service.createWorkspace(name: "B")

    service.deleteWorkspace(ws1.id)
    #expect(service.workspaces.count == 1)
    #expect(service.activeWorkspaceId == ws2.id)
}

// MARK: - Conversation filtered by workspace

@Test func filteredConversationsByWorkspace() {
    let ws1 = UUID()
    let ws2 = UUID()
    let convs = [
        Conversation(workspaceId: ws1),
        Conversation(workspaceId: ws2),
        Conversation(workspaceId: nil),
    ]

    let filtered = convs.filter { $0.workspaceId == nil || $0.workspaceId == ws1 }
    #expect(filtered.count == 2)
    #expect(filtered[0].workspaceId == ws1)
    #expect(filtered[1].workspaceId == nil)
}
