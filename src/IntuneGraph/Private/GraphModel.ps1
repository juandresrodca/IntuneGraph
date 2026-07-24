# In-memory graph model and the traversal primitives every query builds on.

function New-IgGraph {
    <#
        Build an indexed in-memory graph from canonical nodes + edges.
        Adds builtin target nodes and synthesizes stub nodes for edges that
        point at a missing group (deleted-group "ghost" -> BrokenGroupReference).
    #>
    param(
        [System.Collections.IDictionary]$Metadata,
        $Nodes,
        $Edges
    )
    $nodeDict = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($n in (ConvertTo-IgArray $Nodes)) {
        if ($null -eq $n) { continue }
        if (-not $nodeDict.ContainsKey([string]$n.id)) { $nodeDict[[string]$n.id] = $n }
    }

    # Builtins.
    foreach ($b in @(
            @{ id = 'builtin-allDevices'; name = 'All Devices' },
            @{ id = 'builtin-allUsers'; name = 'All Users' })) {
        if (-not $nodeDict.ContainsKey($b.id)) {
            $nodeDict[$b.id] = New-IgNode -Id $b.id -Type 'Builtin' -Name $b.name -SourceId $b.id -Properties @{}
        }
    }

    $edgeList = New-Object System.Collections.Generic.List[object]
    $counter = 0
    foreach ($e in (ConvertTo-IgArray $Edges)) {
        if ($null -eq $e) { continue }
        # Synthesize ghost nodes for missing endpoints (deleted group references).
        foreach ($endpoint in @($e.from, $e.to)) {
            if ($endpoint -and -not $nodeDict.ContainsKey($endpoint)) {
                if ($endpoint -like 'grp-*') {
                    $nodeDict[$endpoint] = New-IgNode -Id $endpoint -Type 'Group' -Name '(deleted group)' -SourceId ($endpoint -replace '^grp-', '') -Properties @{ missing = $true }
                }
            }
        }
        $counter++
        if (-not (Get-IgProp $e 'id')) {
            $e | Add-Member -NotePropertyName 'id' -NotePropertyValue ('e-{0:D6}' -f $counter) -Force
        }
        [void]$edgeList.Add($e)
    }

    $graph = [pscustomobject]@{
        PSTypeName = 'IntuneGraph.Graph'
        Metadata   = $Metadata
        Nodes      = $nodeDict
        Edges      = $edgeList
        Out        = $null
        In         = $null
        NameIndex  = $null
    }
    Add-IgGraphIndex -Graph $graph
    return $graph
}

function Add-IgGraphIndex {
    <# Build Out/In adjacency and the name index (all case-insensitive). #>
    param([Parameter(Mandatory)]$Graph)

    $out = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $in = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $nameIndex = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($e in $Graph.Edges) {
        if (-not $out.ContainsKey($e.from)) { $out[$e.from] = New-Object System.Collections.Generic.List[object] }
        [void]$out[$e.from].Add($e)
        if (-not $in.ContainsKey($e.to)) { $in[$e.to] = New-Object System.Collections.Generic.List[object] }
        [void]$in[$e.to].Add($e)
    }

    foreach ($node in $Graph.Nodes.Values) {
        foreach ($key in @($node.name, (Get-IgProp $node.properties 'userPrincipalName'), $node.sourceId)) {
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if (-not $nameIndex.ContainsKey($key)) { $nameIndex[$key] = New-Object System.Collections.Generic.List[object] }
            if (-not $nameIndex[$key].Contains($node.id)) { [void]$nameIndex[$key].Add($node.id) }
        }
    }

    $Graph.Out = $out
    $Graph.In = $in
    $Graph.NameIndex = $nameIndex
}

function Get-IgOutEdges {
    param($Graph, [string]$NodeId, [string]$Type)
    if (-not $Graph.Out.ContainsKey($NodeId)) { return @() }
    $edges = ConvertTo-IgArray $Graph.Out[$NodeId]
    if ($Type) { return @($edges | Where-Object { $_.type -eq $Type }) }
    return $edges
}
function Get-IgInEdges {
    param($Graph, [string]$NodeId, [string]$Type)
    if (-not $Graph.In.ContainsKey($NodeId)) { return @() }
    $edges = ConvertTo-IgArray $Graph.In[$NodeId]
    if ($Type) { return @($edges | Where-Object { $_.type -eq $Type }) }
    return $edges
}

function Resolve-IgNodeIdentity {
    <#
        Resolve a user-supplied identity (GUID, node id, name, UPN, device name)
        to a single node id. Throws with candidates on ambiguity.
    #>
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$Identity,
        [string]$Type
    )
    # Direct node id or prefixed id.
    if ($Graph.Nodes.ContainsKey($Identity)) { return $Identity }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Graph.NameIndex.ContainsKey($Identity)) {
        foreach ($id in $Graph.NameIndex[$Identity]) { [void]$candidates.Add($id) }
    }
    # Fallback: match on sourceId GUID with any prefix.
    if ($candidates.Count -eq 0) {
        foreach ($node in $Graph.Nodes.Values) {
            if ($node.sourceId -and $node.sourceId -ieq $Identity) { [void]$candidates.Add($node.id) }
        }
    }

    if ($Type) {
        $candidates = [System.Collections.Generic.List[string]]@($candidates | Where-Object { $Graph.Nodes[$_].type -eq $Type })
    }

    $unique = @($candidates | Select-Object -Unique)
    if ($unique.Count -eq 0) { throw "No node found matching identity '$Identity'." }
    if ($unique.Count -gt 1) {
        $list = ($unique | ForEach-Object { "$($Graph.Nodes[$_].type):$($Graph.Nodes[$_].name) [$_]" }) -join '; '
        throw "Identity '$Identity' is ambiguous. Candidates: $list. Re-run with a node id or -Type."
    }
    return $unique[0]
}

function Resolve-IgGroupClosure {
    <#
        Direction Up:   from a user/device/group, BFS over memberOf edges to find
                        all containing groups, each with the full membership path
                        (list of node ids from the entity up to the group).
        Direction Down: from a group, BFS over reverse memberOf edges to find all
                        transitive members (users/devices/nested groups).
        Cycle-guarded.
    #>
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$EntityId,
        [ValidateSet('Up', 'Down')][string]$Direction = 'Up'
    )
    $result = @{}   # reachedNodeId -> path (array of node ids)
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    [void]$visited.Add($EntityId)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([pscustomobject]@{ Id = $EntityId; Path = @($EntityId) })

    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        if ($Direction -eq 'Up') {
            $edges = Get-IgOutEdges -Graph $Graph -NodeId $cur.Id -Type 'memberOf'
            foreach ($e in $edges) {
                if ($visited.Add($e.to)) {
                    $newPath = @($cur.Path) + $e.to
                    $result[$e.to] = $newPath
                    $queue.Enqueue([pscustomobject]@{ Id = $e.to; Path = $newPath })
                }
            }
        }
        else {
            $edges = Get-IgInEdges -Graph $Graph -NodeId $cur.Id -Type 'memberOf'
            foreach ($e in $edges) {
                if ($visited.Add($e.from)) {
                    $newPath = @($cur.Path) + $e.from
                    $result[$e.from] = $newPath
                    $queue.Enqueue([pscustomobject]@{ Id = $e.from; Path = $newPath })
                }
            }
        }
    }
    return $result
}
