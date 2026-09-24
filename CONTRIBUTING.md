# Contributing to IntuneGraph

**You do not need an Intune tenant to contribute.** Every test, the demo mode and
the whole query engine run against fixtures on disk — verbatim Microsoft Graph
response bodies committed to this repository. Clone it, run `.\build.ps1`, and
you have a working Contoso tenant with nested groups, exclusions, filters and one
of every hygiene defect, offline.

That is deliberate. A reporting tool for production tenants cannot ask its
contributors to point it at a production tenant.

## Prerequisites

| | |
|---|---|
| PowerShell | 7+ recommended, Windows PowerShell 5.1 supported (both are covered in CI) |
| Pester | 5.0+ — `Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser` |
| PSScriptAnalyzer | `Install-Module PSScriptAnalyzer -Scope CurrentUser` |

`Microsoft.Graph.Authentication` is only needed if you intend to run against a
live tenant. Nothing in the test suite loads it.

## Repository layout

```
src/IntuneGraphKit/
├── Public/          one file per exported cmdlet — this is the supported surface
├── Private/         internals: Fetch, Normalize, GraphModel, Query, Emit, Mcp, Util
├── DemoData/        the Contoso tenant shipped to users via -DemoData
└── Assets/          the self-contained HTML report template
tests/
├── IntuneGraph.Tests.ps1     the Pester 5 suite
├── New-ContosoFixtures.ps1   the generator that writes both fixture trees
└── Fixtures/contoso/         what the tests read
docs/                fixtures, permissions, MCP wiring, discoverability
tools/mcp/           the MCP stdio launcher
tools/gif/           the README demo recorder
site/                the Astro page behind the GitHub Pages demo
```

Screenshots and the README animation live in `docs/img/`, and
[`docs/img/README.md`](docs/img/README.md) says how each one is produced — `demo.gif` is
rendered headlessly by `tools/gif/`, not screen-captured, so regenerating it needs a
fresh `Export-IntuneGraph -DemoData` rather than a recording session.

The rule that keeps the codebase honest: **`Invoke-IgRequest` is the only seam
that knows whether data is live or mocked.** Fetchers, normalisers, the graph
builder, queries and the emitters are all mode-blind. If a change makes any of
them aware of where the data came from, it belongs somewhere else.

## Running the build

```powershell
.\build.ps1                # Analyze, then Test — what CI runs
.\build.ps1 -Task Test     # Pester only
.\build.ps1 -Task Analyze  # PSScriptAnalyzer only
.\build.ps1 -Task Fixtures # regenerate the Contoso dataset
.\build.ps1 -Task Publish  # release workflow only — see Releasing
```

CI runs `Analyze` then `Test` for every push and pull request on Windows
PowerShell 5.1 and PowerShell 7 on `windows-latest`, and PowerShell 7 on
`ubuntu-latest`, so run both locally before you open one.

### PSScriptAnalyzer

Settings live in [`PSScriptAnalyzerSettings.psd1`](PSScriptAnalyzerSettings.psd1)
and apply to `src/IntuneGraphKit` recursively. Severity is `Error` and `Warning`;
**errors fail the build, warnings do not.** Three rules are excluded, each with
its reason written next to it — `PSAvoidUsingWriteHost` because the report
cmdlets write formatted output to the host on purpose,
`PSUseShouldProcessForStateChangingFunctions` because `Export`/`Import` act on
the graph model rather than the tenant, and `PSUseSingularNouns` for the private
`Get-Ig*` helpers that genuinely return collections.

Suppress a rule inline only with a comment saying why. If you find yourself
adding a fourth global exclusion, raise an issue first — the exclusion list is
meant to stay short enough to read.

## Adding a scenario or a fixture

Fixtures are generated, not hand-edited, so that the test tree and the shipped
demo data cannot drift apart. To add a scenario:

1. Edit the identity tables and workload definitions at the top of
   [`tests/New-ContosoFixtures.ps1`](tests/New-ContosoFixtures.ps1).
2. Run `.\build.ps1 -Task Fixtures`. It rewrites both `tests/Fixtures/contoso`
   and `src/IntuneGraphKit/DemoData`.
3. Update the expected counts in `tests/IntuneGraph.Tests.ps1` — they are
   asserted, and a scenario nobody counted is a scenario nobody tested.
4. Commit the regenerated JSON along with your change.

A fixture file holds the exact wire shape Graph returns, `{ "value": [ ... ] }`,
under the path mapping described in [docs/fixtures.md](docs/fixtures.md).
Multi-page responses use `{ "pages": [ ... ] }` so paging stays exercised. A
missing fixture is a hard error by design: a silent empty result would hide a
bug rather than surface one.

The Contoso dataset is built so **each hygiene check fires exactly once**. If you
add a defect to the fixtures, add the assertion that catches it in the same pull
request, and keep it to one instance — the one-of-each property is what makes
`Find-IntuneOrphan` regressions obvious.

## Things this project will not accept

These are not style preferences; they are the guarantees the README and
[SECURITY.md](SECURITY.md) make to people running this against a live tenant.

- **No write paths to Graph.** The single function that calls Graph hardcodes
  `GET`. A `POST`, `PATCH`, `PUT` or `DELETE` anywhere in `src/` will be
  rejected, however convenient.
- **No new Graph scopes** beyond the four read-only ones in
  [docs/permissions.md](docs/permissions.md) without a discussion first.
- **No network calls from the HTML report.** The renderer is vendored inline and
  stays that way — no CDN, no font fetch, no telemetry.
- **No real tenant data in fixtures, issues or pull requests.** Redact, or
  reproduce against `-DemoData`.

## Commit messages and pull requests

Write commit subjects as conventional commits — `feat:`, `fix:`, `docs:`,
`test:`, `chore:`, `ci:` — in the imperative, under about 72 characters, with a
body that says *why* the change matters rather than restating the diff. Some
older history predates the convention; new commits follow it.

A pull request wants:

- one logical change, with the tests that prove it,
- `.\build.ps1` green locally,
- a `CHANGELOG.md` entry under *Unreleased* for anything a user would notice —
  the format is [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and
  versions follow [SemVer](https://semver.org/),
- documentation updated in the same pull request when behaviour changes.

## Releasing

Releases go out from CI, never from a workstation. The module is published to the
PowerShell Gallery as **IntuneGraphKit** — `IntuneGraph` on the Gallery is an
unrelated module by another author, which is why the two names differ (see
[docs/discoverability.md](docs/discoverability.md#the-gallery-name-intunegraphkit)).

1. Move the *Unreleased* entries in `CHANGELOG.md` under the new version and date.
2. Set `ModuleVersion` in `src/IntuneGraphKit/IntuneGraphKit.psd1` to that version.
3. Merge to `main`, then tag the merge commit and push the tag —
   `git tag v0.3.0`, then `git push origin v0.3.0`.

The Release workflow re-runs the whole CI matrix on the tagged commit, checks that the
tag matches `ModuleVersion`, and only then publishes. A Gallery version can be unlisted
but its number can never be reused, so that check is the last point at which a mistake
costs nothing.

The API key exists only as the `PSGALLERY_API_KEY` repository secret.
`build.ps1 -Task Publish` reads it from the environment and refuses to run without
it; there is deliberately no parameter for it.

## Where to start

Issues labelled
[good first issue](https://github.com/juandresrodca/IntuneGraph/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
are scoped so that reading `docs/fixtures.md` is enough context to finish them.
Extending the fixture documentation with real-world assignment shapes (#2) and
adding demo scenarios for edge cases (#3) both land squarely in the fixture
workflow above.

Reporting an assignment your tenant resolves differently from IntuneGraph is
just as valuable as code — that is the class of bug fixtures cannot invent.
Please include the shape of the assignment, not the tenant data.

## Security

Do not open a public issue for a security problem. The private reporting route,
the supported versions and the invariants this project treats as non-negotiable
are in [SECURITY.md](SECURITY.md).

## Licence

By contributing, you agree that your contributions are licensed under the
[MIT Licence](LICENSE) that covers this repository.
