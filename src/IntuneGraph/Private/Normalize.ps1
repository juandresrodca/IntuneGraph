# Normalization: raw Graph objects -> canonical IntuneGraph nodes and edges.
# Node id carries a type prefix so the type is readable in every edge and id
# collisions across Graph collections are impossible.

function New-IgNode {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Type,
        [string]$Name,
        [string]$SourceId,
        [string]$Subtype,
        [hashtable]$Properties
    )
    if (-not $Properties) { $Properties = @{} }
    [pscustomobject]@{
        id         = $Id
        type       = $Type
        subtype    = $Subtype
        name       = $Name
        sourceId   = $SourceId
        properties = $Properties
    }
}

function ConvertTo-IgWorkloadNode {
    <# Config policies, compliance policies, apps, scripts, filters -> node. #>
    param(
        [Parameter(Mandatory)]$Raw,
        [Parameter(Mandatory)][ValidateSet('ConfigPolicy', 'CompliancePolicy', 'App', 'Script', 'Filter')][string]$Kind
    )
    $sid = [string](Get-IgProp $Raw 'id')
    switch ($Kind) {
        'ConfigPolicy' {
            $name = Get-IgProp $Raw 'name'
            if (-not $name) { $name = Get-IgProp $Raw 'displayName' }
            $odata = ConvertTo-IgShortType ([string](Get-IgProp $Raw '@odata.type'))
            $subtype = if ($odata) { 'deviceConfiguration' } else { 'settingsCatalog' }
            return New-IgNode -Id "cfg-$sid" -Type 'ConfigPolicy' -Name $name -SourceId $sid -Subtype $subtype -Properties @{
                platforms          = Get-IgProp $Raw 'platforms'
                technologies       = Get-IgProp $Raw 'technologies'
                odataType          = $odata
                createdDateTime    = Get-IgProp $Raw 'createdDateTime'
                lastModifiedDateTime = Get-IgProp $Raw 'lastModifiedDateTime'
            }
        }
        'CompliancePolicy' {
            return New-IgNode -Id "cmp-$sid" -Type 'CompliancePolicy' -Name (Get-IgProp $Raw 'displayName') -SourceId $sid -Subtype (ConvertTo-IgShortType ([string](Get-IgProp $Raw '@odata.type'))) -Properties @{
                createdDateTime      = Get-IgProp $Raw 'createdDateTime'
                lastModifiedDateTime = Get-IgProp $Raw 'lastModifiedDateTime'
            }
        }
        'App' {
            return New-IgNode -Id "app-$sid" -Type 'App' -Name (Get-IgProp $Raw 'displayName') -SourceId $sid -Subtype (ConvertTo-IgShortType ([string](Get-IgProp $Raw '@odata.type'))) -Properties @{
                publisher = Get-IgProp $Raw 'publisher'
            }
        }
        'Script' {
            $odata = [string](Get-IgProp $Raw '@odata.type')
            $subtype = if ($odata -match 'deviceHealthScript') { 'remediationScript' } else { 'platformScript' }
            return New-IgNode -Id "scr-$sid" -Type 'Script' -Name (Get-IgProp $Raw 'displayName') -SourceId $sid -Subtype $subtype -Properties @{}
        }
        'Filter' {
            return New-IgNode -Id "flt-$sid" -Type 'Filter' -Name (Get-IgProp $Raw 'displayName') -SourceId $sid -Subtype 'assignmentFilter' -Properties @{
                platform = Get-IgProp $Raw 'platform'
                rule     = Get-IgProp $Raw 'rule'
            }
        }
    }
}

function ConvertTo-IgGroupNode {
    param([Parameter(Mandatory)]$Raw)
    $sid = [string](Get-IgProp $Raw 'id')
    $groupTypes = Get-IgProp $Raw 'groupTypes'
    $isM365 = $false
    if ($groupTypes) { $isM365 = @($groupTypes) -contains 'Unified' }
    $rule = Get-IgProp $Raw 'membershipRule'
    $membershipType = if ($rule) { 'dynamic' } else { 'assigned' }
    New-IgNode -Id "grp-$sid" -Type 'Group' -Name (Get-IgProp $Raw 'displayName') -SourceId $sid -Subtype ($(if ($isM365) { 'm365' } else { 'security' })) -Properties @{
        membershipType = $membershipType
        dynamicRule    = $rule
    }
}

function ConvertTo-IgMemberNode {
    <# A group-member directory object (user/device/group) -> node. #>
    param([Parameter(Mandatory)]$Raw)
    $sid = [string](Get-IgProp $Raw 'id')
    $odata = [string](Get-IgProp $Raw '@odata.type')
    if ($odata -match 'device') {
        return New-IgNode -Id "dev-$sid" -Type 'Device' -Name (Get-IgProp $Raw 'displayName') -SourceId $sid -Properties @{
            operatingSystem = Get-IgProp $Raw 'operatingSystem'
            aadDeviceId     = Get-IgProp $Raw 'deviceId'
        }
    }
    elseif ($odata -match 'group') {
        return $null  # nested groups are already nodes from the groups collection
    }
    else {
        return New-IgNode -Id "usr-$sid" -Type 'User' -Name (Get-IgProp $Raw 'displayName') -SourceId $sid -Properties @{
            userPrincipalName = Get-IgProp $Raw 'userPrincipalName'
        }
    }
}

function Resolve-IgAssignmentTarget {
    <#
        Decode an assignment object's .target into a canonical target descriptor:
        { targetNodeId, mode (include|exclude), filterId, filterMode }.
        Returns $null when the target type is unrecognized.
    #>
    param([Parameter(Mandatory)]$Assignment)
    $target = Get-IgProp $Assignment 'target'
    if (-not $target) { return $null }
    $odata = [string](Get-IgProp $target '@odata.type')

    $filterId = Get-IgProp $target 'deviceAndAppManagementAssignmentFilterId'
    $filterMode = Get-IgProp $target 'deviceAndAppManagementAssignmentFilterType'
    if ($filterMode -eq 'none') { $filterId = $null; $filterMode = $null }

    # NOTE: 'exclusionGroupAssignmentTarget' contains the substring
    # 'groupAssignmentTarget', so with switch -Regex every 'break' below is
    # required - otherwise both cases run and include overwrites exclude.
    $mode = 'include'
    $targetNodeId = $null
    switch -Regex ($odata) {
        'allDevicesAssignmentTarget'        { $targetNodeId = 'builtin-allDevices'; $mode = 'include'; break }
        'allLicensedUsersAssignmentTarget'  { $targetNodeId = 'builtin-allUsers';   $mode = 'include'; break }
        'exclusionGroupAssignmentTarget'    { $targetNodeId = 'grp-' + [string](Get-IgProp $target 'groupId'); $mode = 'exclude'; break }
        'groupAssignmentTarget'             { $targetNodeId = 'grp-' + [string](Get-IgProp $target 'groupId'); $mode = 'include'; break }
        default {
            $gid = Get-IgProp $target 'groupId'
            if ($gid) { $targetNodeId = "grp-$gid" } else { return $null }
        }
    }

    [pscustomobject]@{
        targetNodeId = $targetNodeId
        mode         = $mode
        filterId     = if ($filterId) { "flt-$filterId" } else { $null }
        filterMode   = $filterMode
    }
}

function ConvertTo-IgAssignmentEdges {
    <#
        Turn a workload node's raw assignments into assignedTo (+ filteredBy) edges.
        $HasIntent adds the app assignment intent to edge properties.
    #>
    param(
        [Parameter(Mandatory)][string]$FromId,
        $Assignments,
        [switch]$HasIntent
    )
    $edges = New-Object System.Collections.Generic.List[object]
    if (-not $Assignments) { return $edges }

    foreach ($a in @($Assignments)) {
        $t = Resolve-IgAssignmentTarget -Assignment $a
        if (-not $t) { continue }
        $intent = $null
        if ($HasIntent) { $intent = Get-IgProp $a 'intent' }

        [void]$edges.Add([pscustomobject]@{
            type       = 'assignedTo'
            from       = $FromId
            to         = $t.targetNodeId
            properties = @{
                mode         = $t.mode
                assignmentId = Get-IgProp $a 'id'
                intent       = $intent
                filterId     = $t.filterId
                filterMode   = $t.filterMode
            }
        })

        if ($t.filterId) {
            [void]$edges.Add([pscustomobject]@{
                type       = 'filteredBy'
                from       = $FromId
                to         = $t.filterId
                properties = @{
                    viaAssignmentId = Get-IgProp $a 'id'
                    filterMode      = $t.filterMode
                    appliedOnTarget = $t.targetNodeId
                }
            })
        }
    }
    return $edges
}
