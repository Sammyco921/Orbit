Security Policy

Orbit is a local-first AI agent runtime that can execute system-level tools on macOS. Because of this, security issues are taken seriously.

Supported Versions

Security fixes are applied to the latest stable release only.

Reporting a Vulnerability

If you discover a security vulnerability, please do not open a public issue.

Instead, report it privately via GitHub Security Advisories or contact the maintainer directly.

Please include:

* description of the issue
* steps to reproduce
* potential impact
* any suggested mitigation (if available)

Scope

The following areas are in scope:

* MCP server transport layer
* tool execution system (especially system commands)
* plugin system (future)
* memory and workspace data isolation
* API endpoints (future HTTP layer)

Out of scope:

* misuse of tools when explicitly approved by the user
* issues in third-party dependencies unless exploitable through Orbit directly

Security Model

Orbit assumes a user-controlled trust model:

* tools must explicitly request permission for sensitive actions
* MCP connections require local socket or explicit transport setup
* plugins run in isolated subprocesses (when enabled)
* no remote execution is allowed by default

Users are responsible for:

* approving tool execution
* managing plugin installations
* controlling API exposure if enabled

Disclosure Policy

We aim to:

* acknowledge reports within 72 hours
* provide a fix or mitigation plan as soon as feasible
* coordinate disclosure once a patch is available
