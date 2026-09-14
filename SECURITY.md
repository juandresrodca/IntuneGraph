# Security Policy

IntuneGraph reads production Microsoft 365 tenants. That deserves a stated policy
rather than an assumption, so here it is.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Report privately through GitHub:
[Security → Report a vulnerability](https://github.com/juandresrodca/IntuneGraph/security/advisories/new).
If private reporting is unavailable to you, email **juandresrodca@gmail.com** with
`IntuneGraph security` in the subject.

Please include:

- the module version (`(Get-Module IntuneGraphKit).Version`) and PowerShell version
  (`$PSVersionTable.PSVersion`),
- what you did, what happened, and what you expected,
- a minimal reproduction — **against `-DemoData` wherever possible**, never against a
  real tenant export,
- any redacted output (see *Sharing evidence safely* below).

What to expect:

| Stage | Target |
|---|---|
| Acknowledgement | 72 hours |
| Initial assessment | 7 days |
| Fix or documented mitigation | 90 days, sooner where the severity warrants |
| Public disclosure | after a fix ships, credit given unless you ask otherwise |

This is a personal open-source project maintained outside working hours. There is no
bug bounty; there is a genuine commitment to answering you and to crediting you.

## Supported versions

| Version | Supported |
|---|---|
| 0.2.x | ✅ current |
| 0.1.x | ⚠️ security fixes only |
| `main` | ✅ fixes land here first |

Until 1.0, the supported version is the latest tagged release plus `main`.

## What IntuneGraph does and does not do

These are the security properties the project treats as invariants. A breach of any of
them is a vulnerability, and should be reported as one.

**Read-only against Microsoft Graph.** The module requests four read scopes and zero
write scopes:

| Scope | Covers |
|---|---|
| `DeviceManagementConfiguration.Read.All` | configuration, compliance, scripts, filters |
| `DeviceManagementApps.Read.All` | apps and their assignments |
| `DeviceManagementManagedDevices.Read.All` | managed devices |
| `Group.Read.All` | groups and group membership |

The single function that calls Graph hardcodes `GET`. There is no `POST`, `PATCH`,
`PUT` or `DELETE` path anywhere in the codebase. `Directory.Read.All` and
`User.Read.All` are deliberately **not** requested. Full detail in
[`docs/permissions.md`](docs/permissions.md).

**No telemetry, no outbound calls from the report.** The generated HTML report vendors
its renderer inline and makes zero network requests. Nothing is sent anywhere; there is
no analytics, no update check, no error reporting.

**The MCP server never touches your tenant.** `Start-IntuneGraphMcp` serves a local
`graph.json` snapshot over stdio. It holds no credentials and cannot refresh itself —
you decide when to re-export. An AI assistant wired to it gets answers about your
tenant, never access to it.

**Credentials are never persisted.** Authentication goes through the Microsoft
Authentication Library; IntuneGraph does not write tokens, secrets or client IDs to
disk, and does not read them from configuration files.

## The part that is on you: `graph.json` is sensitive

An exported graph contains device names, user principal names, group names and
membership, and your full assignment topology. That is a map of your estate. Treat the
export the way you would treat any tenant extract:

- keep it out of source control — the shipped [`.gitignore`](.gitignore) excludes
  `*.graph.json` and `graph.json`, but verify before you commit,
- do not attach a real export to an issue, a discussion or a support ticket,
- store it on encrypted media, and delete it when the analysis is done,
- remember that the generated HTML report embeds the same data.

## Sharing evidence safely

To reproduce almost anything, `-DemoData` is enough:

```powershell
Import-Module IntuneGraphKit
Export-IntuneGraph -DemoData -PassThru | Show-IntuneGraph
```

The bundled Contoso tenant exercises nested groups, filters and include/exclude
collisions without a single real identifier. If a report genuinely needs tenant shape,
send counts and structure — "1 400 devices, 6-deep nesting, 3 exclusion groups" — not
names, not GUIDs, not the file.

## Out of scope

- Vulnerabilities in Microsoft Graph, Intune or Entra ID — report those to
  [MSRC](https://msrc.microsoft.com/report).
- Anything requiring an attacker who already has your `graph.json` or your tenant
  credentials.
- Findings from automated scanners with no demonstrated impact.
- The GitHub Pages demo, which serves static, fictional data.
