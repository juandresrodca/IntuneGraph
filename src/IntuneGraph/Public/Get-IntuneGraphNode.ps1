function Get-IntuneGraphNode {
    <#
    .SYNOPSIS
        Search and browse nodes in the graph.
    .EXAMPLE
        Get-IntuneGraphNode -Type Group
    .EXAMPLE
        Get-IntuneGraphNode -Name 'Win11*'
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Device', 'User', 'Group', 'Filter', 'ConfigPolicy', 'CompliancePolicy', 'App', 'Script', 'Builtin')]
        [string]$Type,
        [string]$Name,
        [string]$Id,
        $Graph,
        [string]$Path
    )
    $g = Get-IgWorkingGraph -Graph $Graph -Path $Path
    $result = foreach ($node in $g.Nodes.Values) {
        if ($Type -and $node.type -ne $Type) { continue }
        if ($Id -and $node.id -ne $Id) { continue }
        if ($Name -and $node.name -notlike $Name) { continue }
        [pscustomobject]@{
            Type = $node.type
            Name = $node.name
            Subtype = $node.subtype
            Id   = $node.id
        }
    }
    $result | Sort-Object Type, Name
}
