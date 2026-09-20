## What this changes, and why

<!-- One logical change. Say why it matters rather than restating the diff. -->

Closes #

## How it was verified

<!-- The commands you ran and what they printed. `.\build.ps1` runs Analyze then Test,
     which is exactly what CI runs on 5.1 and 7. -->

```powershell
.\build.ps1
```

## Checklist

- [ ] `.\build.ps1` is green locally (PSScriptAnalyzer errors fail the build; warnings do not)
- [ ] Tests cover the change, and any new fixture scenario has the assertion that catches it
- [ ] Fixtures, if touched, were regenerated with `.\build.ps1 -Task Fixtures` and committed
- [ ] `CHANGELOG.md` has an *Unreleased* entry for anything a user would notice
- [ ] Documentation updated in this pull request if behaviour changed
- [ ] Commit subjects are conventional commits in the imperative, under about 72 characters

## Guarantees this change does not break

These are the promises the README and SECURITY.md make to people running this against a
live tenant — tick each one, or say in the description why it does not apply.

- [ ] No write path to Graph: `Invoke-IgRequest` still hardcodes `GET`
- [ ] No new Graph scopes beyond the four read-only ones in `docs/permissions.md`
- [ ] No network calls from the generated HTML report — no CDN, no font fetch, no telemetry
- [ ] No real tenant data anywhere in the diff, the tests or this description
