# Changelog

All notable changes to IntuneGraph are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[SemVer](https://semver.org/).

## [Unreleased]

### Changed
- **The module is now `IntuneGraphKit`**: `Install-Module IntuneGraphKit`,
  `Import-Module IntuneGraphKit`. The name `IntuneGraph` on the PowerShell Gallery
  belongs to an unrelated module by another author, and a Gallery package name has to
  match the module name. Cmdlet names, the `graph.json` format, the MCP server name and
  the project name are unchanged. If you import from a clone, the path is now
  `src/IntuneGraphKit/IntuneGraphKit.psd1`.
- The README no longer tells visitors to run `Install-Module IntuneGraph`, which
  installed that unrelated module instead of this one.
- The manifest `Description` is now the same text as the repository description, and
  the module has a freshly generated `GUID` ahead of its first Gallery publish.

### Added
- [docs/FAQ.md](docs/FAQ.md): thirteen questions that keep arriving — which Gallery
  package to install and why the name matters, delegated versus app-only auth, why an
  exclusion beats an include through a nested group, what `AppliesPreFilter` does and
  does not claim, why `Get-IntuneTarget` can return nothing, what an export costs on a
  large tenant, whether `graph.json` is safe to share, and 5.1 versus 7. Linked from
  the README.
- Release pipeline: pushing a `v*` tag re-runs the full CI matrix and, when it is green
  and the tag matches `ModuleVersion`, publishes to the PowerShell Gallery
  (`.github/workflows/release.yml`, `build.ps1 -Task Publish`).
- Gallery listing metadata: `CompatiblePSEditions` plus the `PSEdition_Desktop` and
  `PSEdition_Core` tags, so the module appears under both edition filters, and an icon.

## [0.2.0] - 2026-09-06

### Added
- `Start-IntuneGraphMcp` — run IntuneGraph as an MCP (Model Context Protocol) stdio
  server, so an AI assistant can query the graph and answer *why* a policy applies,
  with the real membership path. Six read-only tools: `intune_target`,
  `intune_blast_radius` (including what-if membership changes), `intune_orphans`,
  `intune_path`, `intune_node`, `intune_summary`.
- Dual-era protocol support: the legacy `initialize` handshake (`2024-11-05` through
  `2025-11-25`, defaulting to `2025-06-18`) plus `server/discover`, so newer stateless
  clients can probe and negotiate instead of hanging on the stdio pipe.
- `tools/mcp/mcp-server.ps1` launcher and [docs/mcp.md](docs/mcp.md) with Claude Code,
  `.mcp.json` and VS Code Copilot wiring.
- The server serves a `graph.json` snapshot only — it never connects to Microsoft
  Graph, never writes a file, and forces the session to a disconnected state for its
  whole lifetime, so an assistant never receives tenant credentials. It reloads the
  snapshot automatically when the file changes on disk.

## [0.1.0] - 2026-07-24

Initial release.

### Added
- `Export-IntuneGraph` — read-only Graph snapshot to `graph.json` (config &
  compliance policies, apps, platform/remediation scripts, assignment filters,
  groups with nesting, members, managed devices, All-Devices/All-Users builtins).
- `Get-IntuneTarget` — resolve everything that applies to a device/user, with the
  full membership path, include/exclude (exclusion-wins) and filter annotation.
- `Get-IntuneBlastRadius` — group impact report plus `-WhatIfAddMember` /
  `-WhatIfRemoveMember` change simulation.
- `Find-IntuneOrphan` — six hygiene checks (Unassigned, EmptyTarget,
  IncludeExcludeCollision, BrokenGroupReference, UnusedFilter, MixedTargeting).
- `Show-IntuneGraph` — self-contained interactive HTML viewer (dependency-free
  renderer, zero network calls), with `-Focus` neighborhood mode.
- `Connect-IntuneGraph` / `Disconnect-IntuneGraph` — least-privilege, read-only.
- `Import-IntuneGraph` / `Get-IntuneGraphNode`.
- Bundled Contoso demo tenant (`-DemoData`) and fixture-driven Pester suite.
