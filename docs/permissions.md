# Permissions & security

IntuneGraph is **read-only by construction**. The only function that calls
Microsoft Graph (`Invoke-IgLiveRequest`) hardcodes `-Method GET`; there are no
`POST`, `PATCH` or `DELETE` code paths anywhere in the module.

## Delegated (interactive) scopes

`Connect-IntuneGraph` requests exactly these four scopes:

| Scope | Covers |
|---|---|
| `DeviceManagementConfiguration.Read.All` | configuration policies, legacy device configurations, compliance policies, platform scripts, remediations, assignment filters |
| `DeviceManagementApps.Read.All` | mobile apps and their assignments |
| `DeviceManagementManagedDevices.Read.All` | managed devices |
| `Group.Read.All` | groups and group membership |

Intentionally **not** requested: `Directory.Read.All`, `User.Read.All`,
`DeviceManagementServiceConfig.Read.All`, and any `*.ReadWrite.*` scope.

## App-only (unattended) auth

For automation, register an Entra app, grant the four **Application** permissions
above (admin consent), and connect with a certificate:

```powershell
Connect-IntuneGraph -TenantId <tenant> -ClientId <appId> -CertificateThumbprint <thumb>
```

## Data handling

- **No telemetry.** IntuneGraph never phones home.
- **The HTML report makes zero network calls.** The graph renderer is a small
  vendored, inline vanilla-JS force-directed layout — no CDN, no fonts, no
  analytics. Safe to open on an air-gapped machine.
- **Your data stays local.** Everything lives in the `graph.json` you export.
  Treat that file as sensitive (it describes your tenant) and keep it out of
  source control — the default `.gitignore` already excludes it.

## National clouds

Pass `-Environment USGov` or `-Environment USGovDoD` to `Connect-IntuneGraph`.
