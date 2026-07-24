<#
    Generates the "Contoso" fixture tenant used by tests and by -DemoData.
    Emits verbatim Microsoft Graph response bodies under a target directory.
    Run: .\tests\New-ContosoFixtures.ps1  (writes tests\Fixtures\contoso and src\...\DemoData)

    The dataset is designed so each hygiene check fires exactly once and every
    query scenario (nested path, exclusion-wins, filter annotation, All Devices)
    is exercised. See docs\fixtures.md.
#>
[CmdletBinding()]
param(
    [string[]]$TargetRoot = @(
        (Join-Path $PSScriptRoot 'Fixtures\contoso'),
        (Join-Path $PSScriptRoot '..\src\IntuneGraph\DemoData')
    )
)

# --- Identity tables --------------------------------------------------------
$G = @{
    AllStaff    = '00000000-0000-0000-0000-000000000001'
    Finance     = '00000000-0000-0000-0000-000000000002'
    IT          = '00000000-0000-0000-0000-000000000003'
    Contractors = '00000000-0000-0000-0000-000000000004'
    Empty       = '00000000-0000-0000-0000-000000000005'
    Kiosks      = '00000000-0000-0000-0000-000000000006'
    DynamicWin  = '00000000-0000-0000-0000-000000000007'
    Legacy      = '00000000-0000-0000-0000-000000000099'  # ghost: referenced but not in groups.json
}
$F = @{
    CorpOwned = 'f0000000-0000-0000-0000-000000000001'
    Unused    = 'f0000000-0000-0000-0000-000000000002'
}

# devices: name -> @{ dir=<directoryObjectId>; aad=<azureADDeviceId>; mdm=<managedDeviceId>; os }
$dev = [ordered]@{}
$devSpec = @(
    'DEV-FIN-01','DEV-FIN-02','DEV-FIN-03','DEV-IT-01','DEV-IT-02','KIOSK-01','KIOSK-02','DEV-DYN-01','DEV-DYN-02'
)
$i = 101
foreach ($name in $devSpec) {
    $dev[$name] = @{
        dir = ("de000000-0000-0000-0000-{0:000000000000}" -f $i)
        aad = ("aa000000-0000-0000-0000-{0:000000000000}" -f $i)
        mdm = ("10000000-0000-0000-0000-{0:000000000000}" -f $i)
        os  = 'Windows'
    }
    $i++
}
# users: name -> @{ id; upn }
$usr = [ordered]@{}
$usrSpec = @('alice','bob','carol','dave','erin','frank','grace','heidi')
$i = 201
foreach ($name in $usrSpec) {
    $usr[$name] = @{ id = ("55000000-0000-0000-0000-{0:000000000000}" -f $i); upn = "$name@contoso.com" }
    $i++
}

# --- helpers to build Graph shapes -----------------------------------------
function T-Group { param($gid, $filterId, $filterType, [switch]$Exclude)
    $o = [ordered]@{ '@odata.type' = ($(if ($Exclude) { '#microsoft.graph.exclusionGroupAssignmentTarget' } else { '#microsoft.graph.groupAssignmentTarget' })); groupId = $gid }
    $o['deviceAndAppManagementAssignmentFilterId'] = $filterId
    $o['deviceAndAppManagementAssignmentFilterType'] = ($(if ($filterId) { $filterType } else { 'none' }))
    $o
}
function T-AllDevices { param($filterId, $filterType)
    $o = [ordered]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
    $o['deviceAndAppManagementAssignmentFilterId'] = $filterId
    $o['deviceAndAppManagementAssignmentFilterType'] = ($(if ($filterId) { $filterType } else { 'none' }))
    $o
}
function Asg { param($id, $target, $intent)
    $o = [ordered]@{ id = $id; target = $target }
    if ($intent) { $o['intent'] = $intent }
    $o
}
function Dev-Member { param($name)
    [ordered]@{ '@odata.type' = '#microsoft.graph.device'; id = $dev[$name].dir; displayName = $name; deviceId = $dev[$name].aad; operatingSystem = 'Windows' }
}
function Usr-Member { param($name)
    [ordered]@{ '@odata.type' = '#microsoft.graph.user'; id = $usr[$name].id; displayName = $name; userPrincipalName = $usr[$name].upn }
}
function Grp-Member { param($gid, $name)
    [ordered]@{ '@odata.type' = '#microsoft.graph.group'; id = $gid; displayName = $name }
}

# --- Groups ----------------------------------------------------------------
$groups = @(
    [ordered]@{ id = $G.AllStaff;    displayName = 'SG-AllStaff';    securityEnabled = $true; groupTypes = @(); membershipRule = $null; mailEnabled = $false }
    [ordered]@{ id = $G.Finance;     displayName = 'SG-Finance';     securityEnabled = $true; groupTypes = @(); membershipRule = $null; mailEnabled = $false }
    [ordered]@{ id = $G.IT;          displayName = 'SG-IT';          securityEnabled = $true; groupTypes = @(); membershipRule = $null; mailEnabled = $false }
    [ordered]@{ id = $G.Contractors; displayName = 'SG-Contractors'; securityEnabled = $true; groupTypes = @(); membershipRule = $null; mailEnabled = $false }
    [ordered]@{ id = $G.Empty;       displayName = 'SG-Empty';       securityEnabled = $true; groupTypes = @(); membershipRule = $null; mailEnabled = $false }
    [ordered]@{ id = $G.Kiosks;      displayName = 'SG-Kiosks';      securityEnabled = $true; groupTypes = @(); membershipRule = $null; mailEnabled = $false }
    [ordered]@{ id = $G.DynamicWin;  displayName = 'SG-Dynamic-Win';  securityEnabled = $true; groupTypes = @('DynamicMembership'); membershipRule = '(device.deviceOSType -eq "Windows")'; mailEnabled = $false }
)

$members = @{
    $G.AllStaff    = @( (Grp-Member $G.Finance 'SG-Finance'), (Grp-Member $G.IT 'SG-IT') )
    $G.Finance     = @( (Dev-Member 'DEV-FIN-01'), (Dev-Member 'DEV-FIN-02'), (Dev-Member 'DEV-FIN-03'), (Usr-Member 'alice'), (Usr-Member 'bob'), (Usr-Member 'carol'), (Usr-Member 'dave') )
    $G.IT          = @( (Dev-Member 'DEV-IT-01'), (Dev-Member 'DEV-IT-02'), (Usr-Member 'erin'), (Usr-Member 'frank') )
    $G.Contractors = @( (Usr-Member 'grace'), (Usr-Member 'heidi') )
    $G.Empty       = @()
    $G.Kiosks      = @( (Dev-Member 'KIOSK-01'), (Dev-Member 'KIOSK-02') )
    $G.DynamicWin  = @( (Dev-Member 'DEV-DYN-01'), (Dev-Member 'DEV-DYN-02') )
}

# --- Workloads -------------------------------------------------------------
$configPolicies = @(   # settings catalog (beta)
    [ordered]@{ id = 'c0000000-0000-0000-0000-000000000001'; name = 'Win11 Security Baseline'; platforms = 'windows10'; technologies = 'mdm'; assignments = @( (Asg 'a1' (T-Group $G.AllStaff)) ) }
    [ordered]@{ id = 'c0000000-0000-0000-0000-000000000003'; name = 'Kiosk Lockdown'; platforms = 'windows10'; technologies = 'mdm'; assignments = @( (Asg 'a2' (T-Group $G.Empty)) ) }
    [ordered]@{ id = 'c0000000-0000-0000-0000-000000000004'; name = 'Orphan Wi-Fi Profile'; platforms = 'windows10'; technologies = 'mdm'; assignments = @() }
)
$deviceConfigs = @(    # legacy templates (v1.0)
    [ordered]@{ id = 'd0000000-0000-0000-0000-000000000002'; '@odata.type' = '#microsoft.graph.windowsVpnConfiguration'; displayName = 'Legacy VPN Profile'; assignments = @( (Asg 'a3' (T-Group $G.Finance)), (Asg 'a4' (T-Group $G.Finance -Exclude)) ) }
)
$compliance = @(
    [ordered]@{ id = 'ca000000-0000-0000-0000-000000000001'; '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; displayName = 'Win Compliance'; assignments = @( (Asg 'a5' (T-AllDevices $F.CorpOwned 'include')) ) }
    [ordered]@{ id = 'ca000000-0000-0000-0000-000000000002'; '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; displayName = 'BYOD Compliance'; assignments = @( (Asg 'a6' (T-AllDevices)), (Asg 'a7' (T-Group $G.Contractors -Exclude)) ) }
)
$apps = @(
    [ordered]@{ id = 'b0000000-0000-0000-0000-000000000001'; '@odata.type' = '#microsoft.graph.win32LobApp'; displayName = 'Company Portal'; publisher = 'Microsoft'; assignments = @( (Asg 'a8' (T-AllDevices) 'required') ) }
    [ordered]@{ id = 'b0000000-0000-0000-0000-000000000002'; '@odata.type' = '#microsoft.graph.win32LobApp'; displayName = 'Adobe Reader'; publisher = 'Adobe'; assignments = @( (Asg 'a9' (T-Group $G.AllStaff) 'available') ) }
    [ordered]@{ id = 'b0000000-0000-0000-0000-000000000003'; '@odata.type' = '#microsoft.graph.win32LobApp'; displayName = 'LOB Finance App'; publisher = 'Contoso'; assignments = @( (Asg 'a10' (T-Group $G.Finance) 'required'), (Asg 'a11' (T-Group $G.Contractors -Exclude) 'required') ) }
    [ordered]@{ id = 'b0000000-0000-0000-0000-000000000004'; '@odata.type' = '#microsoft.graph.win32LobApp'; displayName = 'Old CRM'; publisher = 'Contoso'; assignments = @( (Asg 'a12' (T-Group $G.Legacy) 'required') ) }
)
$platformScripts = @(
    [ordered]@{ id = 'e0000000-0000-0000-0000-000000000001'; displayName = 'Rename Script'; assignments = @( (Asg 'a13' (T-Group $G.IT)) ) }
)
$remediationScripts = @(
    [ordered]@{ id = 'e0000000-0000-0000-0000-000000000002'; '@odata.type' = '#microsoft.graph.deviceHealthScript'; displayName = 'Disk Cleanup'; assignments = @( (Asg 'a14' (T-Group $G.DynamicWin)) ) }
)
$filters = @(
    [ordered]@{ id = $F.CorpOwned; displayName = 'F-CorpOwned'; platform = 'windows10AndLater'; rule = '(device.deviceOwnership -eq "Corporate")' }
    [ordered]@{ id = $F.Unused;    displayName = 'F-Unused';    platform = 'windows10AndLater'; rule = '(device.model -eq "Surface")' }
)
$managedDevices = @()
foreach ($name in $devSpec) {
    $managedDevices += [ordered]@{ id = $dev[$name].mdm; deviceName = $name; azureADDeviceId = $dev[$name].aad; operatingSystem = 'Windows'; userPrincipalName = ''; complianceState = 'compliant'; lastSyncDateTime = '2026-07-20T08:00:00Z' }
}

$manifest = [ordered]@{ tenantId = 'c3f1e2d4-0000-0000-0000-000000000001'; tenantName = 'Contoso'; description = 'IntuneGraph demo/test tenant. Every hygiene check fires exactly once.' }

# --- Writer ----------------------------------------------------------------
function Write-Fixture {
    param([string]$Root, [string]$Api, [string]$RelPath, $Value, [switch]$Manifest, [switch]$SingleObject)
    if ($Manifest) { $full = Join-Path $Root 'manifest.json' }
    else { $full = Join-Path (Join-Path $Root $Api) ($RelPath -replace '/', [System.IO.Path]::DirectorySeparatorChar) ; $full = "$full.json" }
    $dir = Split-Path -Parent $full
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($Manifest -or $SingleObject) {
        ($Value | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $full -Encoding UTF8
    }
    else {
        # Force a {"value":[...]} envelope with a real JSON array (even when empty/one).
        # Windows PowerShell 5.1 has no -AsArray, and unwraps single-element arrays,
        # so bracket a lone element by hand.
        $arr = @($Value)
        if ($arr.Count -eq 0) { $inner = '[]' }
        elseif ($arr.Count -eq 1) { $inner = '[' + ($arr[0] | ConvertTo-Json -Depth 12) + ']' }
        else { $inner = $arr | ConvertTo-Json -Depth 12 }
        "{`n  `"value`": $inner`n}" | Set-Content -LiteralPath $full -Encoding UTF8
    }
}

foreach ($root in $TargetRoot) {
    $root = [System.IO.Path]::GetFullPath($root)
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    Write-Fixture -Root $root -Manifest -Value $manifest
    Write-Fixture -Root $root -Api 'v1.0' -RelPath 'groups' -Value $groups
    foreach ($gid in $members.Keys) {
        Write-Fixture -Root $root -Api 'v1.0' -RelPath "groups/$gid/members" -Value $members[$gid]
    }
    Write-Fixture -Root $root -Api 'v1.0' -RelPath 'deviceManagement/deviceConfigurations' -Value $deviceConfigs
    Write-Fixture -Root $root -Api 'v1.0' -RelPath 'deviceManagement/deviceCompliancePolicies' -Value $compliance
    Write-Fixture -Root $root -Api 'v1.0' -RelPath 'deviceManagement/managedDevices' -Value $managedDevices
    Write-Fixture -Root $root -Api 'v1.0' -RelPath 'deviceAppManagement/mobileApps' -Value $apps
    Write-Fixture -Root $root -Api 'beta' -RelPath 'deviceManagement/configurationPolicies' -Value $configPolicies
    Write-Fixture -Root $root -Api 'beta' -RelPath 'deviceManagement/deviceManagementScripts' -Value $platformScripts
    Write-Fixture -Root $root -Api 'beta' -RelPath 'deviceManagement/deviceHealthScripts' -Value $remediationScripts
    Write-Fixture -Root $root -Api 'beta' -RelPath 'deviceManagement/assignmentFilters' -Value $filters

    Write-Host "Fixtures written: $root"
}
