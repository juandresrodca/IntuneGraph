# Query engine: pure functions over an IgGraph. No I/O.

$script:IgWorkloadTypes = @('ConfigPolicy', 'CompliancePolicy', 'App', 'Script')

function Get-IgWorkloadNodes {
    param($Graph)
    @($Graph.Nodes.Values | Where-Object { $script:IgWorkloadTypes -contains $_.type })
}

function Resolve-IgEffectiveAssignments {
    <#
        Given a device/user/group entity, return one record per workload that
        targets it, with status (Applies | AppliesPreFilter | Excluded), the
        membership path that causes it, and filter/intent annotations.
        Exclusion wins over include.
    #>
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$EntityId
    )
    if (-not $Graph.Nodes.ContainsKey($EntityId)) { throw "Entity '$EntityId' not in graph." }
    $entityType = $Graph.Nodes[$EntityId].type

    # Candidate assignment targets -> path from entity to target.
    $targets = @{}
    $targets[$EntityId] = @($EntityId)
    $up = Resolve-IgGroupClosure -Graph $Graph -EntityId $EntityId -Direction Up
    foreach ($gid in $up.Keys) { $targets[$gid] = $up[$gid] }
    if ($entityType -eq 'Device') { $targets['builtin-allDevices'] = @($EntityId, 'builtin-allDevices') }
    if ($entityType -eq 'User') { $targets['builtin-allUsers'] = @($EntityId, 'builtin-allUsers') }

    # Collect assignedTo edges hitting any candidate target, grouped by workload.
    $byWorkload = @{}   # workloadId -> list of @{ edge; targetId; path }
    foreach ($targetId in $targets.Keys) {
        foreach ($e in (Get-IgInEdges -Graph $Graph -NodeId $targetId -Type 'assignedTo')) {
            $wid = $e.from
            if (-not $byWorkload.ContainsKey($wid)) { $byWorkload[$wid] = New-Object System.Collections.Generic.List[object] }
            [void]$byWorkload[$wid].Add([pscustomobject]@{ edge = $e; targetId = $targetId; path = $targets[$targetId] })
        }
    }

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($wid in $byWorkload.Keys) {
        if (-not $Graph.Nodes.ContainsKey($wid)) { continue }
        $wnode = $Graph.Nodes[$wid]
        $hits = $byWorkload[$wid]
        $excludeHit = $hits | Where-Object { $_.edge.properties.mode -eq 'exclude' } | Select-Object -First 1
        $includeHit = $hits | Where-Object { $_.edge.properties.mode -eq 'include' } | Select-Object -First 1

        if ($excludeHit) {
            $status = 'Excluded'; $winner = $excludeHit
        }
        elseif ($includeHit) {
            $winner = $includeHit
            $status = if ($winner.edge.properties.filterId) { 'AppliesPreFilter' } else { 'Applies' }
        }
        else { continue }

        $viaName = ($winner.path | ForEach-Object { $Graph.Nodes[$_].name }) -join ' -> '
        [void]$records.Add([pscustomobject]@{
            WorkloadId   = $wid
            Workload     = $wnode.name
            Type         = $wnode.type
            Subtype      = $wnode.subtype
            Status       = $status
            Intent       = $winner.edge.properties.intent
            Mode         = $winner.edge.properties.mode
            ViaTargetId  = $winner.targetId
            Via          = $viaName
            Path         = $winner.path
            FilterId     = $winner.edge.properties.filterId
            FilterMode   = $winner.edge.properties.filterMode
        })
    }
    return @($records | Sort-Object Type, Workload)
}

function Get-IgApplyingSet {
    <# Set of workload ids that actually apply (Applies or AppliesPreFilter). #>
    param($Records)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @($Records)) {
        if ($r.Status -eq 'Applies' -or $r.Status -eq 'AppliesPreFilter') { [void]$set.Add($r.WorkloadId) }
    }
    return $set
}

function Get-IgAssignmentDiff {
    <# Diff two effective-assignment record sets. Returns Gains / Loses records. #>
    param($Before, $After)
    $beforeSet = Get-IgApplyingSet -Records $Before
    $afterSet = Get-IgApplyingSet -Records $After
    $afterById = @{}; foreach ($r in @($After)) { $afterById[$r.WorkloadId] = $r }
    $beforeById = @{}; foreach ($r in @($Before)) { $beforeById[$r.WorkloadId] = $r }

    $gains = New-Object System.Collections.Generic.List[object]
    foreach ($id in $afterSet) { if (-not $beforeSet.Contains($id)) { [void]$gains.Add($afterById[$id]) } }
    $loses = New-Object System.Collections.Generic.List[object]
    foreach ($id in $beforeSet) { if (-not $afterSet.Contains($id)) { [void]$loses.Add($beforeById[$id]) } }

    [pscustomobject]@{
        Gains = @($gains | Sort-Object Type, Workload)
        Loses = @($loses | Sort-Object Type, Workload)
    }
}

function Test-IgHygiene {
    <# Run the hygiene checks and return finding objects. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Check', Justification = 'Referenced inside the $run closure')]
    param(
        [Parameter(Mandatory)]$Graph,
        [string[]]$Check = @('All')
    )
    $run = {
        param($name)
        return ($Check -contains 'All' -or $Check -contains $name)
    }
    $findings = New-Object System.Collections.Generic.List[object]
    $add = {
        param($chk, $sev, $node, $detail, $rec)
        [void]$findings.Add([pscustomobject]@{
            Check          = $chk
            Severity       = $sev
            NodeId         = $node.id
            NodeName       = $node.name
            NodeType       = $node.type
            Detail         = $detail
            Recommendation = $rec
        })
    }

    $workloads = Get-IgWorkloadNodes -Graph $Graph

    foreach ($w in $workloads) {
        $assign = Get-IgOutEdges -Graph $Graph -NodeId $w.id -Type 'assignedTo'

        # 1. Unassigned
        if ((& $run 'Unassigned') -and $assign.Count -eq 0) {
            & $add 'Unassigned' 'Info' $w "$($w.type) '$($w.name)' has no assignments." 'Assign it or delete it to reduce clutter.'
        }

        # 3. IncludeExcludeCollision (same group included and excluded)
        if (& $run 'IncludeExcludeCollision') {
            $incl = @($assign | Where-Object { $_.properties.mode -eq 'include' } | ForEach-Object { $_.to })
            $excl = @($assign | Where-Object { $_.properties.mode -eq 'exclude' } | ForEach-Object { $_.to })
            $collide = @($incl | Where-Object { $excl -contains $_ } | Select-Object -Unique)
            foreach ($c in $collide) {
                $gname = if ($Graph.Nodes.ContainsKey($c)) { $Graph.Nodes[$c].name } else { $c }
                & $add 'IncludeExcludeCollision' 'High' $w "Group '$gname' is both included and excluded on '$($w.name)'. The exclusion wins; the include is dead." 'Remove the redundant include or exclude.'
            }
        }

        # 2. EmptyTarget (all include targets are real but empty groups).
        #    Missing/ghost group targets are owned by BrokenGroupReference and must
        #    NOT also trip EmptyTarget, so a workload with any missing include is skipped.
        if (& $run 'EmptyTarget') {
            $includes = @($assign | Where-Object { $_.properties.mode -eq 'include' })
            if ($includes.Count -gt 0) {
                $anyReach = $false
                $anyMissing = $false
                foreach ($i in $includes) {
                    if ($i.to -like 'builtin-*') { $anyReach = $true; break }
                    if ($Graph.Nodes.ContainsKey($i.to) -and (Get-IgProp $Graph.Nodes[$i.to].properties 'missing')) { $anyMissing = $true; continue }
                    if ($Graph.Nodes.ContainsKey($i.to)) {
                        $members = Resolve-IgGroupClosure -Graph $Graph -EntityId $i.to -Direction Down
                        $realMembers = @($members.Keys | Where-Object { $Graph.Nodes[$_].type -in @('Device', 'User') })
                        if ($realMembers.Count -gt 0) { $anyReach = $true; break }
                    }
                }
                if (-not $anyReach -and -not $anyMissing) {
                    & $add 'EmptyTarget' 'Warning' $w "'$($w.name)' is assigned only to empty group(s); it applies to nothing." 'Populate the target group or remove the assignment.'
                }
            }
        }

        # 4. BrokenGroupReference (assignment to a missing/ghost group)
        if (& $run 'BrokenGroupReference') {
            foreach ($e in $assign) {
                if ($Graph.Nodes.ContainsKey($e.to) -and (Get-IgProp $Graph.Nodes[$e.to].properties 'missing')) {
                    & $add 'BrokenGroupReference' 'High' $w "'$($w.name)' targets a deleted group ($($e.to -replace '^grp-', ''))." 'Remove the stale assignment.'
                }
            }
        }

        # 6. MixedTargeting (device workload excluding a user-only group)
        if (& $run 'MixedTargeting') {
            if ($w.type -in @('ConfigPolicy', 'CompliancePolicy', 'Script')) {
                foreach ($e in @($assign | Where-Object { $_.properties.mode -eq 'exclude' -and $_.to -like 'grp-*' })) {
                    if ($Graph.Nodes.ContainsKey($e.to) -and -not (Get-IgProp $Graph.Nodes[$e.to].properties 'missing')) {
                        $members = Resolve-IgGroupClosure -Graph $Graph -EntityId $e.to -Direction Down
                        $types = @($members.Keys | ForEach-Object { $Graph.Nodes[$_].type } | Where-Object { $_ -in @('Device', 'User') } | Select-Object -Unique)
                        if ($types.Count -eq 1 -and $types[0] -eq 'User') {
                            $gname = $Graph.Nodes[$e.to].name
                            & $add 'MixedTargeting' 'Warning' $w "Device-context '$($w.name)' excludes user-only group '$gname'; the exclusion silently does nothing." 'Exclude a device group instead.'
                        }
                    }
                }
            }
        }
    }

    # 5. UnusedFilter
    if (& $run 'UnusedFilter') {
        foreach ($f in @($Graph.Nodes.Values | Where-Object { $_.type -eq 'Filter' })) {
            $used = Get-IgInEdges -Graph $Graph -NodeId $f.id -Type 'filteredBy'
            if ($used.Count -eq 0) {
                & $add 'UnusedFilter' 'Info' $f "Assignment filter '$($f.name)' is referenced by no assignment." 'Delete it if no longer needed.'
            }
        }
    }

    return (ConvertTo-IgArray $findings)
}
