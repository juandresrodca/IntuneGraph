function Find-IntuneOrphan {
    <#
    .SYNOPSIS
        Scan the graph for assignment hygiene problems.
    .DESCRIPTION
        Feature 3. Finds unassigned workloads, assignments to empty or deleted
        groups, include/exclude collisions, unused assignment filters, and
        device-vs-user mixed targeting that silently does nothing.
    .EXAMPLE
        Find-IntuneOrphan
    .EXAMPLE
        Find-IntuneOrphan -Check IncludeExcludeCollision, BrokenGroupReference -Severity High
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All', 'Unassigned', 'EmptyTarget', 'IncludeExcludeCollision', 'BrokenGroupReference', 'UnusedFilter', 'MixedTargeting')]
        [string[]]$Check = @('All'),
        [ValidateSet('Info', 'Warning', 'High')]
        [string]$Severity,
        $Graph,
        [string]$Path
    )
    $g = Get-IgWorkingGraph -Graph $Graph -Path $Path
    $findings = Test-IgHygiene -Graph $g -Check $Check

    if ($Severity) { $findings = @($findings | Where-Object { $_.Severity -eq $Severity }) }

    $sevRank = @{ High = 0; Warning = 1; Info = 2 }
    $findings | Sort-Object @{ Expression = { $sevRank[$_.Severity] } }, Check, NodeName
}
