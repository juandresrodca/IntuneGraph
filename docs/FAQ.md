# FAQ

Short answers to the questions that come up most. Where a question has a long
answer, it lives in [comparison.md](comparison.md) or [permissions.md](permissions.md)
and this page links to it rather than repeating it.

---

### Do I need an Intune tenant to try this?

No. `Export-IntuneGraph -DemoData` builds a complete graph from the demo tenant bundled
in the module — groups, nested groups, policies, apps, filters, orphans and
include/exclude collisions — with no Graph authentication and no network access at all.

```powershell
Export-IntuneGraph -DemoData -PassThru | Show-IntuneGraph -Open
```

Every test in the repository runs the same way, which is why you can contribute without
a tenant. [fixtures.md](fixtures.md) describes how the demo data is structured.

---

### Which module do I install? `IntuneGraph` or `IntuneGraphKit`?

**`IntuneGraphKit`.** The repository is called IntuneGraph; the Gallery package is
`IntuneGraphKit`.

```powershell
Install-Module IntuneGraphKit -Scope CurrentUser
```

This matters more than a naming quirk normally would: `IntuneGraph` on the PowerShell
Gallery is an unrelated module by another author, and unlike this one it **writes** to
Intune. Check the name before you install.
([#5](https://github.com/juandresrodca/IntuneGraph/issues/5) tracks the publication
state of the package.)

---

### What permissions does it need, and can it change anything in my tenant?

Four **read-only** delegated scopes and zero write scopes:
`DeviceManagementConfiguration.Read.All`, `DeviceManagementApps.Read.All`,
`DeviceManagementManagedDevices.Read.All`, `Group.Read.All`.

It cannot change anything, and not as a matter of policy: the single function that
reaches Microsoft Graph hardcodes `-Method GET`, and there is no `POST`, `PATCH` or
`DELETE` path anywhere in the module. [permissions.md](permissions.md) lists what is
deliberately *not* requested, including `Directory.Read.All` and every `ReadWrite`
scope.

---

### Delegated or app-only — which should I use?

Delegated (`Connect-IntuneGraph` with no arguments) for interactive work: you consent
once, the scopes are yours, and the export inherits your own visibility.

App-only, with a certificate, for anything unattended — a scheduled weekly hygiene
export, a pipeline:

```powershell
Connect-IntuneGraph -TenantId <tenant> -ClientId <appId> -CertificateThumbprint <thumb>
```

The four permissions are the same, granted as **Application** permissions with admin
consent. Use a certificate rather than a client secret; a secret in a scheduled task is
a credential sitting in plain text on a file share, and the four scopes it holds read
your whole directory's group membership.

---

### A user is in a group the policy targets, but `Get-IntuneTarget` says `Excluded`. Why?

Because an exclusion beats an include, always, no matter how the two are reached.
Intune resolves it that way and so does IntuneGraph: if any path from the entity — the
object itself, any group it belongs to, any group *those* groups nest into, or
All Users / All Devices — reaches an exclusion on that workload, the result is
`Excluded` and the include is dead.

Run `Get-IntuneTarget -Identity <x> -IncludeExcluded` to see the excluded workloads
alongside the applying ones, with the `Via` path that causes each. The most common
cause is a nested group somebody added six months ago; `Via` shows the full chain
rather than the group you were looking at.

If the *same* group is both included and excluded on one workload, that is a hygiene
finding rather than a puzzle — `Find-IntuneOrphan -Check IncludeExcludeCollision`
reports it as High, because the include can never fire.

---

### What does `AppliesPreFilter` mean — does the policy apply or not?

It means the assignment reaches this device **and carries an assignment filter that
IntuneGraph did not evaluate**. Read it as *"applies unless the filter says otherwise"*.

IntuneGraph names the filter and its mode (include/exclude) and stops there. It does not
evaluate the filter rule against a device's properties, because the snapshot holds the
assignment graph, not per-device attributes. Check the rule in the admin centre for the
final answer. This is one of several deliberate boundaries — the full list is
[what IntuneGraph will not tell you](comparison.md#what-intunegraph-will-not-tell-you).

---

### `Get-IntuneTarget` returns nothing for a device I know has policies

In rough order of likelihood:

1. **The device is not in the snapshot.** If the export ran with `-SkipDevices`, there
   are no device nodes to resolve. Re-export without it.
2. **The identity did not match.** `-Identity` accepts a device name, a UPN or a GUID,
   and matches what is in the snapshot. `Get-IntuneGraphNode` lists what was actually
   exported, which is the quickest way to see the name the graph knows.
3. **The assignments are newer than the snapshot.** The graph is a point-in-time file.
   Re-export.
4. **The targeting is outside the exported surface.** Conditional Access, app protection
   (MAM), Autopilot profiles and enrolment restrictions are not read, so they never
   appear in a `Via` path even when they are the real reason the device behaves as it
   does.

---

### How long does an export take on a large tenant?

Export time scales with the **number of groups**, not the number of devices: workloads
are a handful of calls with `$expand=assignments`, while group membership is expanded
one call per group. Devices are a single paged call, and `-SkipDevices` removes it
entirely — worth it on a tenant with tens of thousands of managed devices when you only
need group- and policy-level answers.

Paging (`@odata.nextLink`) and 429/503 backoff with `Retry-After` are handled inside the
export, so a throttled tenant slows down rather than failing. Everything after the
export runs offline against the snapshot at local-file speed, which is why iterating on
a troubleshooting question is free after the first run.
[Performance and refresh cadence](comparison.md#performance-and-refresh-cadence) has the
suggested refresh intervals. Traversal performance on very large tenants is tracked in
[#1](https://github.com/juandresrodca/IntuneGraph/issues/1).

---

### Is `graph.json` safe to commit or send to a colleague?

Treat it as sensitive. It is a full description of your tenant's targeting: group names,
group membership, device names, policy names and how they connect. That is exactly the
map an attacker would want, and it is also the kind of thing that should not land in a
public repository by accident. The shipped `.gitignore` already excludes it.

The HTML report carries the same data inline, so the same applies to it. If you need to
hand a finding to someone, send the specific `Get-IntuneTarget` or
`Get-IntuneBlastRadius` output rather than the whole snapshot —
[workflow 4 in comparison.md](comparison.md#4-handing-the-finding-to-someone-else)
shows what that looks like.

---

### Windows PowerShell 5.1 or PowerShell 7?

Both are supported (`CompatiblePSEditions = Desktop, Core`, `PowerShellVersion = 5.1`)
and the test suite is expected to pass on both. **7+ is recommended** — it is faster on
the graph traversals and it is what the Microsoft Graph modules are developed against.

5.1 is there because it is what is already installed on a domain-joined admin
workstation, and needing a runtime install is a bad reason not to run a read-only
report. If you are choosing freshly, choose 7.

---

### Does the HTML report phone home? Can I open it on an air-gapped machine?

It makes **zero network calls**. The graph renderer is a small vanilla-JS force-directed
layout vendored inline into the file — no CDN, no web fonts, no analytics, no telemetry
of any kind. One file, open it anywhere, including on a machine with no route out.

---

### The demo tenant is called something different in the viewer than in the docs

Known and tracked in
[#12](https://github.com/juandresrodca/IntuneGraph/issues/12). The bundled demo data
identifies the tenant as **Silver Chariot Corporate**, which is what the viewer header,
the hosted demo and the MCP `intune_summary` tool all report; parts of the documentation
still call it Contoso from an earlier version of the data. Same tenant, one name pending
a cleanup.

---

### Does it work in GCC High, DoD or another national cloud?

Yes — pass the environment to `Connect-IntuneGraph`:

```powershell
Connect-IntuneGraph -Environment USGov      # or USGovDoD
```

Everything downstream of the export is offline and cloud-agnostic.

---

### Can I ask these questions from an AI assistant instead?

That is what the bundled MCP server is for. `Start-IntuneGraphMcp` exposes the same
queries — effective assignments with the `Via` path, blast radius, hygiene findings — as
tools that Claude Code or GitHub Copilot can call, against your local snapshot rather
than against Graph. Setup is in [mcp.md](mcp.md).

---

Something missing here? Open an
[issue](https://github.com/juandresrodca/IntuneGraph/issues) — a question asked twice
belongs on this page.
