# Fixtures & the Contoso demo tenant

IntuneGraph's tests and `-DemoData` mode run against **fixtures**: verbatim
Microsoft Graph response bodies stored on disk. This means the whole tool — and
its test suite — works with **no tenant, no credentials, and no network**.

## How the switch works

`Invoke-IgRequest` is the only seam that knows whether data is live or mocked:

- **Live:** `Export-IntuneGraph` after `Connect-IntuneGraph` → real Graph calls.
- **Fixture:** `Export-IntuneGraph -FromFixtures <dir>` or `-DemoData` → files.

Fetchers, normalizers, the graph builder, queries and the HTML emitter are all
mode-blind.

## Path mapping

A Graph path maps to a file by stripping the query string and appending `.json`
under `<root>/<api>/`:

| Graph request | Fixture file |
|---|---|
| `beta /deviceManagement/configurationPolicies` | `beta/deviceManagement/configurationPolicies.json` |
| `v1.0 /groups` | `v1.0/groups.json` |
| `v1.0 /groups/{id}/members` | `v1.0/groups/{id}/members.json` |

Each file holds the exact wire shape: `{ "value": [ ... ] }`. Multi-page
responses can use `{ "pages": [ {"value":[...]}, ... ] }` to exercise paging.
A missing fixture is a hard error (silent empties would hide bugs).

## The Contoso dataset

`tests/Fixtures/contoso` (mirrored to `src/IntuneGraph/DemoData`) is designed so
**each hygiene check fires exactly once** and every query scenario is covered:

- **Nesting:** `SG-AllStaff` ⊃ `SG-Finance`, `SG-IT` → tests the `Via` path.
- **Exclusion-wins:** `LOB Finance App` includes `SG-Finance`, excludes `SG-Contractors`.
- **Filter annotation:** `Win Compliance` → All Devices with filter `F-CorpOwned`.
- **Hygiene one-of-each:** `Orphan Wi-Fi Profile` (Unassigned), `Kiosk Lockdown` →
  `SG-Empty` (EmptyTarget), `Legacy VPN Profile` (IncludeExcludeCollision),
  `Old CRM` → deleted `SG-Legacy` (BrokenGroupReference), `F-Unused` (UnusedFilter),
  `BYOD Compliance` excluding user group (MixedTargeting).

## Regenerating / extending

The dataset is emitted by a generator so it stays consistent:

```powershell
.\tests\New-ContosoFixtures.ps1
```

Edit the identity tables and workload definitions at the top of that script, then
re-run it to rewrite both the test fixtures and the bundled demo data. Update the
expected counts in `tests/IntuneGraph.Tests.ps1` accordingly.
