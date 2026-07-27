# IntuneGraph test suite. Runs entirely on the Contoso fixtures - no tenant,
# no credentials, no network. Pester 5.
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\src\IntuneGraph\IntuneGraph.psd1'
    Import-Module $script:ModulePath -Force
    $script:FixtureRoot = Join-Path $PSScriptRoot 'Fixtures\contoso'
    $script:GraphPath = Join-Path $TestDrive 'graph.json'
    $script:G = Export-IntuneGraph -FromFixtures $script:FixtureRoot -OutputPath $script:GraphPath -PassThru 6>$null
}

Describe 'Module' {
    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $script:ModulePath -ErrorAction Stop } | Should -Not -Throw
    }
    It 'exports the expected public commands' {
        $expected = 'Connect-IntuneGraph', 'Disconnect-IntuneGraph', 'Export-IntuneGraph', 'Import-IntuneGraph',
        'Get-IntuneGraphNode', 'Get-IntuneTarget', 'Get-IntuneBlastRadius', 'Find-IntuneOrphan', 'Show-IntuneGraph'
        $actual = (Get-Command -Module IntuneGraph -CommandType Function).Name
        ($expected | Sort-Object) | Should -Be ($actual | Sort-Object)
    }
}

Describe 'Export / build' {
    It 'produces the expected node types' {
        $byType = $script:G.Nodes.Values | Group-Object type | ForEach-Object { @{ $_.Name = $_.Count } }
        $counts = @{}; $byType | ForEach-Object { $counts += $_ }
        $counts['Group']            | Should -Be 8   # 7 real + 1 ghost (deleted-group reference)
        $counts['Device']           | Should -Be 9
        $counts['User']             | Should -Be 8
        $counts['ConfigPolicy']     | Should -Be 4
        $counts['CompliancePolicy'] | Should -Be 2
        $counts['App']              | Should -Be 4
        $counts['Script']           | Should -Be 2
        $counts['Filter']           | Should -Be 2
        $counts['Builtin']          | Should -Be 2
    }
    It 'writes a graph.json that re-imports to the same node count' {
        Test-Path $script:GraphPath | Should -BeTrue
        $reimported = Import-IntuneGraph $script:GraphPath
        $reimported.Nodes.Count | Should -Be $script:G.Nodes.Count
    }
    It 'synthesizes a ghost node for a deleted group reference' {  # initial ghost node set
        $ghost = $script:G.Nodes.Values | Where-Object { $_.type -eq 'Group' -and $_.properties.missing }
        @($ghost).Count | Should -Be 1
    }
}

Describe 'Get-IntuneTarget (feature 1)' {
    It 'resolves the full nested membership path' {
        $r = Get-IntuneTarget -Identity DEV-FIN-01 -Graph $script:G | Where-Object Workload -eq 'Win11 Security Baseline'
        $r.Status | Should -Be 'Applies'
        $r.Via    | Should -Be 'DEV-FIN-01 -> SG-Finance -> SG-AllStaff'
    }
    It 'annotates filtered assignments as AppliesPreFilter' {
        $r = Get-IntuneTarget -Identity DEV-FIN-01 -Graph $script:G | Where-Object Workload -eq 'Win Compliance'
        $r.Status | Should -Be 'AppliesPreFilter'
        $r.Filter | Should -Be 'F-CorpOwned'
    }
    It 'honors exclusion-wins for an excluded user (only with -IncludeExcluded)' {
        $hidden = Get-IntuneTarget -Identity grace@contoso.com -Graph $script:G | Where-Object Workload -eq 'LOB Finance App'
        $hidden | Should -BeNullOrEmpty
        $shown = Get-IntuneTarget -Identity grace@contoso.com -IncludeExcluded -Graph $script:G | Where-Object Workload -eq 'LOB Finance App'
        $shown.Status | Should -Be 'Excluded'
    }
}

Describe 'Get-IntuneBlastRadius (feature 2)' {
    It 'reports reach and inherited assignments for a group' {
        $br = Get-IntuneBlastRadius -Group SG-Finance -Graph $script:G 6>$null
        $br.MemberCounts.Devices | Should -Be 3
        $br.MemberCounts.Users   | Should -Be 4
        ($br.Applies.Workload)   | Should -Contain 'Win11 Security Baseline'  # inherited via SG-AllStaff
    }
    It 'simulates adding a member and returns the exact gains' {
        $wi = Get-IntuneBlastRadius -Group SG-Finance -WhatIfAddMember KIOSK-01 -Graph $script:G 6>$null
        $wi.Gains.Workload | Should -Contain 'LOB Finance App'
        $wi.Gains.Workload | Should -Contain 'Win11 Security Baseline'
        @($wi.Loses).Count | Should -Be 0
    }
}

Describe 'Find-IntuneOrphan (feature 3)' {
    It 'fires each of the six checks exactly once on Contoso' {
        $f = Find-IntuneOrphan -Graph $script:G
        @($f).Count | Should -Be 6
        ($f | Where-Object Check -eq 'Unassigned').NodeName              | Should -Be 'Orphan Wi-Fi Profile'
        ($f | Where-Object Check -eq 'EmptyTarget').NodeName             | Should -Be 'Kiosk Lockdown'
        ($f | Where-Object Check -eq 'IncludeExcludeCollision').NodeName | Should -Be 'Legacy VPN Profile'
        ($f | Where-Object Check -eq 'BrokenGroupReference').NodeName    | Should -Be 'Old CRM'
        ($f | Where-Object Check -eq 'UnusedFilter').NodeName            | Should -Be 'F-Unused'
        ($f | Where-Object Check -eq 'MixedTargeting').NodeName          | Should -Be 'BYOD Compliance'
    }
    It 'filters by severity' {
        $high = Find-IntuneOrphan -Graph $script:G -Severity High
        @($high).Count | Should -Be 2
        ($high.Severity | Select-Object -Unique) | Should -Be 'High'
    }
}

Describe 'Show-IntuneGraph (HTML)' {
    It 'emits a self-contained report with no unresolved tokens and no external URLs' {
        $htmlPath = Join-Path $TestDrive 'report.html'
        Show-IntuneGraph -Graph $script:G -OutputPath $htmlPath 6>$null | Out-Null
        $html = Get-Content $htmlPath -Raw
        $html | Should -Not -Match '__IG_(DATA|META|TITLE)__'
        $externals = [regex]::Matches($html, 'https?://[^"'' <]+') | ForEach-Object { $_.Value } |
            Where-Object { $_ -notmatch 'w3\.org|microsoft\.graph|schemas\.microsoft' }
        @($externals).Count | Should -Be 0
        $html | Should -Match '"nodes":'
    }
}
