# Small shared helpers.

function Get-IgProp {
    <#
        Safely read a property from a PSCustomObject or key from a hashtable.
        Returns $Default (default $null) when the property/key is absent or the
        input is $null. Graph responses have many optional properties, so every
        optional read goes through here.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        $InputObject,
        [Parameter(Mandatory, Position = 1)]
        [string]$Name,
        [Parameter(Position = 2)]
        $Default = $null
    )
    if ($null -eq $InputObject) { return $Default }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }

    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $prop) { return $prop.Value }
    return $Default
}

function ConvertTo-IgArray {
    <#
        Safely materialize any value to an array. Windows PowerShell 5.1 throws
        "Argument types do not match" for the array-subexpression @() operator when
        applied directly to a [System.Collections.Generic.List[object]]; the
        [object[]] cast does not, so route all List->array conversions through here.
    #>
    param($InputObject)
    if ($null -eq $InputObject) { return @() }
    return [object[]]$InputObject
}

function Get-IgWorkingGraph {
    <#
        Resolve the graph a query cmdlet should operate on: an explicit -Graph
        object, a -Path to graph.json, or the session's last exported graph.
    #>
    param($Graph, [string]$Path)
    if ($Graph) {
        if ($Graph.PSObject.TypeNames -contains 'IntuneGraph.Graph') { return $Graph }
        throw "The -Graph argument is not an IntuneGraph graph object. Pipe from Export-IntuneGraph/Import-IntuneGraph."
    }
    if ($Path) { return (ConvertFrom-IgGraphJson -Path $Path) }
    if ($script:IgSession.LastGraph) { return $script:IgSession.LastGraph }
    throw "No graph available. Run Export-IntuneGraph or Import-IntuneGraph first, or pass -Graph / -Path."
}

function ConvertTo-IgShortType {
    <#
        Trim a Graph @odata.type like '#microsoft.graph.win32LobApp' down to 'win32LobApp'.
    #>
    param([string]$OdataType)
    if ([string]::IsNullOrWhiteSpace($OdataType)) { return $null }
    return ($OdataType -replace '^#?microsoft\.graph\.', '')
}
