function Disconnect-IntuneGraph {
    <#
    .SYNOPSIS
        Disconnect from Microsoft Graph and clear the IntuneGraph session.
    #>
    [CmdletBinding()]
    param()
    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
        try { Disconnect-MgGraph -ErrorAction Stop | Out-Null }
        catch { Write-Verbose "Disconnect-MgGraph: $($_.Exception.Message)" }
    }
    $script:IgSession.Mode = 'None'
    $script:IgSession.TenantId = $null
    $script:IgSession.Account = $null
    $script:IgSession.Scopes = @()
    $script:IgSession.ConnectedAt = $null
    Write-Verbose "IntuneGraph session cleared."
}
