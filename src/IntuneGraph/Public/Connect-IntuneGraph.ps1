function Connect-IntuneGraph {
    <#
    .SYNOPSIS
        Authenticate to Microsoft Graph with least-privilege, read-only scopes.
    .DESCRIPTION
        Lazily loads Microsoft.Graph.Authentication and calls Connect-MgGraph with
        the four read-only scopes IntuneGraph needs. The module requests zero write
        scopes and contains no write code paths.
    .EXAMPLE
        Connect-IntuneGraph
    .EXAMPLE
        Connect-IntuneGraph -TenantId contoso.onmicrosoft.com -UseDeviceCode
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string[]]$Scopes = @(
            'DeviceManagementConfiguration.Read.All',
            'DeviceManagementApps.Read.All',
            'DeviceManagementManagedDevices.Read.All',
            'Group.Read.All'
        ),
        [string]$ClientId,
        [string]$CertificateThumbprint,
        [switch]$UseDeviceCode,
        [ValidateSet('Global', 'USGov', 'USGovDoD')]
        [string]$Environment = 'Global'
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw "Microsoft.Graph.Authentication is not installed. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $connectParams = @{ NoWelcome = $true }
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }
    if ($Environment -ne 'Global') { $connectParams['Environment'] = $Environment }

    if ($ClientId -and $CertificateThumbprint) {
        $connectParams['ClientId'] = $ClientId
        $connectParams['CertificateThumbprint'] = $CertificateThumbprint
    }
    else {
        $connectParams['Scopes'] = $Scopes
        if ($UseDeviceCode) { $connectParams['UseDeviceCode'] = $true }
    }

    Connect-MgGraph @connectParams

    $ctx = Get-MgContext
    $script:IgSession.Mode = 'Live'
    $script:IgSession.TenantId = $ctx.TenantId
    $script:IgSession.Account = $ctx.Account
    $script:IgSession.Scopes = $ctx.Scopes
    $script:IgSession.ConnectedAt = (Get-Date)

    # Reinforce the least-privilege story: warn if granted scopes exceed requested.
    $extra = @($ctx.Scopes | Where-Object { $Scopes -notcontains $_ -and $_ -notmatch '^(openid|profile|offline_access|User.Read)$' })
    if ($extra.Count -gt 0) {
        Write-Warning "Granted scopes exceed IntuneGraph's minimum: $($extra -join ', '). IntuneGraph only reads; it never writes."
    }

    [pscustomobject]@{
        TenantId = $ctx.TenantId
        Account  = $ctx.Account
        Scopes   = $ctx.Scopes
        Mode     = 'Live'
    }
}
