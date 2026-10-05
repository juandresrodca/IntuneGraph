# Troubleshooting

Every failure mode of this module that has needed explaining, in the order you meet
them: installing, connecting, exporting, querying, viewing the report, and running the
MCP server. Each entry is **symptom → cause → fix**.

Short questions — which package to install, why an exclusion wins, what
`AppliesPreFilter` means — are answered in [FAQ.md](FAQ.md). This page is for the cases
where something is broken rather than merely surprising.

---

## Start here

Three commands separate "the module is broken" from "your tenant or your permissions
are not what you think they are":

```powershell
Export-IntuneGraph -DemoData -PassThru | Show-IntuneGraph -Open   # 1. does anything work?
Get-MgContext | Select-Object TenantId, Account, Scopes           # 2. who am I, and with what?
Get-IntuneGraphNode -Name '*'                                     # 3. what is actually in the snapshot?
```

If (1) opens a populated graph, the module, the renderer and your PowerShell are all
fine — demo mode makes zero network calls and touches no tenant, so a working demo and a
failing live export narrows the problem to auth, permissions or the tenant itself.

---

## Installing and importing

### `Install-Module IntuneGraphKit` cannot find the package

**Cause.** It is not published yet. The README shows the install command the module is
heading towards, and the PowerShell Gallery badge resolves to nothing until the first
release is cut — tracked in
[#5](https://github.com/juandresrodca/IntuneGraph/issues/5). Publishing is a deliberate
manual step; the procedure is in [publishing.md](publishing.md).

**Fix.** Run it from source:

```powershell
git clone https://github.com/juandresrodca/IntuneGraph.git
Import-Module .\IntuneGraph\src\IntuneGraphKit\IntuneGraphKit.psd1 -Force
```

Everything in this repository works from a clone, including demo mode, the tests and the
MCP server.

### `Install-Module` fails on Windows PowerShell 5.1 with a TLS or "no match was found" error

**Cause.** 5.1 defaults to TLS 1.0/1.1 for `Invoke-WebRequest`, and the Gallery has
required TLS 1.2 for years. The error surfaces as a connection failure or an empty
repository rather than anything mentioning TLS.

**Fix.** In that session, before installing anything:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### `Import-Module` succeeds but the cmdlets are not there

**Cause.** Two copies of the module are loaded, or the manifest was imported by folder
name rather than by path and resolved to a different version.

**Fix.** `Get-Module IntuneGraphKit -All | Select-Object Name, Version, Path` shows what
is loaded and from where. `Remove-Module IntuneGraphKit` then re-import the `.psd1` by
its full path.

---

## Connecting and consent

### `Microsoft.Graph.Authentication is not installed`

**Cause.** `Connect-IntuneGraph` loads that module lazily and refuses to continue
without it. It is not a hard `RequiredModules` dependency on purpose, so demo mode,
fixture mode and the whole test suite run with nothing installed.

**Fix.**

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

Only `Microsoft.Graph.Authentication` is needed — not the full `Microsoft.Graph` meta
module, which is large and brings nothing this module uses.

### Consent is refused, or the export fails partway with 403

**Cause.** This usually shows up *after* `Connect-IntuneGraph` has apparently
succeeded, because consent is per scope. A token carrying three of the four scopes
connects cleanly and then fails on the first read that needs the fourth. The mapping is
one-to-one, so the failing endpoint names the missing scope:

| The export stalls at | Missing scope |
|---|---|
| Configuration policies, legacy device configurations, compliance policies, scripts, remediations, filters | `DeviceManagementConfiguration.Read.All` |
| Apps | `DeviceManagementApps.Read.All` |
| Managed devices | `DeviceManagementManagedDevices.Read.All` |
| Groups, group members | `Group.Read.All` |

**Fix.** Compare what you were granted against what was asked for:

```powershell
$want = 'DeviceManagementConfiguration.Read.All','DeviceManagementApps.Read.All',
        'DeviceManagementManagedDevices.Read.All','Group.Read.All'
$want | Where-Object { (Get-MgContext).Scopes -notcontains $_ }
```

Anything that prints has not been consented. If your tenant restricts user consent — the
common case — a Global Administrator, Privileged Role Administrator or Cloud Application
Administrator has to consent for the organisation once; after that every admin reusing
the Microsoft Graph PowerShell application inherits it. All four are read-only and the
module contains no write code path, which is the argument to put in the request; see
[permissions.md](permissions.md).

Partway failures are not resumable. The export has no checkpointing, so fix the consent
and re-run from the start.

### `Granted scopes exceed IntuneGraph's minimum: …`

**Cause.** Not an error — a deliberate warning. Consent for the Microsoft Graph
PowerShell application is cumulative per tenant and per user, so a scope anyone granted
it previously (often `Directory.Read.All`) is still in your token even though this
module never asks for it and cannot use it.

**Fix.** Nothing is required; the module still only issues `GET`. To get back to a
minimal token, remove the Microsoft Graph PowerShell app's consented permissions under
**Entra ID → Enterprise applications**, or connect with a dedicated app registration
holding only the four scopes:

```powershell
Connect-IntuneGraph -TenantId <tenant> -ClientId <appId> -CertificateThumbprint <thumb>
```

### The browser never opens, or auth hangs on a server with no desktop

**Cause.** Interactive consent needs a browser on the machine running PowerShell.

**Fix.** `Connect-IntuneGraph -UseDeviceCode` for a remote session, or certificate-based
app-only auth for anything unattended. A client secret in a scheduled task is a
credential in plain text holding read access to your whole directory's group membership
— use a certificate.

---

## Exporting

### The export appears to hang, usually on "Group members"

**Cause.** Throttling, and it is working as intended. Group membership is one Graph call
per group, so export time scales with the **number of groups**, not devices. On a
throttled tenant `Invoke-IgLiveRequest` retries a 429 or 503 up to five times, sleeping
for the `Retry-After` value the service returns (10 seconds when it sends none) plus up
to 2 seconds of jitter. A tenant with 2,000 groups being throttled hard can therefore
sit on one `Write-Progress` line for a long time while making steady progress.

**Fix.** Let it run, and shorten the work:

- `-SkipDevices` drops the managed-devices call entirely. Worth it on a tenant with tens
  of thousands of devices when you only need group- and policy-level answers.
- Export off-peak; Graph throttles per app per tenant, so another tool hammering
  Microsoft Graph PowerShell at the same time shares your budget.
- Run it once and query the snapshot repeatedly. Everything downstream of the export is
  offline, so iterating on a question costs nothing after the first run.

After five retries the error is re-thrown rather than swallowed, so a genuinely blocked
export fails loudly rather than returning a partial graph.

### The export finishes with `Nodes: 0   Edges: 0`

**Cause.** Four candidates, in order of likelihood:

1. **The wrong tenant.** `(Get-MgContext).TenantId` against the tenant you meant.
2. **Scope-tagged RBAC.** An Intune role scoped to a subset of objects returns only
   those objects, and an account with no assigned scope tags can legitimately read
   nothing. The calls succeed, return empty collections, and the graph is empty.
3. **An empty fixture root.** With `-FromFixtures`, every fixture file present but
   containing `{"value":[]}` produces exactly this. A *missing* file is a hard error
   instead — see below.
4. **The tenant really is empty.** A fresh lab tenant with no policies and no groups
   exports an empty graph correctly.

**Fix.** Prove the pipeline with `Export-IntuneGraph -DemoData` — if the demo graph has
nodes, the module is fine and the problem is tenant-side. Then compare the Intune admin
centre's own counts against the summary the export prints.

### `Fixture not found: expected file at '…'`

**Cause.** Fixture mode maps each Graph path onto a file under the fixture root, and a
missing file is deliberately fatal. Returning an empty collection instead would hide
the difference between "this tenant has no remediation scripts" and "this fixture set
does not cover remediation scripts", which is exactly the bug class fixtures exist to
catch.

**Fix.** Create the file with a `{"value":[]}` envelope if the emptiness is the point.
[fixtures.md](fixtures.md) documents the directory layout and the API version each
collection lives on — Settings Catalog policies, scripts, remediations and assignment
filters are on `beta`, the rest on `v1.0`, and the path must match.

### The output landed somewhere I did not expect

**Cause.** Without `-OutputPath`, the export names its own directory from the tenant
name with every non-word character stripped, plus a timestamp:
`.\IntuneGraph-<TenantName>-<yyyyMMdd-HHmm>\graph.json`, relative to the current
directory. For the bundled demo data that is `IntuneGraph-SilverChariotCorporate-…`,
which is also why the viewer header does not say Contoso
([#12](https://github.com/juandresrodca/IntuneGraph/issues/12)).

**Fix.** Pass `-OutputPath` when you care. `-Html` writes the report beside it with the
same base name.

---

## Querying the snapshot

### `No graph available. Run Export-IntuneGraph or Import-IntuneGraph first…`

**Cause.** The query cmdlets resolve their graph in a fixed order: an explicit `-Graph`
object, then `-Path` to a `graph.json`, then the last graph exported or imported *in
this session*. A new shell has no session graph.

**Fix.** `Import-IntuneGraph .\graph.json`, or pass `-Path` on each call.

### `Identity 'X' is ambiguous. Candidates: …`

**Cause.** Two objects share a display name — most often a device and the user it is
named after, or a group and a policy. Graph does not enforce uniqueness on
`displayName`, so neither can the resolver.

**Fix.** The error lists every candidate with its type and node id. Re-run with the node
id, or narrow by type where the cmdlet accepts it. `Get-IntuneGraphNode` is the quickest
way to see the exact names in the snapshot.

### `Get-IntuneTarget` returns nothing for a device that definitely has policies

Covered in the FAQ, which walks the four causes in order of likelihood:
[`Get-IntuneTarget` returns nothing for a device I know has policies](FAQ.md#get-intunetarget-returns-nothing-for-a-device-i-know-has-policies).

### `The -Graph argument is not an IntuneGraph graph object`

**Cause.** Something other than a graph reached `-Graph` — commonly the `FileInfo` that
`Show-IntuneGraph` returns, piped onward.

**Fix.** Pipe from `Export-IntuneGraph -PassThru` or `Import-IntuneGraph`.
`Show-IntuneGraph` is a sink: it returns the file it wrote, so it belongs at the end of
a pipeline.

---

## The HTML report

### The page opens but nothing is drawn

**Cause and fix, in the order worth checking:**

1. **The graph is empty.** A report built from a zero-node graph renders its chrome and
   an empty canvas. Check the counts the export printed.
2. **Windows has blocked the script.** A file copied from a share or downloaded carries
   a mark-of-the-web and the browser refuses its inline script, sometimes silently.
   `Unblock-File .\IntuneGraph.html` clears it.
3. **The data was never injected.** The renderer is a template with three placeholders
   filled at write time. If the token survived, the file is not a finished report:

   ```powershell
   Select-String -Path .\IntuneGraph.html -SimpleMatch '__IG_DATA__'
   ```

   Any match means a partial or mixed-version install — re-import the manifest by path
   and regenerate.
4. **The file was re-saved by an editor.** `graph.json` and the report are written as
   UTF-8 **without** a BOM on purpose. Re-saving either with `Set-Content -Encoding UTF8`
   on Windows PowerShell 5.1 adds a BOM, and as UTF-16 with `Out-File` by default; both
   break the parse. Write through `[System.IO.File]::WriteAllText` with
   `UTF8Encoding($false)` if you must post-process.
5. **A viewer that strips inline script.** The report is one self-contained file with the
   renderer, the styles and the data inlined — a document preview pane, a wiki embed or a
   mail client will show a blank frame. Open it from disk in a real browser.

The browser console names the real cause in cases 2–4 and is worth opening before
anything else.

### `-Focus` shows almost nothing

**Cause.** `-Focus` renders only the neighbourhood around a node, `-Depth 2` by default,
with edges treated as undirected. A leaf node — an unassigned policy, a device in no
groups — has a correspondingly tiny neighbourhood.

**Fix.** Raise `-Depth`, or drop `-Focus` to see the whole graph.

### The report is large

**Cause.** The data travels inside the file, so size tracks node and edge count. Tens of
megabytes on a large tenant is normal.

**Fix.** Nothing to fix, but treat the file the way you treat `graph.json` — it carries
the same tenant description inline, and is the same thing to leak.

---

## Windows PowerShell 5.1 versus PowerShell 7

Both are supported — `PowerShellVersion = '5.1'`, `CompatiblePSEditions = Desktop, Core`
— and the test suite is expected to pass on both. 5.1 is there because it is what is
already on a domain-joined admin workstation, and needing a runtime install is a bad
reason not to run a read-only report. Choosing freshly, choose 7.

What actually differs:

| | Windows PowerShell 5.1 | PowerShell 7+ |
|---|---|---|
| Gallery install | needs TLS 1.2 set by hand (above) | works |
| Graph traversal | noticeably slower on large graphs | recommended |
| `Set-Content -Encoding UTF8` | writes a BOM — do not use it on `graph.json` | BOM-free |
| `$IsWindows` | does not exist; `Show-IntuneGraph -Open` falls back to `$env:OS` | defined |
| Microsoft Graph SDK | supported, not the primary target | what it is developed against |

If you are editing the module rather than using it, one more: 5.1 throws *"Argument
types do not match"* for `@()` applied directly to a `List[object]`. Every
list-to-array conversion in the module goes through `ConvertTo-IgArray` for that reason,
and a new one that does not will pass on 7 and fail on 5.1. See
[CONTRIBUTING.md](../CONTRIBUTING.md).

---

## MCP server

The three failures that account for most of them — a profile printing to stdout, an
unresolved `-Path`, and the server apparently doing nothing in a terminal — are in
[mcp.md § Troubleshooting](mcp.md#troubleshooting), along with how to drive the handshake
by hand. Two more that are not:

### The client reports an unsupported protocol version

**Cause.** The server is dual-era. It answers the legacy `initialize` handshake for
protocol versions `2024-11-05` through `2025-11-25`, defaulting to `2025-06-18`, and
implements `server/discover` for the newer stateless revision (`2026-07-28`). A client
demanding something outside both sets gets a negotiation failure, which most clients
report as a generic start-up error.

**Fix.** The client's log pane shows the version it asked for. `-LogRequests` traces each
dispatched method to stderr, where clients surface it, so you can see which handshake was
attempted.

### The server starts by hand but not from the client

**Cause.** MCP clients spawn the server with a minimal environment, so `pwsh` may not be
on the `PATH` the client uses even though it is on yours. The launcher must also be
invoked with `-File`: with `-Command`, the host tries to CLIXML-deserialise the
redirected JSON-RPC stream and the handshake never completes.

**Fix.** Use an absolute interpreter path and keep the argument shape:

```json
{ "command": "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
  "args": ["-NoLogo", "-NoProfile", "-NonInteractive",
           "-File", "C:\\src\\IntuneGraph\\tools\\mcp\\mcp-server.ps1",
           "-Path", "C:\\src\\IntuneGraph\\graph.json"] }
```

`-NoProfile` is load-bearing, not decoration, and both paths must be absolute: the client
chooses the working directory.

---

## Known issues worth knowing about

| | Tracking |
|---|---|
| `Install-Module IntuneGraphKit` does not work yet — the package is unpublished | [#5](https://github.com/juandresrodca/IntuneGraph/issues/5) |
| The demo tenant is Contoso in parts of the docs and Silver Chariot Corporate in the data | [#12](https://github.com/juandresrodca/IntuneGraph/issues/12) |
| The MCP server version and `graph.json` `toolVersion` are hard-coded rather than read from the manifest | [#13](https://github.com/juandresrodca/IntuneGraph/issues/13) |
| Traversal performance on tenants with 1,000+ devices and users | [#1](https://github.com/juandresrodca/IntuneGraph/issues/1) |

## Still stuck

Open an [issue](https://github.com/juandresrodca/IntuneGraph/issues) with:

- `$PSVersionTable.PSVersion` and `(Get-Module IntuneGraphKit).Version`
- the command you ran and the full error, from `-Verbose` where the cmdlet supports it
- the `metadata` block from the top of `graph.json` — **with `tenantId` and `tenantName`
  removed**, which leaves the counts, the schema version and the export timestamp

Do not attach `graph.json` or an HTML report. Both describe your tenant's targeting and
membership in full; a redacted `metadata` block plus the error is enough to reproduce
most things, and a fixture can stand in for the rest.
