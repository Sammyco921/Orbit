# Orbit

Orbit is a local-first AI agent that lives on your machine and helps you get real work done across files, tools, and applications—while keeping you in full control of your data and execution.

It is designed to act less like a chatbot and more like a system-level assistant that can plan, reason, and safely execute tasks inside your environment.

## What Orbit is

Orbit is an extensible agent runtime for macOS that connects AI reasoning with real system capabilities.

You describe intent in natural language. Orbit translates that into structured plans, executes them through tools, and keeps every step transparent and recoverable.

## Core principles

- **Local-first by default** – your data and execution stay on your machine
- **Tool-based intelligence** – capabilities come from tools, not hidden prompts
- **Plan before execution** – complex tasks are decomposed into structured plans
- **Fully observable** – every action is traceable and recoverable
- **Extensible by design** – new tools and plugins expand what Orbit can do

## What it can do

Orbit can:
- Execute multi-step workflows using a planning system
- Interact with your filesystem and development environment
- Work with Git repositories through structured tools
- Run tasks safely with approval controls for sensitive operations
- Maintain workspace-scoped context and memory
- Integrate external capabilities through MCP-compatible tools

## Architecture at a glance

Orbit is built around a deterministic agent loop:

1. User intent is received
2. A structured plan is generated (or fallback reasoning is used)
3. Tasks are executed through tools in a controlled runtime
4. State is checkpointed after each step
5. Results are streamed back to the interface

Everything is event-driven, observable, and recoverable.

## Current status

Orbit is under active development.

- Core agent runtime: implemented
- Planning system: implemented
- MCP transport layer: implemented
- Workspace system: implemented
- Git tooling: implemented
- UI layer: in progress

This is an early but functional platform, not a finished product.

## Why Orbit exists

Most AI tools today are either:
- chat interfaces with no real system access, or
- closed platforms where you lose control over execution and data

Orbit is an attempt to bridge that gap—bringing structured AI reasoning into a local, transparent, and extensible runtime that developers can actually build on.

## License

AGPL-3.0 — see LICENSE file for details.

## Contributing

This project is early-stage and evolving quickly. Contributions, ideas, and feedback are welcome once the initial architecture stabilizes.

For now, the best way to help is to build with it, break it, and see where it fails.

## Status

Orbit is actively evolving through a multi-phase build toward a full local-first agent platform.
