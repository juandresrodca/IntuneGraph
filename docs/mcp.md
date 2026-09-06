# MCP server mode

`Start-IntuneGraphMcp` runs IntuneGraph as an [MCP](https://modelcontextprotocol.io)
server over stdio, so an AI assistant can query your tenant's relationship graph
directly. The interesting part is not that it can list policies — it's that it can
answer **why** one applies, with the exact group path through nesting.

```
> why does Win11 Security Baseline apply to DEV-FIN-01?

  [intune_target]
  Win11 Security Baseline  ConfigPolicy  Applies
  via  DEV-FIN-01 -> SG-Finance -> SG-AllStaff
```

## Why this is safe to point an AI at

The server reads a **local `graph.json` snapshot** and nothing else. It never
connects to Microsoft Graph, never exports, and never writes a file — so the
assistant never gets your tenant credentials, and there is no code path from a tool
call to your live tenant.

That guarantee is enforced three ways:

1. The tool handlers only call the pure query layer. Nothing in the MCP code path
   references the Graph transport at all.
2. The server forces the module session to `Mode='None'` for its whole lifetime, so
   any Graph call would hit `Assert-IgConnection` and throw.
3. The module has no write path in the first place: the single function that talks
   to Graph hardcodes `GET`, and there is no `$Method` parameter anywhere. See
   [permissions.md](permissions.md).

You control how fresh the data is, because you decide when to run
`Export-IntuneGraph`. The server notices when `graph.json` changes on disk and
reloads it, so you can refresh mid-conversation without restarting the client.

## Setup

First produce a snapshot:

```powershell
Connect-IntuneGraph
Export-IntuneGraph -OutputPath D:\snapshots\contoso\graph.json
```

Or skip the tenant entirely and use the bundled demo data:

```powershell
Export-IntuneGraph -DemoData -OutputPath D:\snapshots\demo\graph.json
```

### Claude Code

```bash
claude mcp add intunegraph -- pwsh -NoLogo -NoProfile -NonInteractive \
  -File "D:/path/to/IntuneGraph/tools/mcp/mcp-server.ps1" \
  -Path "D:/snapshots/contoso/graph.json"
```

On Windows PowerShell 5.1:

```bash
claude mcp add intunegraph -- powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ^
  -File "D:\path\to\IntuneGraph\tools\mcp\mcp-server.ps1" ^
  -Path "D:\snapshots\contoso\graph.json"
```

### `.mcp.json`

```json
{
  "mcpServers": {
    "intunegraph": {
      "command": "pwsh",
      "args": [
        "-NoLogo", "-NoProfile", "-NonInteractive",
        "-File", "D:/path/to/IntuneGraph/tools/mcp/mcp-server.ps1",
        "-Path", "D:/snapshots/contoso/graph.json"
      ]
    }
  }
}
```

### VS Code (GitHub Copilot) — `.vscode/mcp.json`

```json
{
  "servers": {
    "intunegraph": {
      "type": "stdio",
      "command": "pwsh",
      "args": [
        "-NoLogo", "-NoProfile", "-NonInteractive",
        "-File", "${workspaceFolder}/tools/mcp/mcp-server.ps1",
        "-Path", "${workspaceFolder}/snapshots/graph.json"
      ]
    }
  }
}
```

### If the module is installed from PSGallery

You can skip the launcher script and start the server from the installed module:

```json
{
  "command": "pwsh",
  "args": ["-NoLogo", "-NoProfile", "-NonInteractive", "-InputFormat", "Text",
           "-Command", "Import-Module IntuneGraph; Start-IntuneGraphMcp -Path 'D:/snapshots/contoso/graph.json'"]
}
```

`-InputFormat Text` matters here: with `-Command`, the host would otherwise try to
CLIXML-deserialize the redirected JSON-RPC stream. The `-File` launcher above avoids
the question entirely, which is why it's the recommended shape.

## Tools

| Tool | Answers |
|---|---|
| `intune_target` | What applies to this device or user, and the `Via` path that causes each assignment. Set `includeExcluded` to also see what's blocked and why. |
| `intune_blast_radius` | What reaches a group's members, and — with `whatIfAddMember` / `whatIfRemoveMember` — exactly what a membership change would add or remove. |
| `intune_orphans` | Assignment hygiene: unassigned workloads, empty or deleted target groups, include/exclude collisions, unused filters, mixed device/user targeting. |
| `intune_path` | How two things are connected: why a workload reaches an entity, how a device nests into a group, what two entities share. |
| `intune_node` | Name search across devices, users, groups, policies, apps, scripts and filters — for pinning down the exact name to use. |
| `intune_summary` | Tenant, snapshot age and object counts. Worth checking before treating the data as current. |

All six are read-only. A tool that fails — an unknown device name, an ambiguous
identity — returns an error *result* rather than a protocol error, so the assistant
reads the message and retries instead of dropping the turn.

## Protocol notes

The server is dual-era. It answers the legacy `initialize` handshake (protocol
versions `2024-11-05` through `2025-11-25`, defaulting to `2025-06-18`) and also
implements `server/discover`, so a client speaking the newer stateless revision can
probe it and negotiate instead of hanging on the stdio pipe.

Transport is newline-delimited JSON-RPC 2.0: one compact JSON object per line, LF
endings, UTF-8 without a BOM. stdout carries the protocol and nothing else; every
diagnostic goes to stderr, which MCP clients show in their logs.

## Troubleshooting

**The client says the server failed to start, or "unexpected token".**
Almost always a PowerShell profile printing something. stdout is the protocol
stream, so a single `Write-Host` in your profile corrupts the handshake. Make sure
`-NoProfile` is in the args — it is load-bearing, not decoration.

**"No graph available."**
The `-Path` didn't resolve. Use an absolute path: the client launches the server
with an arbitrary working directory. The server fails fast at startup rather than
erroring on every call, so check the client's log pane for the reason.

**Nothing happens when I run it in a terminal.**
Correct — it's waiting on stdin for JSON-RPC. It's meant to be launched by a client.
To check it by hand, pipe a request in:

```powershell
'{"jsonrpc":"2.0","id":1,"method":"tools/list"}' |
  powershell.exe -NoLogo -NoProfile -NonInteractive -File .\tools\mcp\mcp-server.ps1 -Path .\graph.json
```

**I want to see what the client is asking for.**
Add `-LogRequests` to the launcher args. Traces go to stderr, so they never disturb
the protocol stream.

**The assistant quotes stale data.**
The snapshot is a point-in-time export. Re-run `Export-IntuneGraph` over the same
path — the server picks up the change on the next tool call — and ask it to check
`intune_summary` for the snapshot age.
