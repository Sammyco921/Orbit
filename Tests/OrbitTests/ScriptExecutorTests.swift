import Testing
import Foundation
@testable import Orbit

struct ScriptExecutorTests {

    @Test func structuredRunReturnsStdout() async throws {
        let executor = ScriptExecutor()
        let output = try await executor.run(executable: "/bin/echo", arguments: ["hello world"])
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
    }

    @Test func structuredRunWithMultipleArgs() async throws {
        let executor = ScriptExecutor()
        let output = try await executor.run(executable: "/bin/echo", arguments: ["-n", "foo", "bar"])
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "foo bar")
    }

    @Test func structuredRunPropagatesNonZeroExit() async {
        let executor = ScriptExecutor()
        await #expect(throws: (any Error).self) {
            try await executor.run(executable: "/usr/bin/false", arguments: [])
        }
    }

    @Test func structuredRunRejectsEmptyExecutable() async {
        let executor = ScriptExecutor()
        await #expect(throws: (any Error).self) {
            try await executor.run(executable: "", arguments: ["foo"])
        }
    }

    @Test func structuredRunRejectsShellInjection() async throws {
        let executor = ScriptExecutor()
        let malicious = "hello; rm -rf /"
        let output = try await executor.run(executable: "/bin/echo", arguments: [malicious])
        // The semicolon and subsequent command should be treated as literal text
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).contains("hello; rm -rf /"))
    }

    @Test func structuredRunRejectsArgumentInjection() async throws {
        let executor = ScriptExecutor()
        let inject = "$(whoami)"
        let output = try await executor.run(executable: "/bin/echo", arguments: [inject])
        // Should echo the literal string, not execute whoami
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "$(whoami)")
    }

    @Test func runShellIsDeprecatedWrapper() async throws {
        let executor = ScriptExecutor()
        let output = try await executor.runShell("echo hello")
        #expect(output.contains("hello"))
    }
}
