# Publishing

How a version of IntuneGraph reaches the PowerShell Gallery, written down so that the
second release is done the way the first one was.

The short version: the module is published as **IntuneGraphKit** (see
[*The Gallery name*](discoverability.md#the-gallery-name-intunegraphkit) for why it is not
`IntuneGraph`), a release is a pushed tag called `v<ModuleVersion>`, and CI does the
publishing. Nobody runs `Publish-PSResource` from a workstation.

It is one-way in the way that matters. A Gallery version can be unlisted, but its number
can never be reused, so everything that can be checked is checked before the tag goes up.
That is what most of this page is.

---

## Deciding the version

Versions follow [SemVer](https://semver.org/). Until 1.0, the minor number moves for a new
capability or a breaking change, and the patch number is for a fix that changes no
behaviour. `0.2.0` added the MCP server; `0.3.0` renames the module, which is breaking,
so [CHANGELOG.md](../CHANGELOG.md) says so under *Changed*, marked **BREAKING**, with the
one-line migration.

If a change would make someone edit a script they already have, it is breaking, and the
changelog entry has to say what to edit.

---

## Where the version lives

Six places carry it. Only the first is checked by CI.

| Where | What it controls | Checked |
|---|---|---|
| `ModuleVersion` in [`src/IntuneGraphKit/IntuneGraphKit.psd1`](../src/IntuneGraphKit/IntuneGraphKit.psd1) | The Gallery version, and what `Install-Module` resolves | Yes — the tag must equal `v` plus this |
| [`CHANGELOG.md`](../CHANGELOG.md) | The `## [x.y.z] - date` heading, a fresh empty `## [Unreleased]` above it, and a compare link at the foot of the file | No |
| [`SECURITY.md`](../SECURITY.md), *Supported versions* | Which versions receive fixes | No |
| `$script:IgMcpServerVersion` in `src/IntuneGraphKit/Private/Mcp.ps1` | The version the MCP server reports in `serverInfo` | No |
| `toolVersion` in `src/IntuneGraphKit/Public/Export-IntuneGraph.ps1` | Written into `metadata` in every exported `graph.json` | No |
| The git tag, `v<ModuleVersion>` | Triggers the release | It is the check |

The two code rows are hardcoded, not read from the manifest, and no test asserts them, so
a release that forgets them is green in CI and reports the old version about itself.
[#13](https://github.com/juandresrodca/IntuneGraph/issues/13) removes the problem; until
it lands, bump both by hand and treat the grep in *Before you tag* as part of the release.

Two places that look like version locations are not. `ReleaseNotes` in the manifest points
at `CHANGELOG.md` on `main`, so it never needs editing per release. The README's Gallery
badge reads the version from the Gallery.

---

## Manifest fields

The manifest is the Gallery listing, and a published version's listing cannot be
corrected in place — only a new version fixes it. So the fields get checked before a tag,
not after.

| Field | Rule |
|---|---|
| `ModuleVersion` | The one that changes every release. |
| `GUID` | Never. It is the module's identity on the Gallery, and it was set once, before the first publish. |
| `RootModule` and the folder | The folder, the manifest and the root module all carry the name `IntuneGraphKit`, and that name is the Gallery package name. Renaming any one of them breaks the publish. |
| `Description` | The same text as the repository description, the README's opening paragraph and the awesome-entra entry. Change the pitch in all four in one commit — see [*One description, not four*](discoverability.md#one-description-not-four). |
| `Tags`, `CompatiblePSEditions` | `PSEdition_Desktop` and `PSEdition_Core` stay in `Tags`, alongside `CompatiblePSEditions = Desktop, Core`: together they drive the Gallery's edition filter. Keep `Tags` in step with the GitHub topics, which are a separate list. |
| `ProjectUri`, `LicenseUri`, `IconUri`, `ReleaseNotes` | All `https://`. `IconUri` points at `docs/img/icon.png` on `main`, so that file has to stay where it is. |
| `FunctionsToExport` | An explicit list, never `*`. A new cmdlet has to be added here and to the exports test in the suite, which pins the list. |
| `PowerShellVersion` | `5.1`. It is the floor the README promises, and CI tests it. |

The *Module* tests in [`tests/IntuneGraph.Tests.ps1`](../tests/IntuneGraph.Tests.ps1)
cover the exports, the editions, the tags and the four URIs. They do not cover `GUID` or
`Description`, which is why those two are on a list a person reads.

Nothing in the pipeline handles a `Prerelease` label: the tag check compares only
`ModuleVersion`. Do not add one without extending the workflow first.

---

## What has to pass

```powershell
.\build.ps1          # Analyze, then Test
```

Those are the two steps CI runs, in that order.

**PSScriptAnalyzer.** It runs over `src/IntuneGraphKit` with the settings in
[`PSScriptAnalyzerSettings.psd1`](../PSScriptAnalyzerSettings.psd1). Errors and warnings
are both reported, **errors fail the build and warnings do not**. Three rules are
excluded, each with its reason written beside it; a fourth exclusion needs an issue
first, as [CONTRIBUTING.md](../CONTRIBUTING.md#psscriptanalyzer) says.

One trap: on a machine without PSScriptAnalyzer, `build.ps1` prints a warning and skips the
step instead of failing. A skipped gate looks like a passed one. Look for
`PSScriptAnalyzer: clean.` in the output rather than for the absence of red.

**Pester.** The whole suite runs against the Contoso fixtures: no tenant, no network. A
failing test fails the CI step, because `Invoke-Pester` leaves its failure count in
`$LASTEXITCODE` and the Actions step wrapper exits with it. `build.ps1` does not exit
with that number itself: run from a prompt it finishes with status 0 even when tests
failed (checked on Windows PowerShell 5.1 with Pester 5.7.1). Read the `Failed:` line of
the summary, and do not wire the script's exit status into a hook or another script.

**The matrix.** CI runs both steps on PowerShell 7 and Windows PowerShell 5.1 on
`windows-latest`, and on PowerShell 7 on `ubuntu-latest`. You can only run the one you
have installed; CI covers the rest, and the release re-runs all three on the tagged commit
before it publishes anything.

---

## Releasing

### 1. Prepare the release in a pull request

Releases are cut from `main`, so the preparation is an ordinary pull request:

1. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [x.y.z] - YYYY-MM-DD`, add a new
   empty `## [Unreleased]` above it, and update the links at the foot. `Unreleased`
   compares `vx.y.z...main` from now on, and the new version compares with the tag before
   it. The first one, `0.3.0`, has no earlier tag to compare with, so it links to its
   release page instead.
2. Set `ModuleVersion` to `x.y.z`.
3. Update the two hardcoded strings in `Mcp.ps1` and `Export-IntuneGraph.ps1`, until
   [#13](https://github.com/juandresrodca/IntuneGraph/issues/13) removes them.
4. Update the *Supported versions* table in `SECURITY.md`, following the pattern already
   there: the new minor is current, and the previous one drops to security fixes only.
5. Check the manifest fields above, especially `Description` if the pitch has moved.

### 2. Before you tag

With the pull request merged and `main` checked out:

```powershell
.\build.ps1                                                  # the same gate CI runs
Test-ModuleManifest .\src\IntuneGraphKit\IntuneGraphKit.psd1 # the manifest parses; prints name, version, exports
"v$((Import-PowerShellDataFile .\src\IntuneGraphKit\IntuneGraphKit.psd1).ModuleVersion)"   # the tag you are about to push
git grep -nF "0.2.0" -- src                                  # the previous version: should print nothing
```

Replace `0.2.0` with the version you are leaving. If the grep finds a line, that is a
string the release would have shipped stale.

### 3. Tag the merge commit and push the tag

```powershell
git switch main
git pull --ff-only
git log -1 --oneline        # this must be the release pull request's merge
git tag v0.3.0
git push origin v0.3.0
```

Pushing the tag is the release. Use a lightweight tag, as above: the workflow reads only
the name.

### 4. Watch the Release workflow

[`release.yml`](../.github/workflows/release.yml) has two jobs and runs them in order:

1. **`ci`** — the full matrix again, on the tagged commit, through the same
   [`ci.yml`](../.github/workflows/ci.yml) a pull request runs.
2. **`publish`** — only if `ci` passed. It first checks that the tag equals
   `v<ModuleVersion>` and stops with *Nothing was published* if not, then runs
   `./build.ps1 -Task Publish`.

That task calls `Publish-PSResource -Path src/IntuneGraphKit -Repository PSGallery` with
the key taken from `$env:PSGALLERY_API_KEY`. It is `Publish-PSResource`, not
`Publish-Module`: it is the cmdlet of the maintained PSResourceGet module, which
`build.ps1` notes ships with PowerShell 7.4 and later, so the workflow installs nothing.
It is also why the publish job needs PowerShell 7 even though the module supports 5.1 —
the module's floor and the pipeline's are not the same thing.

### 5. Confirm it from the outside

The Gallery validates a new version before it lists it, so `Find-Module` can lag the
workflow by several minutes. Once it appears:

```powershell
Find-Module IntuneGraphKit -RequiredVersion 0.3.0
```

Then install it into a clean process on **both** editions and run the demo, which is the
README's own first command and the thing a visitor does first:

```powershell
powershell.exe -NoProfile -Command "Install-Module IntuneGraphKit -RequiredVersion 0.3.0 -Scope CurrentUser -Force; Import-Module IntuneGraphKit; Export-IntuneGraph -DemoData -PassThru | Show-IntuneGraph -Open"
pwsh -NoProfile -Command "Install-Module IntuneGraphKit -RequiredVersion 0.3.0 -Scope CurrentUser -Force; Import-Module IntuneGraphKit; Export-IntuneGraph -DemoData -PassThru | Show-IntuneGraph -Open"
```

Open the package page and check the icon, the licence and project links, the
release-notes link, and that the module appears under both PowerShell edition filters.

### 6. Create the GitHub release

The workflow publishes to the Gallery and does nothing else — it has `contents: read`
only — so the GitHub release is a human step. Do it after the Gallery check, so that the
release marked *Latest* never points at a version that failed to publish.

```powershell
gh release create v0.3.0 --verify-tag --title "IntuneGraph 0.3.0" --notes-file release-notes.md
```

Take the notes from the matching `CHANGELOG.md` section rather than regenerating them from
commit subjects: the changelog is where the breaking changes are called out in the words
a reader needs. `--verify-tag` makes the command fail instead of creating a tag you did
not push.

---

## The API key

The Gallery key lives in exactly one place: the **`PSGALLERY_API_KEY` repository secret**.
It is never in the repository, never a parameter default, and never typed on a command
line. `build.ps1 -Task Publish` reads it from the environment, refuses to run without it,
and deliberately has no parameter for it. The workflow hands it over through `env`, not
by interpolating it into a script.

To create it:

1. On the PowerShell Gallery, **Account → API Keys → Create**.
2. Scope it to *Push new packages and package versions*, and to the one package with the
   glob pattern `IntuneGraphKit`. The scope has to cover new packages because the first
   publish creates the listing. Nothing about this key needs to be able to touch any other
   package.
3. Give it an expiry, and put the date somewhere you will see it.
4. Store it as the secret without it passing through shell history:

```powershell
gh secret set PSGALLERY_API_KEY
```

That prompts for the value instead of taking it as an argument.

An expired key fails at the `publish` job, after CI has already passed, so check the
expiry before you push a tag. If the key is ever exposed — in a log, an issue, a pasted
command — revoke it on the Gallery first, then issue a new one and replace the secret.

---

## When it goes wrong

| What you see | What it means | What to do |
|---|---|---|
| The `ci` job is red | Nothing was published; the version number is unspent. | Fix it on `main` through a pull request. Delete the tag (`git push --delete origin v0.3.0`, then `git tag -d v0.3.0`) and tag the new merge commit. |
| *Tag … does not match ModuleVersion* | Nothing was published. The manifest and the tag disagree. | The same: fix whichever is wrong, delete the tag, tag again. |
| *PSGALLERY_API_KEY is not set* | The secret is missing or misnamed. Nothing was published. | Add the secret, then re-run the failed job from the Actions tab. The tag and CI result stand, so there is no need to re-tag. |
| `publish` fails with the Gallery refusing the key | Expired, wrong scope, or a glob that does not match `IntuneGraphKit`. | Check the key on the Gallery, replace the secret, re-run the failed job. |
| `publish` fails and you cannot tell why | The version may or may not have gone up. | **Look at the Gallery before doing anything else.** If the version is listed, its number is spent: fix forward with the next patch version and never re-tag. If it is not listed, treat it as a refused publish above. |
| A published version is wrong | The listing cannot be corrected in place. | Unlist it from the package's management page on the Gallery, fix the cause, and ship the next version. The number cannot be reused. |

Deleting and re-pushing a tag is safe only while nothing was published under it. Once the
Gallery lists the version, the tag stays where it is.

---

## The first release

Status as of 4 October 2026: **nothing has been published**, and the first tag is also the
first time the `publish` job runs.

- `ModuleVersion` is still `0.2.0`, there are no git tags, and there are no GitHub
  releases. `0.1.0` and `0.2.0` predate the pipeline, which is why
  [CHANGELOG.md](../CHANGELOG.md) says they cannot be installed with
  `-RequiredVersion`.
- The repository has no Actions secrets, so `PSGALLERY_API_KEY` does not exist yet.
- The changelog for `0.3.0` is written and sits under *Unreleased*.

What is left is the human part: create the key, set the secret, open the release pull
request described under *Releasing*, and push `v0.3.0`.

Read *When it goes wrong* before the tag goes up, not after. The `publish` job has not
been exercised end to end: that `Publish-PSResource` is available to the PowerShell on the
runner rests on the note in `build.ps1`, not on a run. If the first attempt fails at that
step and nothing is listed, the version is unspent and the fix is a pull request, not a
new number.

Once `0.3.0` is on the Gallery and the checks in step 5 pass, delete this section.
