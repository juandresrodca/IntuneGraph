# Discoverability

How IntuneGraph is meant to be found, and why each field says what it says.

This file exists so that the repository's topics and description are a **decision on
record** rather than something that drifts. Anyone changing them — including the daily
maintenance task — should change this file in the same commit, with the reason.

---

## The three surfaces

| Surface | What it is | Where it is set |
|---|---|---|
| **GitHub search and topic pages** | Someone types `intune assignments` into GitHub, or lands on `github.com/topics/intune`. The topics decide whether this repo is in that result set at all. | Repository settings → Topics |
| **The live demo** | `https://juandresrodca.github.io/IntuneGraph/demo/`, published by `.github/workflows/pages.yml`. Set as the repository homepage so it appears as a link in search results and in the sidebar. | Repository settings → Website |
| **PowerShell Gallery** | The install route, `Install-Module IntuneGraphKit` — see [*The Gallery name*](#the-gallery-name-intunegraphkit) for why it is not `IntuneGraph`. Gallery search reads the `Tags` in `src/IntuneGraphKit/IntuneGraphKit.psd1`, which are a separate list from GitHub topics and should stay in step with them. | `IntuneGraphKit.psd1` |

The README's first screen is the fourth surface, and the only one that converts a
visitor into a user. It leads with the demo command that needs no tenant, because the
cost of trying this tool is the thing most likely to stop someone. The MCP server comes
straight after it, ahead of the demo GIF, so the capability the `mcp` topics are there
for is visible without scrolling rather than a screen further down.

---

## The Gallery name: IntuneGraphKit

The project is IntuneGraph; the module on the Gallery is **IntuneGraphKit**. That was
not a choice between two names. `IntuneGraph` on the PowerShell Gallery was already
taken — by an unrelated module from another author that uploads, assigns and removes
Intune apps — and a Gallery package name has to equal the module name.

The difference matters in one direction. Anyone who types the project name into
`Install-Module` gets the other module: one with write cmdlets, installed on the
strength of a README whose whole pitch is *read-only*. So the README's install block
carries a one-line note naming the other package, and that note stays for as long as
the other package exists.

Everything a user does not install kept the project name: the repository, the site,
the cmdlet names, the MCP server name (`intunegraph`) and the report title.

---

## Topics

GitHub allows twenty. The rule for adding one: **a real practitioner would type it into
a search box.** Not a description of the code, not a technology the project happens to
use internally — a phrase somebody looking for this kind of tool would actually use.

### Product terms — what the tool is about

| Topic | The search it serves |
|---|---|
| `intune` | The single highest-traffic term for this repo. |
| `microsoft-intune` | The same search, written out. GitHub does not treat the two as synonyms. |
| `intune-management` | Narrows to tooling rather than to documentation and blog mirrors. |
| `endpoint-management` | The vendor-neutral phrase, and how the discipline is named in job titles. |
| `mem` | The Microsoft Endpoint Manager era shorthand. Still typed by people who learned the product under that name. |
| `mdm` | The generic category. Broad, but it is how people outside the Microsoft stack search. |
| `microsoft-graph` | The API this reads. A large, active topic page in its own right. |
| `entra-id` | Group membership and nesting is Entra, not Intune — resolving it is half of what this tool does. |

### Practitioner terms — where this community actually is

| Topic | The search it serves |
|---|---|
| `modern-workplace` | The umbrella the M365 consulting world files this work under. |
| `msendpointmgr` | The community hub the Intune audience already reads. A deliberate signal of which crowd this is for. |

### Capability terms — what it does that others do not

| Topic | The search it serves |
|---|---|
| `graph-visualization` | The differentiator against flat-list assignment tools. |
| `mcp` | The repo ships an MCP server ([`docs/mcp.md`](mcp.md)). Currently one of the fastest-moving topic pages on GitHub. |
| `model-context-protocol` | The same audience, written out. Both are in heavy use. |

### Implementation terms — only where they are how people search

| Topic | The search it serves |
|---|---|
| `powershell` | The language, and a genuine filter for this audience: an Intune admin searching for a PowerShell tool means it. |
| `powershell-module` | Narrows to installable modules rather than to loose scripts. Matches the PSGallery install route. |

Deliberately **not** used: `azure`, `windows`, `automation`, `devops`. Each is true and
each is useless — the topic pages are far too broad to send anyone here, and they dilute
the fifteen above.

---

## Status: proposed, not yet applied

The list above is the target. The topics currently set on the repository are the
earlier ten; the five capability and module terms — `entra-id`, `mcp`,
`model-context-protocol`, `microsoft-intune`, `powershell-module` — still need
applying.

They cannot be applied by the maintenance tooling. Setting topics is
`PUT /repos/{owner}/{repo}/topics`, which a fine-grained token can only call with
**Administration: write**, and the token used for routine maintenance deliberately does
not carry that permission — its whole blast radius is contents and issues. Repository
settings are a human decision, which is the correct trade.

So this is a manual step. Either paste the list into
**Settings → General → Topics**, or run it once with a token that has the scope:

```bash
gh api -X PUT repos/juandresrodca/IntuneGraph/topics \
  -f 'names[]=intune' \
  -f 'names[]=microsoft-intune' \
  -f 'names[]=intune-management' \
  -f 'names[]=endpoint-management' \
  -f 'names[]=mem' \
  -f 'names[]=mdm' \
  -f 'names[]=modern-workplace' \
  -f 'names[]=msendpointmgr' \
  -f 'names[]=microsoft-graph' \
  -f 'names[]=entra-id' \
  -f 'names[]=powershell' \
  -f 'names[]=powershell-module' \
  -f 'names[]=graph-visualization' \
  -f 'names[]=mcp' \
  -f 'names[]=model-context-protocol'
```

The call replaces the whole list, so the fifteen above are the complete intended set,
not an addition to what is there.

---

## Description

> Turn your Microsoft Intune tenant into an interactive relationship graph, and ask
> your AI why a policy applies through the bundled MCP server. See what applies to a
> device or user and why, preview a group's blast radius, find broken assignments.
> Read-only Graph, offline demo, self-contained HTML viewer. Zero write scopes.

Search results and the topic pages truncate long descriptions, so the first sentence
has to carry the whole pitch on its own. That is why the MCP server is in the first
sentence rather than the tail: it is what separates this from flat-list assignment
tools, and a truncated description should still say so. What follows it is there for the
visitor who has already clicked: the three questions the tool answers, then the two
objections an admin raises before installing anything that touches their tenant
(*does it write?* and *do I need a tenant to try it?*), answered before they are asked.

The manifest `Description` in `src/IntuneGraphKit/IntuneGraphKit.psd1` carries the same
text, so the Gallery listing and the repository make the same pitch. Change both in the
same commit.

---

## Sibling repositories

`IntuneGraph`, `Enterprise-Onboarding-Platform` and `EntraHuntKit` deliberately share
`intune`, `entra-id` and `microsoft-365` between them. The overlap is the point: they
are one body of work aimed at one audience, and somebody who arrives at any of them
through a topic page should be able to find the other two.

That is also why each README links the others, and why the profile README groups them
together rather than listing every repository flat.

---

## Reviewing this

Worth a look whenever the project gains a capability that someone would search for by
name — the MCP server is exactly that case, and is why `mcp` is on the list at all.
Otherwise, leave it alone. Topics that change every month are topics nobody trusts.
