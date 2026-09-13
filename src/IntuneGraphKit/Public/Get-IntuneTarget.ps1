function Get-IntuneTarget {
    <#
    .SYNOPSIS
        Show everything that applies to a device or user - and the group path that causes each.
    .DESCRIPTION
        Feature 1. Resolves the full set of configuration profiles, compliance
        policies, apps and scripts that target a device or user, following group
        membership (including nesting), assignment filters, and include/exclude
        semantics (exclusion wins). The 'Via' column - the membership chain that
        causes each assignment - is what flat-list tools don't give you.
    .EXAMPLE
        Get-IntuneTarget -Identity DEV-FIN-01
    .EXAMPLE
        Get-IntuneTarget -Identity alice@contoso.com -IncludeExcluded
    #>
    [CmdletBinding(DefaultParameterSetName = 'Identity')]
    param(
        [Parameter(ParameterSetName = 'Identity', Mandatory, Position = 0)]
        [string]$Identity,
        [Parameter(ParameterSetName = 'Device', Mandatory)]
        [string]$Device,
        [Parameter(ParameterSetName = 'User', Mandatory)]
        [string]$User,
        [ValidateSet('ConfigPolicy', 'CompliancePolicy', 'App', 'Script')]
        [string]$Type,
        [switch]$IncludeExcluded,
        $Graph,
        [string]$Path
    )
    $g = Get-IgWorkingGraph -Graph $Graph -Path $Path

    switch ($PSCmdlet.ParameterSetName) {
        'Device' { $entityId = Resolve-IgNodeIdentity -Graph $g -Identity $Device -Type 'Device' }
        'User' { $entityId = Resolve-IgNodeIdentity -Graph $g -Identity $User -Type 'User' }
        default { $entityId = Resolve-IgNodeIdentity -Graph $g -Identity $Identity }
    }

    $records = Resolve-IgEffectiveAssignments -Graph $g -EntityId $entityId
    $out = foreach ($r in $records) {
        if ($Type -and $r.Type -ne $Type) { continue }
        if (-not $IncludeExcluded -and $r.Status -eq 'Excluded') { continue }
        [pscustomobject]@{
            Workload = $r.Workload
            Type     = $r.Type
            Status   = $r.Status
            Intent   = $r.Intent
            Via      = $r.Via
            Filter   = if ($r.FilterId -and $g.Nodes.ContainsKey($r.FilterId)) { $g.Nodes[$r.FilterId].name } else { $null }
        }
    }
    $entityName = $g.Nodes[$entityId].name
    Write-Verbose "Target: $entityName ($entityId)"
    $out | Sort-Object @{ Expression = { $_.Status -eq 'Excluded' } }, Type, Workload
}
