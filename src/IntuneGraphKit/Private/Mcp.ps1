# MCP (Model Context Protocol) server engine: exposes the graph as read-only tools
# over newline-delimited JSON-RPC 2.0, so an AI client can ask why a policy applies
# and get the real membership path instead of a guess.
#
# LOAD ORDER: the module loader dot-sources Private/*.ps1 sorted by path, so this
# file loads BEFORE Normalize.ps1, Query.ps1 and Util.ps1. Everything at top level
# here must therefore be a literal or a scriptblock - never a call to Get-IgProp,
# ConvertTo-IgArray or any query function. Scriptblock BODIES are safe: they only
# run once the whole module is loaded.
#
# STDOUT IS THE TRANSPORT. Nothing in this file may Write-Host, Write-Output to the
# success stream from the loop, or call a public cmdlet (Get-IntuneBlastRadius and
# Export-IntuneGraph both Write-Host their summaries, which lands on stdout and
# corrupts the stream). Handlers call the pure query layer only. Diagnostics go to
# stderr via Write-IgMcpLog.

$script:IgMcpServerName    = 'intunegraph'
$script:IgMcpServerVersion = '0.2.0'

# Legacy era: the 'initialize' handshake. This is what every shipping client speaks
# or falls back to. Modern era (per-request _meta) is additive; see Invoke-IgMcpRequest.
$script:IgMcpLegacyVersions = @('2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05')
$script:IgMcpModernVersions = @('2026-07-28')
$script:IgMcpDefaultVersion = '2025-06-18'

$script:IgMcpLogEnabled = $false

$script:IgMcpInstructions = @'
IntuneGraph answers relationship questions about a Microsoft Intune tenant from a
local, read-only snapshot (graph.json). It resolves group nesting, assignment
filters and include/exclude semantics (an exclusion always wins over an include).

Prefer intune_target when asked what applies to a device or user, and always quote
its "Via" column - that is the exact group path that causes the assignment, which
is the part no other tool can tell you. Use intune_blast_radius before any group
membership change. The snapshot is a point-in-time export: check intune_summary if
the age of the data matters to the answer.
'@

# --- Tool registry ----------------------------------------------------------------
# One registry drives both tools/list and tools/call, so the advertised schema and
# the executed handler can never drift apart. Handler signature is uniform:
#   param($Graph, $Arguments) -> @{ Text = <string>; Data = <object> }
# The parameter is named $Arguments, never $Args: PSAvoidAssignmentToAutomaticVariable
# is Error severity and would fail the build.

$script:IgMcpTools = [ordered]@{

    'intune_target' = @{
        Description = 'What actually applies to a device or user, and the exact group path (Via) that causes each assignment. Resolves nested groups, assignment filters, and include/exclude semantics where an exclusion wins. Use this to answer "why does this policy apply to X?".'
        Schema      = {
            [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    identity        = [ordered]@{ type = 'string'; description = 'Device name, user UPN, group name, object GUID, or graph node id. For example DEV-FIN-01 or alice@contoso.com.' }
                    type            = [ordered]@{ type = 'string'; enum = [object[]]@('ConfigPolicy', 'CompliancePolicy', 'App', 'Script'); description = 'Only return workloads of this kind.' }
                    includeExcluded = [ordered]@{ type = 'boolean'; description = 'Also list workloads that are blocked by an exclusion, so you can explain what is NOT applying and why.' }
                }
                required             = [object[]]@('identity')
                additionalProperties = $false
            }
        }
        Handler     = {
            param($Graph, $Arguments)
            $identity = [string](Get-IgProp $Arguments 'identity')
            if ([string]::IsNullOrWhiteSpace($identity)) { throw "Required argument 'identity' is missing." }
            $includeExcluded = [bool](Get-IgProp $Arguments 'includeExcluded' $false)
            $typeFilter = [string](Get-IgProp $Arguments 'type')

            $entityId = Resolve-IgNodeIdentity -Graph $Graph -Identity $identity
            $entity = $Graph.Nodes[$entityId]
            $records = Resolve-IgEffectiveAssignments -Graph $Graph -EntityId $entityId

            $rows = New-Object System.Collections.Generic.List[object]
            foreach ($r in $records) {
                if ($typeFilter -and $r.Type -ne $typeFilter) { continue }
                if (-not $includeExcluded -and $r.Status -eq 'Excluded') { continue }
                $filterName = ''
                if ($r.FilterId -and $Graph.Nodes.ContainsKey($r.FilterId)) { $filterName = $Graph.Nodes[$r.FilterId].name }
                [void]$rows.Add([pscustomobject]@{
                    Workload = $r.Workload
                    Type     = $r.Type
                    Status   = $r.Status
                    Intent   = [string]$r.Intent
                    Via      = $r.Via
                    Filter   = $filterName
                })
            }
            $ordered = ConvertTo-IgMcpJsonArray ($rows | Sort-Object @{ Expression = { $_.Status -eq 'Excluded' } }, Type, Workload)

            $text = "$($entity.type) '$($entity.name)': $($ordered.Count) workload(s)." + "`n`n" +
                    (Format-IgMcpTable -Rows $ordered -Columns @('Workload', 'Type', 'Status', 'Intent', 'Via', 'Filter'))
            @{
                Text = $text
                Data = [ordered]@{ entity = $entity.name; entityType = $entity.type; count = $ordered.Count; results = $ordered }
            }
        }
    }

    'intune_blast_radius' = @{
        Description = 'Preview the impact of a group before changing it: every workload that reaches its members through nesting, what is removed by exclusion, and the transitive member counts. Pass whatIfAddMember or whatIfRemoveMember to simulate a membership change and get the exact workloads gained and lost.'
        Schema      = {
            [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    group              = [ordered]@{ type = 'string'; description = 'Group name, object GUID, or graph node id.' }
                    whatIfAddMember    = [ordered]@{ type = 'string'; description = 'Simulate adding this device or user to the group. Nothing is changed - the simulation is in memory only.' }
                    whatIfRemoveMember = [ordered]@{ type = 'string'; description = 'Simulate removing this device or user from the group.' }
                }
                required             = [object[]]@('group')
                additionalProperties = $false
            }
        }
        Handler     = {
            param($Graph, $Arguments)
            $group = [string](Get-IgProp $Arguments 'group')
            if ([string]::IsNullOrWhiteSpace($group)) { throw "Required argument 'group' is missing." }
            $addMember = [string](Get-IgProp $Arguments 'whatIfAddMember')
            $removeMember = [string](Get-IgProp $Arguments 'whatIfRemoveMember')
            if ($addMember -and $removeMember) { throw "Specify only one of whatIfAddMember / whatIfRemoveMember." }

            $groupId = Resolve-IgNodeIdentity -Graph $Graph -Identity $group -Type 'Group'
            $groupName = $Graph.Nodes[$groupId].name

            if ($addMember -or $removeMember) {
                $ident = $addMember
                if (-not $ident) { $ident = $removeMember }
                $entityId = Resolve-IgNodeIdentity -Graph $Graph -Identity $ident
                $diff = Get-IgMcpWhatIfDiff -Graph $Graph -EntityId $entityId -GroupId $groupId -Add:([bool]$addMember)

                $gains = ConvertTo-IgMcpJsonArray ($diff.Gains | Select-Object Workload, Type, Status, Intent, Via)
                $loses = ConvertTo-IgMcpJsonArray ($diff.Loses | Select-Object Workload, Type, Status, Intent, Via)
                $action = 'Removing'
                if ($addMember) { $action = 'Adding' }
                $preposition = 'from'
                if ($addMember) { $preposition = 'to' }

                $text = "$action '$($Graph.Nodes[$entityId].name)' $preposition '$groupName': gains $($gains.Count) workload(s), loses $($loses.Count)." + "`n`n" +
                        "GAINS`n" + (Format-IgMcpTable -Rows $gains -Columns @('Workload', 'Type', 'Intent', 'Via')) + "`n`n" +
                        "LOSES`n" + (Format-IgMcpTable -Rows $loses -Columns @('Workload', 'Type', 'Intent', 'Via'))
                return @{
                    Text = $text
                    Data = [ordered]@{
                        group  = $groupName
                        entity = $Graph.Nodes[$entityId].name
                        action = $(if ($addMember) { 'AddMember' } else { 'RemoveMember' })
                        gains  = $gains
                        loses  = $loses
                    }
                }
            }

            $records = Resolve-IgEffectiveAssignments -Graph $Graph -EntityId $groupId
            $applies = ConvertTo-IgMcpJsonArray ($records | Where-Object { $_.Status -eq 'Applies' -or $_.Status -eq 'AppliesPreFilter' } | Select-Object Workload, Type, Status, Via)
            $removes = ConvertTo-IgMcpJsonArray ($records | Where-Object { $_.Status -eq 'Excluded' } | Select-Object Workload, Type, Via)

            $down = Resolve-IgGroupClosure -Graph $Graph -EntityId $groupId -Direction Down
            $devices = @($down.Keys | Where-Object { $Graph.Nodes[$_].type -eq 'Device' })
            $users = @($down.Keys | Where-Object { $Graph.Nodes[$_].type -eq 'User' })
            $nested = @($down.Keys | Where-Object { $Graph.Nodes[$_].type -eq 'Group' })

            $text = "Blast radius: $groupName" + "`n" +
                    "Applies $($applies.Count) workload(s); removes $($removes.Count) via exclusion." + "`n" +
                    "Reach: $($devices.Count) device(s), $($users.Count) user(s), $($nested.Count) nested group(s)." + "`n`n" +
                    "APPLIES`n" + (Format-IgMcpTable -Rows $applies -Columns @('Workload', 'Type', 'Status', 'Via')) + "`n`n" +
                    "REMOVED BY EXCLUSION`n" + (Format-IgMcpTable -Rows $removes -Columns @('Workload', 'Type', 'Via'))
            @{
                Text = $text
                Data = [ordered]@{
                    group               = $groupName
                    applies             = $applies
                    removesViaExclusion = $removes
                    memberCounts        = [ordered]@{ devices = $devices.Count; users = $users.Count; nestedGroups = $nested.Count }
                }
            }
        }
    }

    'intune_orphans' = @{
        Description = 'Assignment hygiene scan: workloads assigned to nothing, assignments pointing at empty or deleted groups, include/exclude collisions on the same group, unused assignment filters, and device-context policies excluding user-only groups (which silently does nothing).'
        Schema      = {
            [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    check    = [ordered]@{
                        type        = 'array'
                        items       = [ordered]@{ type = 'string'; enum = [object[]]@('All', 'Unassigned', 'EmptyTarget', 'IncludeExcludeCollision', 'BrokenGroupReference', 'UnusedFilter', 'MixedTargeting') }
                        description = 'Which checks to run. Defaults to All.'
                    }
                    severity = [ordered]@{ type = 'string'; enum = [object[]]@('Info', 'Warning', 'High'); description = 'Only return findings at this severity.' }
                }
                additionalProperties = $false
            }
        }
        Handler     = {
            param($Graph, $Arguments)
            $check = Get-IgProp $Arguments 'check'
            if (-not $check) { $check = @('All') }
            $severity = [string](Get-IgProp $Arguments 'severity')

            $findings = Test-IgHygiene -Graph $Graph -Check ([string[]](ConvertTo-IgArray $check))
            if ($severity) { $findings = @($findings | Where-Object { $_.Severity -eq $severity }) }

            $rank = @{ High = 0; Warning = 1; Info = 2 }
            $ordered = ConvertTo-IgMcpJsonArray ($findings |
                Sort-Object @{ Expression = { $rank[$_.Severity] } }, Check, NodeName |
                Select-Object Check, Severity, NodeType, NodeName, Detail, Recommendation)

            $text = "$($ordered.Count) hygiene finding(s)." + "`n`n" +
                    (Format-IgMcpTable -Rows $ordered -Columns @('Severity', 'Check', 'NodeType', 'NodeName')) + "`n`n" +
                    (Format-IgMcpDetailList -Rows $ordered -TitleColumn 'NodeName' -Columns @('Detail', 'Recommendation'))
            @{
                Text = $text
                Data = [ordered]@{ count = $ordered.Count; results = $ordered }
            }
        }
    }

    'intune_path' = @{
        Description = 'Explain how two things in the tenant are connected: why a workload reaches a device or user, how a device ends up in a group through nesting, or what two entities have in common. Use this when the question is "why", not "what".'
        Schema      = {
            [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    from = [ordered]@{ type = 'string'; description = 'Starting point: device name, user UPN, group name, policy/app name, or graph node id.' }
                    to   = [ordered]@{ type = 'string'; description = 'Destination: device name, user UPN, group name, policy/app name, or graph node id.' }
                }
                required             = [object[]]@('from', 'to')
                additionalProperties = $false
            }
        }
        Handler     = {
            param($Graph, $Arguments)
            $from = [string](Get-IgProp $Arguments 'from')
            $to = [string](Get-IgProp $Arguments 'to')
            if ([string]::IsNullOrWhiteSpace($from)) { throw "Required argument 'from' is missing." }
            if ([string]::IsNullOrWhiteSpace($to)) { throw "Required argument 'to' is missing." }

            $fromId = Resolve-IgNodeIdentity -Graph $Graph -Identity $from
            $toId = Resolve-IgNodeIdentity -Graph $Graph -Identity $to
            Resolve-IgMcpPath -Graph $Graph -FromId $fromId -ToId $toId
        }
    }

    'intune_node' = @{
        Description = 'Search the snapshot for devices, users, groups, policies, apps, scripts or filters by name. Use it to discover the exact name to pass to the other tools when the user was vague.'
        Schema      = {
            [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    query = [ordered]@{ type = 'string'; description = 'Name to match. Wildcards are supported, for example "Win11*" or "*Finance*". Omit to list everything of a given type.' }
                    type  = [ordered]@{ type = 'string'; enum = [object[]]@('Device', 'User', 'Group', 'Filter', 'ConfigPolicy', 'CompliancePolicy', 'App', 'Script', 'Builtin'); description = 'Restrict to one node type.' }
                    limit = [ordered]@{ type = 'integer'; description = 'Maximum rows to return. Defaults to 50.' }
                }
                additionalProperties = $false
            }
        }
        Handler     = {
            param($Graph, $Arguments)
            $query = [string](Get-IgProp $Arguments 'query')
            $type = [string](Get-IgProp $Arguments 'type')
            $limit = [int](Get-IgProp $Arguments 'limit' 50)
            if ($limit -le 0) { $limit = 50 }
            # A bare term is far more useful as a contains-match than as an exact one.
            if ($query -and $query -notmatch '[\*\?]') { $query = "*$query*" }

            $rows = New-Object System.Collections.Generic.List[object]
            foreach ($node in $Graph.Nodes.Values) {
                if ($type -and $node.type -ne $type) { continue }
                if ($query -and $node.name -notlike $query) { continue }
                [void]$rows.Add([pscustomobject]@{
                    Name    = $node.name
                    Type    = $node.type
                    Subtype = [string]$node.subtype
                    Id      = $node.id
                })
            }
            $all = ConvertTo-IgMcpJsonArray ($rows | Sort-Object Type, Name)
            $shown = ConvertTo-IgMcpJsonArray ($all | Select-Object -First $limit)

            $text = "$($all.Count) node(s) matched"
            if ($all.Count -gt $shown.Count) { $text += ", showing the first $($shown.Count)" }
            $text += ".`n`n" + (Format-IgMcpTable -Rows $shown -Columns @('Name', 'Type', 'Subtype', 'Id'))
            @{
                Text = $text
                Data = [ordered]@{ count = $shown.Count; totalMatched = $all.Count; results = $shown }
            }
        }
    }

    'intune_summary' = @{
        Description = 'Snapshot overview: tenant, when the export was taken and how old it is, and how many devices, users, groups, policies, apps, scripts and filters it contains. Check this before making claims about how current the data is.'
        Schema      = {
            [ordered]@{
                type                 = 'object'
                properties           = [ordered]@{}
                additionalProperties = $false
            }
        }
        Handler     = {
            param($Graph, $Arguments)
            $null = $Arguments   # no arguments; referenced so PSReviewUnusedParameter stays quiet

            $byType = [ordered]@{}
            foreach ($grp in ($Graph.Nodes.Values | Group-Object type | Sort-Object Name)) { $byType[$grp.Name] = $grp.Count }

            $exportedAt = [string](Get-IgProp $Graph.Metadata 'exportedAt')
            $ageHours = $null
            if ($exportedAt) {
                $parsed = [datetime]::MinValue
                if ([datetime]::TryParse($exportedAt, [ref]$parsed)) {
                    $ageHours = [math]::Round(((Get-Date).ToUniversalTime() - $parsed.ToUniversalTime()).TotalHours, 1)
                }
            }

            $lines = New-Object System.Collections.Generic.List[string]
            [void]$lines.Add("Tenant:     " + [string](Get-IgProp $Graph.Metadata 'tenantName'))
            [void]$lines.Add("Source:     " + [string](Get-IgProp $Graph.Metadata 'source'))
            [void]$lines.Add("Exported:   $exportedAt")
            if ($null -ne $ageHours) { [void]$lines.Add("Snapshot age: $ageHours hour(s)") }
            [void]$lines.Add("Nodes:      $($Graph.Nodes.Count)   Edges: $($Graph.Edges.Count)")
            [void]$lines.Add('')
            foreach ($k in $byType.Keys) { [void]$lines.Add(("  {0,-18}{1}" -f $k, $byType[$k])) }

            @{
                Text = (($lines) -join "`n")
                Data = [ordered]@{
                    tenantName = Get-IgProp $Graph.Metadata 'tenantName'
                    tenantId   = Get-IgProp $Graph.Metadata 'tenantId'
                    source     = Get-IgProp $Graph.Metadata 'source'
                    exportedAt = $exportedAt
                    ageHours   = $ageHours
                    nodeCount  = $Graph.Nodes.Count
                    edgeCount  = $Graph.Edges.Count
                    byNodeType = $byType
                }
            }
        }
    }
}

# --- Diagnostics -------------------------------------------------------------------

function Write-IgMcpLog {
    <#
        Diagnostics MUST go to stderr: stdout is the JSON-RPC transport and a single
        stray line poisons the session. [Console]::Error writes raw (no CLIXML
        wrapping) and auto-flushes, so MCP clients show it verbatim in their logs.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Always
    )
    if (-not $Always -and -not $script:IgMcpLogEnabled) { return }
    [Console]::Error.WriteLine("[IntuneGraph MCP] $Message")
}

# --- Formatting --------------------------------------------------------------------

function ConvertTo-IgMcpJsonArray {
    <#
        Materialize a value as an array that SURVIVES being returned, so it
        serializes as [] rather than {}.

        ConvertTo-IgArray is correct for counting and iterating, but PowerShell
        unrolls an empty array on the way out of a function, so
        `@{ loses = (ConvertTo-IgArray $null) }` serializes as {} - which a client
        then reads as one empty object instead of zero results. The comma wrapper is
        the standard fix: it survives the unrolling and leaves the inner array intact.

        Use this for anything that lands in structuredContent; use ConvertTo-IgArray
        everywhere else.
    #>
    param($InputObject)
    # Cast in place rather than calling ConvertTo-IgArray: its empty result is already
    # unrolled away by the time it returns, so wrapping that would only preserve a $null.
    if ($null -eq $InputObject) { return , ([object[]]@()) }
    $arr = [object[]]$InputObject
    if ($null -eq $arr) { return , ([object[]]@()) }
    return , $arr
}

function Format-IgMcpTable {
    <#
        Fixed-width table sized from the DATA, never from $Host.UI.RawUI.WindowSize.
        Format-Table would consult the host width, which in a redirected MCP child
        process falls back to 80 columns and truncates the Via column with an ellipsis
        - destroying the single most useful field the tool produces.
    #>
    param($Rows, [string[]]$Columns)
    $rows = ConvertTo-IgArray $Rows
    if ($rows.Count -eq 0) { return '(none)' }

    # Drop columns that are empty for every row, so narrow results stay readable.
    $used = New-Object System.Collections.Generic.List[string]
    foreach ($c in $Columns) {
        foreach ($r in $rows) {
            if (-not [string]::IsNullOrEmpty([string](Get-IgProp $r $c))) { [void]$used.Add($c); break }
        }
    }
    if ($used.Count -eq 0) { return '(none)' }

    $width = @{}
    foreach ($c in $used) {
        $max = $c.Length
        foreach ($r in $rows) {
            $len = ([string](Get-IgProp $r $c)).Length
            if ($len -gt $max) { $max = $len }
        }
        $width[$c] = $max
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(((($used | ForEach-Object { $_.PadRight($width[$_]) }) -join '  ').TrimEnd()))
    [void]$sb.AppendLine((($used | ForEach-Object { '-' * $width[$_] }) -join '  '))
    foreach ($r in $rows) {
        [void]$sb.AppendLine(((($used | ForEach-Object { ([string](Get-IgProp $r $_)).PadRight($width[$_]) }) -join '  ').TrimEnd()))
    }
    return $sb.ToString().TrimEnd()
}

function Format-IgMcpDetailList {
    <# Per-row prose block, for findings where the Detail sentence carries the value. #>
    param($Rows, [string]$TitleColumn, [string[]]$Columns)
    $rows = ConvertTo-IgArray $Rows
    if ($rows.Count -eq 0) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($r in $rows) {
        [void]$sb.AppendLine("* " + [string](Get-IgProp $r $TitleColumn))
        foreach ($c in $Columns) {
            $v = [string](Get-IgProp $r $c)
            if ($v) { [void]$sb.AppendLine("    ${c}: $v") }
        }
    }
    return $sb.ToString().TrimEnd()
}

function Format-IgMcpNodePath {
    <# A list of node ids -> 'DEV-FIN-01 -> SG-Finance -> SG-AllStaff'. #>
    param($Graph, $Path)
    $names = foreach ($id in (ConvertTo-IgArray $Path)) {
        if ($Graph.Nodes.ContainsKey($id)) { $Graph.Nodes[$id].name } else { $id }
    }
    return ($names -join ' -> ')
}

# --- Query helpers used only by the tool handlers ----------------------------------

function Get-IgMcpWhatIfDiff {
    <#
        Simulate a membership change in memory and diff the effective assignments.
        Mirrors Get-IntuneBlastRadius's edge splice, but returns the diff instead of
        writing a summary to the host (which would corrupt the JSON-RPC stream).
        The temporary edge is always removed in a finally block.
    #>
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$EntityId,
        [Parameter(Mandatory)][string]$GroupId,
        [switch]$Add
    )
    $before = Resolve-IgEffectiveAssignments -Graph $Graph -EntityId $EntityId

    if ($Add) {
        $tmp = [pscustomobject]@{ id = 'tmp-mcp-whatif'; type = 'memberOf'; from = $EntityId; to = $GroupId; properties = @{} }
        if (-not $Graph.Out.ContainsKey($EntityId)) { $Graph.Out[$EntityId] = New-Object System.Collections.Generic.List[object] }
        if (-not $Graph.In.ContainsKey($GroupId)) { $Graph.In[$GroupId] = New-Object System.Collections.Generic.List[object] }
        $Graph.Out[$EntityId].Add($tmp); $Graph.In[$GroupId].Add($tmp)
        try { $after = Resolve-IgEffectiveAssignments -Graph $Graph -EntityId $EntityId }
        finally { [void]$Graph.Out[$EntityId].Remove($tmp); [void]$Graph.In[$GroupId].Remove($tmp) }
    }
    else {
        $removed = @()
        if ($Graph.Out.ContainsKey($EntityId)) {
            $removed = @($Graph.Out[$EntityId] | Where-Object { $_.type -eq 'memberOf' -and $_.to -eq $GroupId })
        }
        foreach ($e in $removed) {
            [void]$Graph.Out[$EntityId].Remove($e)
            if ($Graph.In.ContainsKey($GroupId)) { [void]$Graph.In[$GroupId].Remove($e) }
        }
        try { $after = Resolve-IgEffectiveAssignments -Graph $Graph -EntityId $EntityId }
        finally {
            foreach ($e in $removed) {
                $Graph.Out[$EntityId].Add($e)
                if (-not $Graph.In.ContainsKey($GroupId)) { $Graph.In[$GroupId] = New-Object System.Collections.Generic.List[object] }
                $Graph.In[$GroupId].Add($e)
            }
        }
    }
    return (Get-IgAssignmentDiff -Before $before -After $after)
}

function Resolve-IgMcpPath {
    <#
        Explain the relationship between two nodes, picking the most informative
        framing available: workload-to-entity (why it applies), entity-to-group
        (the nesting chain), entity-to-entity (shared groups), and an undirected
        BFS fallback so an odd pairing still gets a useful answer.
    #>
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$FromId,
        [Parameter(Mandatory)][string]$ToId
    )
    $workloadTypes = @('ConfigPolicy', 'CompliancePolicy', 'App', 'Script')
    $entityTypes = @('Device', 'User', 'Group')
    $fromNode = $Graph.Nodes[$FromId]
    $toNode = $Graph.Nodes[$ToId]

    if ($FromId -ieq $ToId) {
        return @{ Text = "'$($fromNode.name)' is the same node as '$($toNode.name)'."; Data = [ordered]@{ connected = $true; kind = 'same' } }
    }

    # --- Workload <-> entity: the "why does this apply" case ----------------------
    $workloadNode = $null; $entityNode = $null
    if ($workloadTypes -contains $fromNode.type -and $entityTypes -contains $toNode.type) { $workloadNode = $fromNode; $entityNode = $toNode }
    elseif ($workloadTypes -contains $toNode.type -and $entityTypes -contains $fromNode.type) { $workloadNode = $toNode; $entityNode = $fromNode }

    if ($workloadNode) {
        $records = Resolve-IgEffectiveAssignments -Graph $Graph -EntityId $entityNode.id
        $hit = @($records | Where-Object { $_.WorkloadId -eq $workloadNode.id }) | Select-Object -First 1
        if (-not $hit) {
            return @{
                Text = "'$($workloadNode.name)' does not reach '$($entityNode.name)'. No assignment targets it directly, through group nesting, or through All Devices / All Users."
                Data = [ordered]@{ connected = $false; kind = 'assignment'; workload = $workloadNode.name; entity = $entityNode.name }
            }
        }
        $filterName = ''
        if ($hit.FilterId -and $Graph.Nodes.ContainsKey($hit.FilterId)) { $filterName = $Graph.Nodes[$hit.FilterId].name }

        $lines = New-Object System.Collections.Generic.List[string]
        [void]$lines.Add("'$($workloadNode.name)' ($($workloadNode.type)) -> '$($entityNode.name)' ($($entityNode.type))")
        [void]$lines.Add('')
        [void]$lines.Add("  Status: $($hit.Status)")
        if ($hit.Intent) { [void]$lines.Add("  Intent: $($hit.Intent)") }
        [void]$lines.Add("  Mode:   $($hit.Mode)")
        [void]$lines.Add("  Via:    $($hit.Via)")
        if ($filterName) { [void]$lines.Add("  Filter: $filterName ($($hit.FilterMode))") }
        [void]$lines.Add('')
        if ($hit.Status -eq 'Excluded') {
            [void]$lines.Add("The assignment is an exclusion, and an exclusion always wins - so this does NOT apply.")
        }
        elseif ($hit.Status -eq 'AppliesPreFilter') {
            [void]$lines.Add("It applies before the assignment filter is evaluated. The filter decides the final outcome on the device itself, which a snapshot cannot determine.")
        }
        else {
            [void]$lines.Add("It applies. The Via chain is the exact group path that causes it.")
        }
        return @{
            Text = ($lines -join "`n")
            Data = [ordered]@{
                connected = $true; kind = 'assignment'
                workload = $workloadNode.name; workloadType = $workloadNode.type
                entity = $entityNode.name; entityType = $entityNode.type
                status = $hit.Status; intent = [string]$hit.Intent; mode = $hit.Mode
                via = $hit.Via; filter = $filterName
            }
        }
    }

    # --- Entity -> containing group: the nesting chain ----------------------------
    if ($entityTypes -contains $fromNode.type -and $toNode.type -eq 'Group') {
        $up = Resolve-IgGroupClosure -Graph $Graph -EntityId $FromId -Direction Up
        if ($up.ContainsKey($ToId)) {
            $path = Format-IgMcpNodePath -Graph $Graph -Path $up[$ToId]
            $hops = @($up[$ToId]).Count - 1
            return @{
                Text = "'$($fromNode.name)' is a member of '$($toNode.name)' through $hops hop(s):`n`n  $path"
                Data = [ordered]@{ connected = $true; kind = 'membership'; hops = $hops; via = $path }
            }
        }
    }

    # --- Two entities: what they have in common -----------------------------------
    if ($entityTypes -contains $fromNode.type -and $entityTypes -contains $toNode.type) {
        $upFrom = Resolve-IgGroupClosure -Graph $Graph -EntityId $FromId -Direction Up
        $upTo = Resolve-IgGroupClosure -Graph $Graph -EntityId $ToId -Direction Up
        $shared = @($upFrom.Keys | Where-Object { $upTo.ContainsKey($_) })
        if ($shared.Count -gt 0) {
            $rows = New-Object System.Collections.Generic.List[object]
            foreach ($gid in ($shared | Sort-Object { $Graph.Nodes[$_].name })) {
                [void]$rows.Add([pscustomobject]@{
                    Group        = $Graph.Nodes[$gid].name
                    "From $($fromNode.name)" = (Format-IgMcpNodePath -Graph $Graph -Path $upFrom[$gid])
                    "From $($toNode.name)"   = (Format-IgMcpNodePath -Graph $Graph -Path $upTo[$gid])
                })
            }
            $rowArray = ConvertTo-IgMcpJsonArray $rows
            return @{
                Text = "'$($fromNode.name)' and '$($toNode.name)' share $($rowArray.Count) group(s).`n`n" +
                       (Format-IgMcpTable -Rows $rowArray -Columns @('Group', "From $($fromNode.name)", "From $($toNode.name)"))
                Data = [ordered]@{ connected = $true; kind = 'sharedGroups'; count = $rowArray.Count; groups = @($shared | ForEach-Object { $Graph.Nodes[$_].name }) }
            }
        }
    }

    # --- Fallback: undirected BFS over the raw edges ------------------------------
    $hops = Find-IgMcpConnection -Graph $Graph -FromId $FromId -ToId $ToId
    if (-not $hops) {
        return @{
            Text = "No relationship found between '$($fromNode.name)' and '$($toNode.name)' within 6 hops."
            Data = [ordered]@{ connected = $false; kind = 'none' }
        }
    }
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("'$($fromNode.name)' -> '$($toNode.name)' in $($hops.Count) hop(s):")
    [void]$lines.Add('')
    foreach ($h in $hops) {
        [void]$lines.Add("  $($Graph.Nodes[$h.From].name)  --$($h.Type)-->  $($Graph.Nodes[$h.To].name)")
    }
    return @{
        Text = ($lines -join "`n")
        Data = [ordered]@{ connected = $true; kind = 'graphPath'; hops = $hops.Count }
    }
}

function Find-IgMcpConnection {
    <#
        Undirected, depth-capped BFS between two nodes. Returns the hop list
        (From/To/Type per hop, in traversal order) or $null when unreachable.
    #>
    param(
        [Parameter(Mandatory)]$Graph,
        [Parameter(Mandatory)][string]$FromId,
        [Parameter(Mandatory)][string]$ToId,
        [int]$MaxDepth = 6
    )
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    [void]$visited.Add($FromId)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([pscustomobject]@{ Id = $FromId; Hops = @() })

    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        if (@($cur.Hops).Count -ge $MaxDepth) { continue }

        foreach ($e in (Get-IgOutEdges -Graph $Graph -NodeId $cur.Id)) {
            if (-not $visited.Add($e.to)) { continue }
            $hops = @($cur.Hops) + [pscustomobject]@{ From = $e.from; To = $e.to; Type = $e.type }
            if ($e.to -ieq $ToId) { return $hops }
            $queue.Enqueue([pscustomobject]@{ Id = $e.to; Hops = $hops })
        }
        foreach ($e in (Get-IgInEdges -Graph $Graph -NodeId $cur.Id)) {
            if (-not $visited.Add($e.from)) { continue }
            $hops = @($cur.Hops) + [pscustomobject]@{ From = $e.to; To = $e.from; Type = $e.type }
            if ($e.from -ieq $ToId) { return $hops }
            $queue.Enqueue([pscustomobject]@{ Id = $e.from; Hops = $hops })
        }
    }
    return $null
}

# --- JSON-RPC envelopes -------------------------------------------------------------

function New-IgMcpResult {
    param($Id, [Parameter(Mandatory)]$Result)
    [ordered]@{ jsonrpc = '2.0'; id = $Id; result = $Result }
}

function New-IgMcpError {
    param($Id, [Parameter(Mandatory)][int]$Code, [Parameter(Mandatory)][string]$Message, $Data)
    $err = [ordered]@{ code = $Code; message = $Message }
    if ($null -ne $Data) { $err['data'] = $Data }
    [ordered]@{ jsonrpc = '2.0'; id = $Id; error = $err }
}

function New-IgMcpToolError {
    <#
        A failing TOOL is reported as a successful JSON-RPC result carrying
        isError:true, not as a protocol error. That distinction matters: a JSON-RPC
        error aborts the client's turn, while an isError result is handed to the
        model, which can read it and retry - for example after the ambiguous-identity
        message from Resolve-IgNodeIdentity.
    #>
    param($Id, [Parameter(Mandatory)][string]$Text)
    New-IgMcpResult -Id $Id -Result ([ordered]@{
        content = [object[]]@( [ordered]@{ type = 'text'; text = $Text } )
        isError = $true
    })
}

# --- Tools ---------------------------------------------------------------------------

function Get-IgMcpToolDescriptors {
    <# The registry projected into the tools/list wire shape. #>
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($name in $script:IgMcpTools.Keys) {
        $tool = $script:IgMcpTools[$name]
        [void]$list.Add([ordered]@{
            name        = $name
            description = $tool.Description
            inputSchema = (& $tool.Schema)
        })
    }
    return (ConvertTo-IgMcpJsonArray $list)
}

function Invoke-IgMcpToolCall {
    param($State, $Id, $Params)
    $name = [string](Get-IgProp $Params 'name')
    if (-not $script:IgMcpTools.Contains($name)) {
        return (New-IgMcpToolError -Id $Id -Text "Unknown tool '$name'. Available tools: $(($script:IgMcpTools.Keys) -join ', ').")
    }
    $arguments = Get-IgProp $Params 'arguments'
    try {
        $graph = Get-IgMcpGraph -State $State
        $out = & $script:IgMcpTools[$name].Handler $graph $arguments
        $result = [ordered]@{
            content = [object[]]@( [ordered]@{ type = 'text'; text = [string]$out.Text } )
            isError = $false
        }
        if ($null -ne $out.Data) { $result['structuredContent'] = $out.Data }
        return (New-IgMcpResult -Id $Id -Result $result)
    }
    catch {
        Write-IgMcpLog "tool '$name' failed: $($_.Exception.Message)"
        return (New-IgMcpToolError -Id $Id -Text "Error: $($_.Exception.Message)")
    }
}

function Get-IgMcpGraph {
    <#
        Return the loaded graph, reloading only when graph.json changed on disk so an
        admin can re-run Export-IntuneGraph mid-conversation. A failed reload keeps
        the previous good graph: a half-written file must not take the server down.
    #>
    param($State)
    $path = Get-IgProp $State 'Path'
    if ($path) {
        try {
            $stamp = (Get-Item -LiteralPath $path -ErrorAction Stop).LastWriteTimeUtc
            if ($stamp -ne $State.LoadedAt) {
                Write-IgMcpLog 'graph.json changed on disk; reloading.' -Always
                $State.Graph = ConvertFrom-IgGraphJson -Path $path 3>$null
                $State.LoadedAt = $stamp
            }
        }
        catch {
            Write-IgMcpLog "reload failed, keeping the previously loaded graph: $($_.Exception.Message)" -Always
        }
    }
    return $State.Graph
}

# --- Dispatch --------------------------------------------------------------------------

function Invoke-IgMcpRequest {
    <#
        PURE: takes one parsed JSON-RPC object, returns a response object, or $null
        for a notification (which must produce no output at all). Performs no I/O,
        which is what makes the whole protocol unit-testable without a client.
    #>
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Request
    )
    if ($Request -isnot [psobject] -or $Request -is [System.Array]) {
        return (New-IgMcpError -Id $null -Code -32600 -Message 'Invalid Request')
    }

    $method = [string](Get-IgProp $Request 'method')
    # Presence, not truthiness: id 0 and id "" are valid request ids but falsy in
    # PowerShell, and treating them as notifications would silently drop the reply.
    $hasId = $null -ne $Request.PSObject.Properties['id']
    $id = Get-IgProp $Request 'id'

    if ([string]::IsNullOrWhiteSpace($method)) {
        if (-not $hasId) { return $null }
        return (New-IgMcpError -Id $id -Code -32600 -Message 'Invalid Request: no method.')
    }

    # Notifications never get a response - not even an error for an unknown method.
    if (-not $hasId) {
        switch ($method) {
            'notifications/initialized' { $State.Initialized = $true }
            default { Write-IgMcpLog "ignoring notification '$method'." }
        }
        return $null
    }

    $params = Get-IgProp $Request 'params'

    # Modern era is detected ONLY by the protocolVersion key inside _meta. Gating on
    # _meta alone would misroute legacy clients, which put progress tokens there.
    $requestedModern = [string](Get-IgProp (Get-IgProp $Request '_meta') 'io.modelcontextprotocol/protocolVersion')
    if ($requestedModern -and ($script:IgMcpModernVersions -notcontains $requestedModern)) {
        return (New-IgMcpError -Id $id -Code -32022 -Message 'Unsupported protocol version' -Data ([ordered]@{
            supported = [object[]]($script:IgMcpModernVersions + $script:IgMcpLegacyVersions)
            requested = $requestedModern
        }))
    }

    switch ($method) {
        'initialize' {
            $requested = [string](Get-IgProp $params 'protocolVersion')
            $chosen = $script:IgMcpDefaultVersion
            if ($script:IgMcpLegacyVersions -contains $requested) { $chosen = $requested }
            $State.Initialized = $true
            $State.Era = 'legacy'
            $State.NegotiatedVersion = $chosen
            return (New-IgMcpResult -Id $id -Result ([ordered]@{
                protocolVersion = $chosen
                capabilities    = [ordered]@{ tools = @{} }
                serverInfo      = [ordered]@{ name = $script:IgMcpServerName; version = $script:IgMcpServerVersion }
                instructions    = $script:IgMcpInstructions
            }))
        }
        'server/discover' {
            $State.Era = 'modern'
            return (New-IgMcpResult -Id $id -Result ([ordered]@{
                resultType        = 'complete'
                supportedVersions = [object[]]($script:IgMcpModernVersions + $script:IgMcpLegacyVersions)
                capabilities      = [ordered]@{ tools = @{} }
                instructions      = $script:IgMcpInstructions
                _meta             = @{ 'io.modelcontextprotocol/serverInfo' = [ordered]@{
                                          name = $script:IgMcpServerName; version = $script:IgMcpServerVersion } }
            }))
        }
        'tools/list' {
            return (New-IgMcpResult -Id $id -Result ([ordered]@{ tools = (Get-IgMcpToolDescriptors) }))
        }
        'tools/call' {
            return (Invoke-IgMcpToolCall -State $State -Id $id -Params $params)
        }
        'ping' {
            return (New-IgMcpResult -Id $id -Result @{})
        }
        default {
            return (New-IgMcpError -Id $id -Code -32601 -Message "Method not found: $method")
        }
    }
}

# --- Transport --------------------------------------------------------------------------

function New-IgMcpState {
    <# The server's mutable state. A plain hashtable so tests can build one directly. #>
    param($Graph, [string]$Path)
    $loadedAt = $null
    if ($Path -and (Test-Path -LiteralPath $Path)) { $loadedAt = (Get-Item -LiteralPath $Path).LastWriteTimeUtc }
    @{
        Graph             = $Graph
        Path              = $Path
        LoadedAt          = $loadedAt
        Initialized       = $false
        Era               = 'legacy'
        NegotiatedVersion = $null
    }
}

function Write-IgMcpMessage {
    <# One message, one line, LF-terminated, flushed immediately. #>
    param(
        [Parameter(Mandatory)][System.IO.TextWriter]$Writer,
        [Parameter(Mandatory)]$Message
    )
    # -InputObject, not the pipeline: at the top level the pipeline unrolls a
    # one-element array back into a scalar, which would break a JSON-RPC batch reply.
    $json = ConvertTo-Json -InputObject $Message -Depth 20 -Compress
    if ($json -match "[`r`n]") {
        # -Compress escapes CR/LF inside strings, so this is unreachable - but one bad
        # line would poison the whole session, so fail loudly rather than emit it.
        Write-IgMcpLog 'FATAL: serialized message contained a raw newline; dropped.' -Always
        return
    }
    $Writer.Write($json + "`n")
    $Writer.Flush()
}

function Invoke-IgMcpLoop {
    <#
        The transport loop. Reader and Writer are injected rather than opened here so
        the tests can drive this exact code path with a StringReader/StringWriter -
        no child process, no console handle, identical parse/dispatch/serialize path.
    #>
    param(
        [Parameter(Mandatory)][System.IO.TextReader]$Reader,
        [Parameter(Mandatory)][System.IO.TextWriter]$Writer,
        [Parameter(Mandatory)]$State
    )
    while ($true) {
        $line = $Reader.ReadLine()
        if ($null -eq $line) { Write-IgMcpLog 'stdin closed; exiting.'; break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parsed = $null
        try { $parsed = $line | ConvertFrom-Json -ErrorAction Stop }
        catch {
            Write-IgMcpMessage -Writer $Writer -Message (New-IgMcpError -Id $null -Code -32700 -Message 'Parse error')
            continue
        }

        if ($parsed -is [System.Array]) {
            $batch = New-Object System.Collections.Generic.List[object]
            foreach ($item in $parsed) {
                $r = Invoke-IgMcpRequest -State $State -Request $item 3>$null 4>$null 5>$null 6>$null
                if ($null -ne $r) { [void]$batch.Add($r) }
            }
            if ($batch.Count -gt 0) { Write-IgMcpMessage -Writer $Writer -Message (ConvertTo-IgArray $batch) }
            continue
        }

        # Assigning consumes the success stream, so a stray emission lands here rather
        # than on stdout; 6>$null is the one that matters (Write-Host writes to stdout).
        $response = Invoke-IgMcpRequest -State $State -Request $parsed 3>$null 4>$null 5>$null 6>$null
        if ($null -ne $response) { Write-IgMcpMessage -Writer $Writer -Message $response }
    }
}
