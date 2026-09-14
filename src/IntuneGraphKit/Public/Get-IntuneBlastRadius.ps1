function Get-IntuneBlastRadius {
    <#
    .SYNOPSIS
        Preview the impact of a group before you change it.
    .DESCRIPTION
        Feature 2. Reports every workload that reaches members of a group (directly
        or through group nesting), what stops applying via exclusions, and the
        group's transitive member counts. With -WhatIfAddMember / -WhatIfRemoveMember
        it simulates a membership change and returns the exact workloads gained/lost.
    .EXAMPLE
        Get-IntuneBlastRadius -Group SG-Finance
    .EXAMPLE
        Get-IntuneBlastRadius -Group SG-Finance -WhatIfAddMember KIOSK-01
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Group,
        [string]$WhatIfAddMember,
        [string]$WhatIfRemoveMember,
        $Graph,
        [string]$Path
    )
    if ($WhatIfAddMember -and $WhatIfRemoveMember) {
        throw "Specify only one of -WhatIfAddMember / -WhatIfRemoveMember."
    }
    $g = Get-IgWorkingGraph -Graph $Graph -Path $Path
    $groupId = Resolve-IgNodeIdentity -Graph $g -Identity $Group -Type 'Group'
    $groupName = $g.Nodes[$groupId].name

    # --- What-if simulation --------------------------------------------------
    if ($WhatIfAddMember -or $WhatIfRemoveMember) {
        $ident = if ($WhatIfAddMember) { $WhatIfAddMember } else { $WhatIfRemoveMember }
        $entityId = Resolve-IgNodeIdentity -Graph $g -Identity $ident
        $before = Resolve-IgEffectiveAssignments -Graph $g -EntityId $entityId

        if ($WhatIfAddMember) {
            $tmp = [pscustomobject]@{ id = 'tmp-whatif'; type = 'memberOf'; from = $entityId; to = $groupId; properties = @{} }
            if (-not $g.Out.ContainsKey($entityId)) { $g.Out[$entityId] = New-Object System.Collections.Generic.List[object] }
            if (-not $g.In.ContainsKey($groupId)) { $g.In[$groupId] = New-Object System.Collections.Generic.List[object] }
            $g.Out[$entityId].Add($tmp); $g.In[$groupId].Add($tmp)
            try { $after = Resolve-IgEffectiveAssignments -Graph $g -EntityId $entityId }
            finally { [void]$g.Out[$entityId].Remove($tmp); [void]$g.In[$groupId].Remove($tmp) }
        }
        else {
            $removed = @()
            if ($g.Out.ContainsKey($entityId)) {
                $removed = @($g.Out[$entityId] | Where-Object { $_.type -eq 'memberOf' -and $_.to -eq $groupId })
            }
            if ($removed.Count -eq 0) { Write-Warning "$ident is not a direct member of $groupName; nothing to remove." }
            foreach ($e in $removed) { [void]$g.Out[$entityId].Remove($e); if ($g.In.ContainsKey($groupId)) { [void]$g.In[$groupId].Remove($e) } }
            try { $after = Resolve-IgEffectiveAssignments -Graph $g -EntityId $entityId }
            finally { foreach ($e in $removed) { $g.Out[$entityId].Add($e); if (-not $g.In.ContainsKey($groupId)) { $g.In[$groupId] = New-Object System.Collections.Generic.List[object] }; $g.In[$groupId].Add($e) } }
        }

        $diff = Get-IgAssignmentDiff -Before $before -After $after
        $action = if ($WhatIfAddMember) { "Adding '$ident' to" } else { "Removing '$ident' from" }
        Write-Host ""
        Write-Host "$action '$groupName':" -ForegroundColor Cyan
        Write-Host ("  Gains {0} workload(s), loses {1}." -f @($diff.Gains).Count, @($diff.Loses).Count)
        Write-Host ""
        return [pscustomobject]@{
            PSTypeName = 'IntuneGraph.WhatIf'
            Group      = $groupName
            Entity     = $g.Nodes[$entityId].name
            Action     = if ($WhatIfAddMember) { 'AddMember' } else { 'RemoveMember' }
            Gains      = $diff.Gains
            Loses      = $diff.Loses
        }
    }

    # --- Base report ---------------------------------------------------------
    $records = Resolve-IgEffectiveAssignments -Graph $g -EntityId $groupId
    $applies = @($records | Where-Object { $_.Status -eq 'Applies' -or $_.Status -eq 'AppliesPreFilter' })
    $removes = @($records | Where-Object { $_.Status -eq 'Excluded' })

    $down = Resolve-IgGroupClosure -Graph $g -EntityId $groupId -Direction Down
    $devices = @($down.Keys | Where-Object { $g.Nodes[$_].type -eq 'Device' })
    $users = @($down.Keys | Where-Object { $g.Nodes[$_].type -eq 'User' })
    $nested = @($down.Keys | Where-Object { $g.Nodes[$_].type -eq 'Group' })

    Write-Host ""
    Write-Host "Blast radius: $groupName" -ForegroundColor Cyan
    Write-Host ("  Applies {0} workload(s); removes {1} via exclusion." -f $applies.Count, $removes.Count)
    Write-Host ("  Reach: {0} device(s), {1} user(s), {2} nested group(s)." -f $devices.Count, $users.Count, $nested.Count)
    Write-Host ""

    [pscustomobject]@{
        PSTypeName          = 'IntuneGraph.BlastRadius'
        Group               = $groupName
        Applies             = @($applies | Select-Object Workload, Type, Status, Via)
        RemovesViaExclusion = @($removes | Select-Object Workload, Type, Via)
        MemberCounts        = [pscustomobject]@{ Devices = $devices.Count; Users = $users.Count; NestedGroups = $nested.Count }
    }
}
