# Claude Code skill packaging

How IntuneGraph is meant to ship as a Claude Code plugin: one install that brings the
MCP server's six read-only tools **and** a skill that tells the assistant how to use
them.

**Status: specified, not shipped.** Nothing in this repository installs as a plugin yet,
and the README says so. This file is the specification the shipping change has to meet;
the checklist at the end is its acceptance criteria.

---

## Why package it at all

The MCP server gives an assistant tools. It does not give it the method: check how old
the snapshot is before trusting it, pin down an exact name before querying, quote the
`Via` path rather than paraphrase it, run a what-if before anyone touches a group, and
never ask for tenant credentials. Today that method lives in the admin's head and in
[docs/mcp.md](mcp.md). A skill is where Claude Code loads it from.

What changes is packaging, and only packaging. The same six tools, the same launcher,
the same `graph.json` snapshot — no new capability and no new code path to a tenant.

---

## Shape: the repository root is the plugin

```text
.claude-plugin/
├── marketplace.json          # makes this repository an installable marketplace
└── plugin.json               # the manifest
skills/
└── intune-assignments/
    └── SKILL.md              # the method
```

Nothing else is added. The manifest points at the existing launcher,
`tools/mcp/mcp-server.ps1`, which imports the module from `src/IntuneGraphKit`.

The root is the plugin, rather than a subdirectory, because of how Claude Code installs
plugins. It copies a marketplace plugin into its local cache
(`~/.claude/plugins/cache`) and does not let a plugin reference files outside its own
directory. A plugin in a subdirectory could not reach the launcher or the module; it
would need a second copy of both, or a PowerShell Gallery install as a prerequisite.
With `"source": "./"` in the marketplace entry, the launcher and the module travel with
the plugin. The cost is that the cache holds the whole repository — site, tests and
fixtures included — rather than just the module.

Once shipped, installing it is two commands in Claude Code:

```text
/plugin marketplace add juandresrodca/IntuneGraph
/plugin install intunegraph@intunegraph
```

---

## The manifest — `.claude-plugin/plugin.json`

```json
{
  "name": "intunegraph",
  "displayName": "IntuneGraph",
  "description": "Ask why an Intune policy applies to a device or user and get the group path. Six read-only tools over a local graph.json snapshot; never connects to your tenant.",
  "author": { "name": "Juan Andres Rodriguez" },
  "homepage": "https://juandresrodca.github.io/IntuneGraph/",
  "repository": "https://github.com/juandresrodca/IntuneGraph",
  "license": "MIT",
  "keywords": ["intune", "microsoft-intune", "entra-id", "mcp", "powershell"],
  "userConfig": {
    "snapshot": {
      "type": "file",
      "title": "IntuneGraph snapshot",
      "description": "A graph.json written by Export-IntuneGraph. The server reads this file and nothing else.",
      "required": true
    }
  },
  "mcpServers": {
    "intunegraph": {
      "command": "pwsh",
      "args": [
        "-NoLogo", "-NoProfile", "-NonInteractive",
        "-File", "${CLAUDE_PLUGIN_ROOT}/tools/mcp/mcp-server.ps1",
        "-Path", "${user_config.snapshot}"
      ]
    }
  }
}
```

Each choice, and why:

| Choice | Reason |
|---|---|
| Snapshot path as `userConfig`, type `file` | Claude Code asks for it when the plugin is enabled and substitutes it into `args` as `${user_config.snapshot}`, so the server needs no new configuration code. It is not marked `sensitive`: the value is a path, stored in user `settings.json`. The file it points at *is* sensitive — see [SECURITY.md](../SECURITY.md). |
| `${CLAUDE_PLUGIN_ROOT}` for the launcher | Resolves to the plugin's installed copy in the cache, wherever that is. |
| `-File` with the launcher, not `-Command` | With `-Command`, the host tries to CLIXML-deserialise the redirected JSON-RPC stream. [docs/mcp.md](mcp.md) has the detail. |
| `-NoProfile` | Load-bearing, not decoration: a profile that prints anything corrupts stdout before the handshake. |
| `pwsh` only | A manifest declares one command. The plugin therefore needs PowerShell 7; Windows PowerShell 5.1 users keep the `claude mcp add` route in [docs/mcp.md](mcp.md), which works today. |
| No `version` | Setting it pins users to that string until it is bumped — a second version number to keep in step with `ModuleVersion`. Revisit at the first tagged release. |
| No `allowed-tools` in the skill | The skill does not pre-approve its own tools. Whether a tool call runs without asking stays with the user's permission settings — the right default for anything pointed at tenant data, even read-only. |

Enabled through the plugin, the tools are scoped to it — `intune_target` becomes
`mcp__plugin_intunegraph_intunegraph__intune_target`, and so on. That scoped name is
what a hook matcher has to use.

## The marketplace entry — `.claude-plugin/marketplace.json`

```json
{
  "name": "intunegraph",
  "owner": { "name": "Juan Andres Rodriguez" },
  "plugins": [
    {
      "name": "intunegraph",
      "source": "./",
      "description": "Ask why an Intune policy applies to a device or user and get the group path. Read-only, over a local snapshot."
    }
  ]
}
```

`intunegraph` is not one of the marketplace names Claude Code reserves.

---

## The six tools

Exactly the tools `Start-IntuneGraphMcp` already serves, unchanged. All six are
read-only; none of them can reach Microsoft Graph, because the server holds the session
disconnected for its whole lifetime.

| Tool | Answers | Required input | Optional input |
|---|---|---|---|
| `intune_target` | What applies to a device or user, and the `Via` path that causes each assignment | `identity` | `type`, `includeExcluded` |
| `intune_blast_radius` | What reaches a group's members — and, with a what-if, exactly what a membership change would add or remove | `group` | `whatIfAddMember`, `whatIfRemoveMember` |
| `intune_orphans` | Assignment hygiene: unassigned workloads, empty or deleted targets, include/exclude collisions, unused filters, mixed targeting | — | `check`, `severity` |
| `intune_path` | How two things are connected: why a workload reaches an entity, how a device nests into a group | `from`, `to` | — |
| `intune_node` | Name search, for pinning down the exact name to use | — | `query`, `type`, `limit` |
| `intune_summary` | Tenant, snapshot age and object counts | — | — |

---

## The skill — `skills/intune-assignments/SKILL.md`

The whole file. It is the method from *Why package it at all*, written for the
assistant rather than the admin.

````markdown
---
name: intune-assignments
description: Explain Microsoft Intune assignments from a local IntuneGraph snapshot - why a policy, app or script applies (or does not) to a device or user, with the group path through nesting, exclusions and filters; what adding or removing a group member would change; and which assignments are broken or orphaned. Use when someone asks why something applies, what touching a group would affect, or for an assignment hygiene check.
---

# Intune assignments, from the graph

You have six read-only tools over a `graph.json` snapshot of one Intune tenant. They
cannot change the tenant and do not connect to it. Answer from the tools, not from
general knowledge of how Intune assignments usually behave.

## Before the first answer

1. Call `intune_summary` and note `exportedAt`. When the answer depends on recent
   changes, say how old the snapshot is. Stale data is fixed by the user re-running
   `Export-IntuneGraph`, not by you.
2. If a name is not exact, find it with `intune_node` first; wildcards work
   (`*Finance*`). If an identity is ambiguous the tool returns the candidates - ask
   which one is meant rather than picking.

## Which tool for which question

- Why does X apply to Y? - `intune_path` from the device or user to the workload.
  Quote the `via` path exactly as returned.
- What applies to Y? - `intune_target`. Add `includeExcluded` when the question is
  about something that is missing.
- What if a member is added or removed? - `intune_blast_radius` with
  `whatIfAddMember` or `whatIfRemoveMember`. Report the gains and the losses; the
  simulation changes nothing.
- What is broken? - `intune_orphans`, High severity first.

## Reading the answers

- `Applies`: the assignment reaches the entity through the path shown.
- `AppliesPreFilter`: the assignment reaches it, but an assignment filter decides at
  check-in. IntuneGraph does not evaluate filter rules - name the filter and its mode,
  and say the outcome depends on the device.
- `Excluded`: an exclusion blocks it, and an exclusion wins over an include.

## Limits to state, not hide

- This is a snapshot, not the live tenant.
- Nothing here can make a change. If a change is wanted, give the steps for the Intune
  portal and say they have to be carried out there.
- Never ask for tenant credentials. The server holds none and needs none.
````

---

## What shipping it takes

- [ ] `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and
      `skills/intune-assignments/SKILL.md` added as specified here, and
      `claude plugin validate` passes.
- [ ] Added from a local checkout with `/plugin marketplace add ./`, the plugin asks for
      the snapshot when it is enabled and lists exactly six tools.
- [ ] Against an `Export-IntuneGraph -DemoData` snapshot, *why does Win11 Security
      Baseline apply to DEV-FIN-01?* comes back as
      `DEV-FIN-01 -> SG-Finance -> SG-AllStaff`.
- [ ] No change to `Start-IntuneGraphMcp`, the launcher or the tools.
- [ ] The README gains an install line in the same change that makes the plugin
      installable, and not before.
