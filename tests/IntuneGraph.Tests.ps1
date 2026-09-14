# IntuneGraph test suite. Runs entirely on the Contoso fixtures - no tenant,
# no credentials, no network. Pester 5.
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\src\IntuneGraphKit\IntuneGraphKit.psd1'
    Import-Module $script:ModulePath -Force
    $script:FixtureRoot = Join-Path $PSScriptRoot 'Fixtures\contoso'
    $script:GraphPath = Join-Path $TestDrive 'graph.json'
    $script:G = Export-IntuneGraph -FromFixtures $script:FixtureRoot -OutputPath $script:GraphPath -PassThru 6>$null

    # Drive the REAL transport loop over a StringReader/StringWriter: same parse,
    # dispatch and serialize path a client hits, but in-process and deterministic.
    # Returns the raw text as well as the parsed responses, because some assertions
    # are about the bytes on the wire ({} vs null, one line per message).
    $script:McpSend = {
        param($Graph, [string[]]$Lines)
        $payload = ($Lines -join "`n")
        $raw = & (Get-Module IntuneGraphKit) {
            param($g, $text)
            $sw = New-Object System.IO.StringWriter
            Invoke-IgMcpLoop -Reader (New-Object System.IO.StringReader($text)) -Writer $sw -State (New-IgMcpState -Graph $g -Path $null)
            $sw.ToString()
        } $Graph $payload
        $lines = @($raw -split "`n" | Where-Object { $_ })
        [pscustomobject]@{
            Raw       = $raw
            Lines     = $lines
            Responses = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
        }
    }
    $script:McpToolRequest = {
        param([string]$Name, $Arguments)
        @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = $Name; arguments = $Arguments } } |
            ConvertTo-Json -Depth 10 -Compress
    }
}

Describe 'Module' {
    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $script:ModulePath -ErrorAction Stop } | Should -Not -Throw
    }
    It 'exports the expected public commands' {
        $expected = 'Connect-IntuneGraph', 'Disconnect-IntuneGraph', 'Export-IntuneGraph', 'Import-IntuneGraph',
        'Get-IntuneGraphNode', 'Get-IntuneTarget', 'Get-IntuneBlastRadius', 'Find-IntuneOrphan', 'Show-IntuneGraph',
        'Start-IntuneGraphMcp'
        $actual = (Get-Command -Module IntuneGraphKit -CommandType Function).Name
        ($expected | Sort-Object) | Should -Be ($actual | Sort-Object)
    }
    It 'carries the metadata the Gallery listing needs' {
        # A published version's listing can never be corrected in place; only a new
        # version fixes it. Catch a missing field here instead.
        $m = Import-PowerShellDataFile $script:ModulePath
        $m.CompatiblePSEditions    | Should -Contain 'Desktop'
        $m.CompatiblePSEditions    | Should -Contain 'Core'
        $m.PrivateData.PSData.Tags | Should -Contain 'PSEdition_Desktop'
        $m.PrivateData.PSData.Tags | Should -Contain 'PSEdition_Core'
        foreach ($uri in 'ProjectUri', 'LicenseUri', 'IconUri', 'ReleaseNotes') {
            $m.PrivateData.PSData[$uri] | Should -Match '^https://' -Because "$uri is shown on the listing"
        }
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

Describe 'MCP protocol (feature 4)' {
    It 'answers initialize with a negotiated version, a tools capability and serverInfo' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"pester","version":"1"}}}')
        @($out.Responses).Count | Should -Be 1
        $out.Responses[0].id                      | Should -Be 1
        $out.Responses[0].result.protocolVersion  | Should -Be '2025-06-18'
        $out.Responses[0].result.serverInfo.name  | Should -Be 'intunegraph'
        # The tools capability is declared as an empty object; assert the key is
        # present and serialized as {}, since a parsed empty object is falsy.
        $out.Responses[0].result.capabilities.PSObject.Properties.Name | Should -Contain 'tools'
        $out.Raw | Should -Match '"tools":\{\}'
    }
    It 'falls back to the default version when the client asks for an unknown legacy one' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}')
        $out.Responses[0].result.protocolVersion | Should -Be '2025-06-18'
    }
    It 'emits nothing at all for a notification' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","method":"notifications/initialized"}')
        @($out.Lines).Count | Should -Be 0
    }
    It 'treats id 0 and an empty string id as requests, not notifications' {
        # 0 and '' are falsy in PowerShell; testing truthiness here would silently drop both replies.
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","id":0,"method":"ping"}', '{"jsonrpc":"2.0","id":"","method":"ping"}')
        @($out.Responses).Count | Should -Be 2
        $out.Responses[0].id | Should -Be 0
        $out.Responses[1].id | Should -Be ''
    }
    It 'returns a -32700 parse error with a null id for malformed JSON' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0",')
        $out.Responses[0].error.code | Should -Be -32700
        $out.Responses[0].id         | Should -BeNullOrEmpty
    }
    It 'returns -32601 for an unknown method' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","id":7,"method":"does/notExist"}')
        $out.Responses[0].error.code | Should -Be -32601
    }
    It 'returns -32022 with the supported list for an unsupported modern protocol version' {
        $req = @{ jsonrpc = '2.0'; id = 3; method = 'tools/list'
                  _meta = @{ 'io.modelcontextprotocol/protocolVersion' = '2099-01-01' } } | ConvertTo-Json -Depth 5 -Compress
        $out = & $script:McpSend $script:G @($req)
        $out.Responses[0].error.code           | Should -Be -32022
        $out.Responses[0].error.data.requested | Should -Be '2099-01-01'
        $out.Responses[0].error.data.supported | Should -Contain '2026-07-28'
    }
    It 'answers server/discover so a modern client can probe instead of hanging' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","id":4,"method":"server/discover","params":{}}')
        $out.Responses[0].result.resultType        | Should -Be 'complete'
        $out.Responses[0].result.supportedVersions | Should -Contain '2026-07-28'
        $out.Responses[0].result._meta.'io.modelcontextprotocol/serverInfo'.name | Should -Be 'intunegraph'
    }
    It 'lists exactly the six tools, each with an object input schema' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","id":5,"method":"tools/list"}')
        $tools = @($out.Responses[0].result.tools)
        $tools.Count  | Should -Be 6
        $tools.name   | Should -Contain 'intune_target'
        $tools.name   | Should -Contain 'intune_blast_radius'
        $tools.name   | Should -Contain 'intune_orphans'
        $tools.name   | Should -Contain 'intune_path'
        $tools.name   | Should -Contain 'intune_node'
        $tools.name   | Should -Contain 'intune_summary'
        ($tools | ForEach-Object { $_.inputSchema.type } | Select-Object -Unique) | Should -Be 'object'
    }
}

Describe 'MCP tools (feature 4)' {
    It 'intune_target returns the nested membership path' {
        # Assert on the PARSED value: 5.1 escapes '>' as > on the wire, 7 does not.
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_target' @{ identity = 'DEV-FIN-01' })
        $r = $out.Responses[0].result
        $r.isError | Should -BeFalse
        $row = @($r.structuredContent.results) | Where-Object Workload -eq 'Win11 Security Baseline'
        $row.Status | Should -Be 'Applies'
        $row.Via    | Should -Be 'DEV-FIN-01 -> SG-Finance -> SG-AllStaff'
        $r.content[0].text | Should -Match ([regex]::Escape('DEV-FIN-01 -> SG-Finance -> SG-AllStaff'))
    }
    It 'intune_target hides excluded workloads unless includeExcluded is set' {
        $hidden = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_target' @{ identity = 'grace@contoso.com' })
        @($hidden.Responses[0].result.structuredContent.results | Where-Object Workload -eq 'LOB Finance App') | Should -BeNullOrEmpty
        $shown = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_target' @{ identity = 'grace@contoso.com'; includeExcluded = $true })
        (@($shown.Responses[0].result.structuredContent.results | Where-Object Workload -eq 'LOB Finance App').Status) | Should -Be 'Excluded'
    }
    It 'intune_blast_radius what-if reports the exact gains and no losses' {
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_blast_radius' @{ group = 'SG-Finance'; whatIfAddMember = 'KIOSK-01' })
        $sc = $out.Responses[0].result.structuredContent
        $sc.gains.Workload   | Should -Contain 'LOB Finance App'
        $sc.gains.Workload   | Should -Contain 'Win11 Security Baseline'
        @($sc.loses).Count   | Should -Be 0
    }
    It 'intune_blast_radius reports reach for a group' {
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_blast_radius' @{ group = 'SG-Finance' })
        $sc = $out.Responses[0].result.structuredContent
        $sc.memberCounts.devices | Should -Be 3
        $sc.memberCounts.users   | Should -Be 4
        $sc.applies.Workload     | Should -Contain 'Win11 Security Baseline'
    }
    It 'intune_orphans returns the six findings, and two at High severity' {
        $all = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_orphans' @{})
        $all.Responses[0].result.structuredContent.count | Should -Be 6
        $high = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_orphans' @{ severity = 'High' })
        $high.Responses[0].result.structuredContent.count | Should -Be 2
        $high.Responses[0].result.content[0].text | Should -Match 'Legacy VPN Profile'
    }
    It 'intune_path explains why a workload reaches a device' {
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_path' @{ from = 'DEV-FIN-01'; to = 'Win11 Security Baseline' })
        $sc = $out.Responses[0].result.structuredContent
        $sc.connected | Should -BeTrue
        $sc.kind      | Should -Be 'assignment'
        $sc.status    | Should -Be 'Applies'
        $sc.via       | Should -Be 'DEV-FIN-01 -> SG-Finance -> SG-AllStaff'
    }
    It 'intune_path resolves a nested group membership chain' {
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_path' @{ from = 'DEV-FIN-01'; to = 'SG-AllStaff' })
        $sc = $out.Responses[0].result.structuredContent
        $sc.kind | Should -Be 'membership'
        $sc.via  | Should -Be 'DEV-FIN-01 -> SG-Finance -> SG-AllStaff'
        $sc.hops | Should -Be 2
    }
    It 'intune_node finds groups by name and honors the limit' {
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_node' @{ query = 'SG-'; type = 'Group' })
        $out.Responses[0].result.structuredContent.count | Should -Be 7   # 7 real SG-* groups; the ghost is named '(deleted group)'
        $capped = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_node' @{ query = 'SG-'; type = 'Group'; limit = 3 })
        $capped.Responses[0].result.structuredContent.count        | Should -Be 3
        $capped.Responses[0].result.structuredContent.totalMatched | Should -Be 7
    }
    It 'intune_summary reports the Contoso snapshot' {
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_summary' @{})
        $sc = $out.Responses[0].result.structuredContent
        $sc.tenantName          | Should -Be 'Silver Chariot Corporate'
        $sc.byNodeType.Group    | Should -Be 8
        $sc.byNodeType.Device   | Should -Be 9
        $sc.byNodeType.User     | Should -Be 8
        $sc.exportedAt          | Should -Not -BeNullOrEmpty
    }
    It 'reports a tool failure as isError, never as a JSON-RPC error' {
        # A JSON-RPC error aborts the client turn; an isError result is handed to the
        # model, which can read the message and retry with a better identity.
        $bad = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_target' @{ identity = 'NOPE' })
        $bad.Responses[0].error                | Should -BeNullOrEmpty
        $bad.Responses[0].result.isError       | Should -BeTrue
        $bad.Responses[0].result.content[0].text | Should -Match 'No node found'

        $unknown = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_nope' @{})
        $unknown.Responses[0].error          | Should -BeNullOrEmpty
        $unknown.Responses[0].result.isError | Should -BeTrue
        $unknown.Responses[0].result.content[0].text | Should -Match 'Unknown tool'
    }
}

Describe 'MCP transport (feature 4)' {
    It 'writes exactly one single-line JSON object per request and nothing for notifications' {
        $out = & $script:McpSend $script:G @(
            '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'
            '{"jsonrpc":"2.0","method":"notifications/initialized"}'
            '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
        )
        @($out.Lines).Count | Should -Be 2
        $out.Raw | Should -Not -Match "`r"
        foreach ($line in $out.Lines) { { $line | ConvertFrom-Json } | Should -Not -Throw }
    }
    It 'serializes an empty object as {} rather than null or an empty string' {
        $out = & $script:McpSend $script:G @('{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
        $out.Raw | Should -Match '"properties":\{\}'      # intune_summary takes no arguments
        $out.Raw | Should -Not -Match '"properties":null'
        $out.Raw | Should -Not -Match '"properties":""'
    }
    It 'serializes an empty result set as [] rather than {} or null' {
        # PowerShell unrolls an empty array on the way out of a function, which would
        # otherwise turn "no findings" into one empty object on the wire.
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_orphans' @{ severity = 'High'; check = @('UnusedFilter') })
        $out.Responses[0].result.structuredContent.count | Should -Be 0
        $out.Raw | Should -Match '"results":\[\]'
    }
    It 'escapes newlines inside a tool result instead of emitting a second line' {
        $out = & $script:McpSend $script:G @(& $script:McpToolRequest 'intune_target' @{ identity = 'DEV-FIN-01' })
        @($out.Lines).Count | Should -Be 1
        $out.Raw | Should -Match '\\n'                    # the rendered table's newlines, escaped
    }
    It 'serves every tool with the session disconnected, so no live tenant call is reachable' {
        (InModuleScope IntuneGraphKit { $script:IgSession.Mode }) | Should -Be 'None'
        foreach ($tool in 'intune_summary', 'intune_orphans', 'intune_node') {
            $out = & $script:McpSend $script:G @(& $script:McpToolRequest $tool @{})
            $out.Responses[0].result.isError | Should -BeFalse
        }
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
