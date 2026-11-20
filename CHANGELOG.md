# Changelog

All notable changes to IntuneGraph are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[SemVer](https://semver.org/).

`0.1.0` and `0.2.0` predate the release pipeline: both are described below, but neither
carries a git tag or a GitHub release, so `-RequiredVersion 0.1.0` cannot be installed
and no `v0.1.0...v0.2.0` comparison exists. Tagging starts at `0.3.0`: from there the comparison links at the foot
of this file are tag ranges, and the two versions before it keep their commit ranges.

## [Unreleased]

## [0.3.0] - 2026-11-15

The first version published to the PowerShell Gallery. A minor bump rather than a patch
because the module name changed, and pre-1.0 SemVer puts a breaking change there.

### Changed
- The README's quick start leads with the route that works today. `Install-Module
  IntuneGraphKit` was the first command a visitor ran and it fails, because the module
  is not on the PowerShell Gallery yet ([#5](https://github.com/juandresrodca/IntuneGraph/issues/5));
  the clone-and-import sequence from
  [docs/troubleshooting.md](docs/troubleshooting.md) now leads instead, with
  `Install-Module` kept underneath and marked as the route once published. The Gallery
  version badge is out of the badge row until that publish — it rendered as *not found*,
  which reads as a broken project rather than an unreleased one. Restoring both is step 6
  of *Prepare the release* in [docs/publishing.md](docs/publishing.md).
- **BREAKING — the module is now `IntuneGraphKit`**: `Install-Module IntuneGraphKit`,
  `Import-Module IntuneGraphKit`. The name `IntuneGraph` on the PowerShell Gallery
  belongs to an unrelated module by another author, and a Gallery package name has to
  match the module name. Cmdlet names, the `graph.json` format, the MCP server name and
  the project name are unchanged. If you import from a clone, the path is now
  `src/IntuneGraphKit/IntuneGraphKit.psd1`. Existing scripts need their
  `Import-Module IntuneGraph` line changed to `Import-Module IntuneGraphKit`; nothing
  else in a caller changes, because no cmdlet was renamed.
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
- Dependabot covers the two npm trees and the workflow actions: `site` (the Astro
  page `pages.yml` publishes) and `tools/gif` (the demo recorder) weekly with minor
  and patch grouped per tree, and `github-actions` monthly. The actions entry is the
  one that matters most — `release.yml` publishes to the PowerShell Gallery, so an
  abandoned or compromised action there has the widest reach of anything in the
  repository. `*.psd1` module dependencies are not a dependabot ecosystem and remain
  unwatched.
- Gallery listing metadata: `CompatiblePSEditions` plus the `PSEdition_Desktop` and
  `PSEdition_Core` tags, so the module appears under both edition filters, and an icon.

### Fixed
- The documentation calls the demo tenant by the name the demo data gives it.
  `src/IntuneGraphKit/DemoData/manifest.json` sets `tenantName` to **Silver Chariot
  Corporate**, which is what the viewer header, the hosted demo and the MCP
  `intune_summary` tool have always reported, while the README, `CONTRIBUTING.md`,
  `SECURITY.md`, `docs/fixtures.md`, `docs/publishing.md` and both issue forms still
  called it Contoso from an earlier version of the data. The prose now agrees with the
  data, so the FAQ entry and the known-issue row that existed only to explain the
  disagreement are gone ([#12](https://github.com/juandresrodca/IntuneGraph/issues/12)).
  Filenames and paths are deliberately untouched: `tests/New-ContosoFixtures.ps1`, the
  `build.ps1` task that calls it and `tests/Fixtures/contoso/` are source, and renaming
  them is a separate decision with its own regeneration step.
- The bug-report form's reproduction placeholder queried `CONTOSO-LT-004`, a device the
  demo tenant does not contain, so copying it returned nothing. It now uses
  `DEV-FIN-01`, which is in the bundled data.

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

<!-- Comparison links. 0.3.0 is the first tag, so it and Unreleased are tag links under
     rule 5 of the anchor rule. 0.1.0 and 0.2.0 were never tagged and keep the commit
     bounds they shipped at, under rules 1 to 3 of
     https://github.com/juandresrodca/EntraHuntKit/blob/main/docs/changelog-anchors.md#the-anchor-rule
     which is where the convention and the reasoning for it now live. The boundaries are
     local to this repository: 0.2.0 is the single commit c79a3c1, and e2c3fb8 is the
     commit before it, the last of the 0.1.0 era. -->
[Unreleased]: https://github.com/juandresrodca/IntuneGraph/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/juandresrodca/IntuneGraph/releases/tag/v0.3.0
[0.2.0]: https://github.com/juandresrodca/IntuneGraph/compare/e2c3fb8...c79a3c1
[0.1.0]: https://github.com/juandresrodca/IntuneGraph/commits/e2c3fb8
