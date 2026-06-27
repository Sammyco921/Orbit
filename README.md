# Orbit — Autonomous Execution System for macOS

Orbit is a local-first, deterministic execution agent runtime for macOS. It translates natural-language intent into auditable, permission-gated tool execution — all without leaving your machine.

```
Intent → Plan → Permission → Execute → Observe → Adapt
```

## Why Orbit

Existing agent frameworks run as remote services or require cloud infrastructure. Orbit runs natively on macOS as a local background runtime — the agent lives on your machine, executes tools on your machine, and never sends raw execution data to third parties.

- **Local-first** — all execution, memory, and state stay on your machine
- **Auditable** — every action is logged and traceable through the event system
- **Permission-gated** — nothing executes without explicit or pre-approved consent
- **Deterministic** — execution follows a strict intent → plan → step pipeline

## Features

- **Background execution runtime** — persistent agent process with job scheduling and crash recovery
- **Menu bar controller** — quick access to agent state, conversations, and execution history
- **Tool execution system** — 30+ built-in tools: files, shell, browser, Git, clipboard, screenshots, and more
- **Agent orchestration** — ReAct loop with planning, self-correction, and multi-step execution
- **Workflow engine** — template-driven workflows with variable substitution and DAG-based step execution
- **Plugin system** — Swift-based plugins with sandboxed runtime, auto-restart, and timeout enforcement
- **Memory system** — hybrid semantic + FTS5 search, conversation summarization, user profile extraction
- **Research & browser tools** — web research, screenshot analysis, and screen understanding
- **MCP server** — Model Context Protocol socket for external AI tool integration
- **Multi-agent teams** — decompose goals across specialized sub-agents
- **LLM provider fallback** — chained providers with automatic failover
- **Graceful degradation** — survives database corruption, provider failures, and plugin crashes

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+ or Swift 5.9+ toolchain
- An API key for at least one LLM provider (OpenAI, Anthropic, or local via Ollama/LM Studio)

## Getting Started

```bash
# Build
swift build

# Run
swift run Orbit
```

On first launch, Orbit creates an empty conversation. Type a message to begin.

Orbit depends only on [GRDB.swift](https://github.com/groue/GRDB.swift) for SQLite persistence. All other functionality is built on system frameworks.

### LLM Provider Configuration

```bash
# OpenAI
export OPENAI_API_KEY="sk-..."

# Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."

# Local (Ollama)
# Start Ollama, then select "Local" in the model picker
```

API keys and model settings can also be managed through the settings panel (`Cmd+,`). Keys are stored in the system Keychain.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    UI Layer                          │
│  SwiftUI (MenuBar, OverlayPanel, ConversationView)  │
└──────────────────────┬──────────────────────────────┘
                       │ intent
                       ▼
┌─────────────────────────────────────────────────────┐
│                  UXOrchestrator                      │
│  State machine: idle → interpreting → planning →    │
│  executing → completed / failed / cancelled         │
└──────────────────────┬──────────────────────────────┘
                       │ execution story
                       ▼
┌─────────────────────────────────────────────────────┐
│                 ExecutionKernel                      │
│  Intent → Plan → PermissionGate → Tools             │
│  ReAct loop, self-correction, retry logic           │
└──────────────┬───────────────────┬──────────────────┘
               │                   │
               ▼                   ▼
┌─────────────────────────┐  ┌─────────────────────────┐
│    PermissionGate       │  │   Tool Registry         │
│  Explicit approval for  │  │  30+ built-in tools     │
│  sensitive operations   │  │  Plugin-hosted tools    │
└─────────────────────────┘  └─────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│           OrbitBackgroundRuntime                     │
│  Persistent agent process, job scheduler, event bus │
│  Memory store, conversation management, workspace   │
└─────────────────────────────────────────────────────┘
```

### Key components

| Component | Responsibility |
|-----------|---------------|
| `UXOrchestrator` | UI state machine; manages execution story lifecycle |
| `ExecutionKernel` | Intent-to-plan pipeline, ReAct agent loop, step execution |
| `PermissionGate` | Approves or denies sensitive tool calls |
| `ToolRegistry` | Discovers and routes tool calls to implementations |
| `OrbitBackgroundRuntime` | Persistent agent process; job scheduling and state persistence |
| `MemoryStore` | Semantic + FTS5 hybrid search over conversation history |

## Safety Model

Safety is a first-class concern in Orbit. The system is designed to prevent unauthorized or accidental system modification.

- **Permission gate** — every sensitive tool call (file write, shell execution, Git push) requires explicit approval or a pre-configured session allowlist
- **Tool sandboxing** — shell commands are validated against an allowlist of safe executables; dangerous patterns are blocked at the tool level
- **Plugin sandbox** — Swift plugins run with macOS sandbox profiles restricting filesystem access to temporary directories
- **No silent execution** — the agent cannot execute without a clear intent submitted through the UI or API
- **Full audit trail** — every tool invocation is recorded in the execution story with timestamps, inputs, and results
- **Keychain storage** — all API keys and OAuth tokens are stored in the system Keychain, not in configuration files

## Testing

```bash
swift test
```

The test suite includes 200+ tests covering the core execution pipeline, agent loop, tool system, memory, permissions, and graceful degradation scenarios.

Tests run automatically via GitHub Actions on push and pull requests to `main` and `release` branches.

## Extensibility

### Tool Protocol

Implement the `Tool` protocol to add new capabilities:

```swift
struct MyTool: Tool {
    var name: String { "my_tool" }
    var parameters: [ToolParameter] { ... }
    func execute(input: ToolInput, context: ExecutionContext) async throws -> ToolOutput { ... }
}
```

Register it with `ToolRegistry.register(MyTool())`.

### Plugin Architecture

Plugins are standalone Swift packages loaded at runtime, running in a sandboxed macOS subprocess with configurable permissions, auto-restart on crash, and execution timeout.

### MCP Compatibility

Orbit exposes a Model Context Protocol server over a Unix socket, allowing any MCP-compatible client to discover and call Orbit tools.

## Project Structure

```
Sources/
  Orbit/            # Core library
    Agent/          # Agent loop, planner, executor agents
    Core/           # Orchestrator, database, runtime, event bus
    Design/         # Design system, animation, voice consistency
    Discovery/      # Service discovery (GitHub, Gmail, Notion, Drive)
    Execution/      # Script engine, screenshot engine
    Generation/     # Document, PDF, spreadsheet generation
    Integrations/   # Slack, GitHub, Notion, Gmail, Calendar connectors
    Jobs/           # Job scheduler, execution engine, replay
    Kernel/         # Execution kernel, capability runtime, permissions
    LLM/            # Provider wrappers (OpenAI, Anthropic, Local)
    Memory/         # Memory store, vector index, embeddings
    Models/         # Data types (Message, Conversation, Workspace, etc.)
    Monitoring/     # System monitoring and telemetry
    OAuth/          # OAuth flow and token management
    Plugins/        # Plugin system with sandboxed runtime
    Research/       # Web research and browser engine
    Services/       # Service layer (Conversation, LLM, Tool, Agent)
    Templates/      # Workflow template engine
    Tools/          # 30+ tool implementations
    UX/             # UX state machine and orchestration
    Views/          # SwiftUI views
    Visual/         # Screen understanding and element detection
  OrbitApp/         # macOS app entry point
Tests/              # Unit tests
```

## Roadmap

- Multi-job scheduling and concurrent agent execution
- Long-running background agents with periodic triggers
- Crash recovery and execution resume from checkpoints
- Distributed execution nodes (future)

## License

MIT
