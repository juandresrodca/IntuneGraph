function Export-IntuneGraph {
    <#
    .SYNOPSIS
        Fetch Intune configuration and build the relationship graph (graph.json).
    .DESCRIPTION
        The one command that reads from Microsoft Graph. Fetches configuration
        profiles, compliance policies, apps, scripts, assignment filters, groups,
        members and devices; normalizes them into a node/edge graph; and writes
        graph.json (optionally an interactive HTML report too).

        Use -DemoData to run against the bundled Contoso dataset with zero tenant
        access, or -FromFixtures <path> to point at your own fixture directory.
    .EXAMPLE
        Export-IntuneGraph -DemoData -Html -PassThru | Show-IntuneGraph -Open
    .EXAMPLE
        Connect-IntuneGraph
        Export-IntuneGraph -OutputPath .\contoso\graph.json
    #>
    [CmdletBinding(DefaultParameterSetName = 'Live')]
    param(
        [string]$OutputPath,
        [Parameter(ParameterSetName = 'Fixtures', Mandatory)][string]$FromFixtures,
        [Parameter(ParameterSetName = 'Demo', Mandatory)][switch]$DemoData,
        [switch]$SkipDevices,
        [switch]$Html,
        [switch]$PassThru
    )

    # --- Resolve data source / session mode -------------------------------------
    $priorMode = $script:IgSession.Mode
    $priorRoot = $script:IgSession.FixtureRoot
    $source = 'live'
    try {
        if ($DemoData) {
            $script:IgSession.Mode = 'Fixture'
            $script:IgSession.FixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\DemoData'))
            $source = 'demo'
        }
        elseif ($FromFixtures) {
            $script:IgSession.Mode = 'Fixture'
            $script:IgSession.FixtureRoot = [System.IO.Path]::GetFullPath($FromFixtures)
            $source = 'fixture'
        }
        else {
            Assert-IgConnection
        }

        # --- Read tenant metadata (fixture manifest if present) -----------------
        $tenantId = $script:IgSession.TenantId
        $tenantName = $null
        if ($script:IgSession.Mode -eq 'Fixture') {
            $manifest = Join-Path $script:IgSession.FixtureRoot 'manifest.json'
            if (Test-Path $manifest) {
                $m = Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
                $tenantId = Get-IgProp $m 'tenantId'
                $tenantName = Get-IgProp $m 'tenantName'
            }
        }

        $nodes = New-Object System.Collections.Generic.List[object]
        $edges = New-Object System.Collections.Generic.List[object]
        $addNode = { param($n) if ($n) { [void]$nodes.Add($n) } }
        $addEdges = { param($es) foreach ($e in (ConvertTo-IgArray $es)) { [void]$edges.Add($e) } }

        # --- Workloads ----------------------------------------------------------
        Write-Progress -Activity 'IntuneGraph export' -Status 'Configuration policies' -PercentComplete 5
        foreach ($p in @(Get-IgRawConfigurationPolicies)) {
            $node = ConvertTo-IgWorkloadNode -Raw $p -Kind ConfigPolicy
            & $addNode $node
            & $addEdges (ConvertTo-IgAssignmentEdges -FromId $node.id -Assignments (Get-IgProp $p 'assignments'))
        }
        Write-Progress -Activity 'IntuneGraph export' -Status 'Legacy device configurations' -PercentComplete 15
        foreach ($p in @(Get-IgRawDeviceConfigurations)) {
            $node = ConvertTo-IgWorkloadNode -Raw $p -Kind ConfigPolicy
            & $addNode $node
            & $addEdges (ConvertTo-IgAssignmentEdges -FromId $node.id -Assignments (Get-IgProp $p 'assignments'))
        }
        Write-Progress -Activity 'IntuneGraph export' -Status 'Compliance policies' -PercentComplete 25
        foreach ($p in @(Get-IgRawCompliancePolicies)) {
            $node = ConvertTo-IgWorkloadNode -Raw $p -Kind CompliancePolicy
            & $addNode $node
            & $addEdges (ConvertTo-IgAssignmentEdges -FromId $node.id -Assignments (Get-IgProp $p 'assignments'))
        }
        Write-Progress -Activity 'IntuneGraph export' -Status 'Apps' -PercentComplete 35
        foreach ($p in @(Get-IgRawMobileApps)) {
            $node = ConvertTo-IgWorkloadNode -Raw $p -Kind App
            & $addNode $node
            & $addEdges (ConvertTo-IgAssignmentEdges -FromId $node.id -Assignments (Get-IgProp $p 'assignments') -HasIntent)
        }
        Write-Progress -Activity 'IntuneGraph export' -Status 'Scripts and remediations' -PercentComplete 45
        foreach ($p in @(Get-IgRawPlatformScripts) + @(Get-IgRawRemediationScripts)) {
            $node = ConvertTo-IgWorkloadNode -Raw $p -Kind Script
            & $addNode $node
            & $addEdges (ConvertTo-IgAssignmentEdges -FromId $node.id -Assignments (Get-IgProp $p 'assignments'))
        }
        Write-Progress -Activity 'IntuneGraph export' -Status 'Assignment filters' -PercentComplete 55
        foreach ($f in @(Get-IgRawAssignmentFilters)) {
            & $addNode (ConvertTo-IgWorkloadNode -Raw $f -Kind Filter)
        }

        # --- Groups + members ---------------------------------------------------
        Write-Progress -Activity 'IntuneGraph export' -Status 'Groups' -PercentComplete 65
        $groups = @(Get-IgRawGroups)
        foreach ($g in $groups) { & $addNode (ConvertTo-IgGroupNode -Raw $g) }

        Write-Progress -Activity 'IntuneGraph export' -Status 'Group members' -PercentComplete 75
        $deviceByAad = @{}
        foreach ($g in $groups) {
            $gid = [string](Get-IgProp $g 'id')
            $members = @(Get-IgRawGroupMembers -GroupId $gid)
            foreach ($mem in $members) {
                $memId = [string](Get-IgProp $mem 'id')
                $odata = [string](Get-IgProp $mem '@odata.type')
                $memNodeId = $null
                if ($odata -match 'group') { $memNodeId = "grp-$memId" }
                elseif ($odata -match 'device') {
                    $memNodeId = "dev-$memId"
                    $node = ConvertTo-IgMemberNode -Raw $mem
                    & $addNode $node
                    $aad = Get-IgProp $mem 'deviceId'
                    if ($aad) { $deviceByAad[[string]$aad] = $memNodeId }
                }
                else {
                    $memNodeId = "usr-$memId"
                    & $addNode (ConvertTo-IgMemberNode -Raw $mem)
                }
                & $addEdges (,([pscustomobject]@{ type = 'memberOf'; from = $memNodeId; to = "grp-$gid"; properties = @{} }))
            }
        }

        # --- Managed devices (enrich or add) ------------------------------------
        $deviceCount = 0
        if (-not $SkipDevices) {
            Write-Progress -Activity 'IntuneGraph export' -Status 'Managed devices' -PercentComplete 85
            $md = @(Get-IgRawManagedDevices)
            $deviceCount = $md.Count
            foreach ($d in $md) {
                $aad = [string](Get-IgProp $d 'azureADDeviceId')
                $props = @{
                    operatingSystem = Get-IgProp $d 'operatingSystem'
                    complianceState = Get-IgProp $d 'complianceState'
                    lastSyncDateTime = Get-IgProp $d 'lastSyncDateTime'
                    userPrincipalName = Get-IgProp $d 'userPrincipalName'
                    intuneDeviceName = Get-IgProp $d 'deviceName'
                    managed          = $true
                }
                if ($aad -and $deviceByAad.ContainsKey($aad)) {
                    # enrich existing member-derived device node
                    $existing = $nodes | Where-Object { $_.id -eq $deviceByAad[$aad] } | Select-Object -First 1
                    if ($existing) {
                        foreach ($k in $props.Keys) { if ($null -ne $props[$k]) { $existing.properties[$k] = $props[$k] } }
                    }
                }
                else {
                    $mdId = [string](Get-IgProp $d 'id')
                    & $addNode (New-IgNode -Id "dev-md-$mdId" -Type 'Device' -Name (Get-IgProp $d 'deviceName') -SourceId $mdId -Properties $props)
                }
            }
        }

        # --- Build graph --------------------------------------------------------
        Write-Progress -Activity 'IntuneGraph export' -Status 'Building graph' -PercentComplete 92
        $userCount = @($nodes | Where-Object { $_.type -eq 'User' }).Count
        if ($deviceCount -eq 0) { $deviceCount = @($nodes | Where-Object { $_.type -eq 'Device' }).Count }

        $metadata = [ordered]@{
            tenantId    = $tenantId
            tenantName  = $tenantName
            exportedAt  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            toolVersion = '0.1.0'
            source      = $source
            deviceCount = $deviceCount
            userCount   = $userCount
        }
        $graph = New-IgGraph -Metadata $metadata -Nodes $nodes -Edges $edges

        # --- Write outputs ------------------------------------------------------
        if (-not $OutputPath) {
            $tag = if ($tenantName) { $tenantName -replace '[^\w\-]', '' } else { $source }
            $stamp = (Get-Date).ToString('yyyyMMdd-HHmm')
            $OutputPath = Join-Path (Get-Location) ("IntuneGraph-$tag-$stamp\graph.json")
        }
        $outDir = Split-Path -Parent $OutputPath
        if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        ConvertTo-IgGraphJson -Graph $graph | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        Write-Progress -Activity 'IntuneGraph export' -Completed

        $script:IgSession.LastGraph = $graph

        if ($Html) {
            $htmlPath = [System.IO.Path]::ChangeExtension($OutputPath, '.html')
            New-IgHtmlReport -Graph $graph -Title ("IntuneGraph - " + ($(if ($tenantName) { $tenantName } else { $source }))) | Set-Content -LiteralPath $htmlPath -Encoding UTF8
            Write-Host "HTML report: $htmlPath" -ForegroundColor Cyan
        }

        # --- Summary ------------------------------------------------------------
        $counts = $graph.Metadata['counts']
        if (-not $counts) {
            $obj = ConvertTo-IgGraphObject -Graph $graph
            $counts = $obj.metadata.counts
        }
        Write-Host ""
        Write-Host "IntuneGraph export complete ($source)" -ForegroundColor Green
        Write-Host ("  Nodes: {0}   Edges: {1}" -f $graph.Nodes.Count, $graph.Edges.Count)
        Write-Host "  graph.json -> $OutputPath"
        Write-Host ""

        if ($PassThru) { return $graph }
    }
    finally {
        # Restore prior session mode (fixture calls are call-scoped).
        if ($DemoData -or $FromFixtures) {
            $script:IgSession.Mode = $priorMode
            $script:IgSession.FixtureRoot = $priorRoot
        }
    }
}
