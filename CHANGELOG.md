# Changelog

All notable changes to IntuneGraph are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[SemVer](https://semver.org/).

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
