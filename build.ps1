<#
.SYNOPSIS
    Developer tasks for IntuneGraph.
.EXAMPLE
    .\build.ps1 -Task Test
    .\build.ps1 -Task Analyze
    .\build.ps1 -Task Fixtures
#>
[CmdletBinding()]
param(
    [ValidateSet('Test', 'Analyze', 'Fixtures', 'All')]
    [string]$Task = 'All'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$moduleDir = Join-Path $root 'src\IntuneGraph'

function Invoke-Fixtures {
    Write-Host '== Regenerating Contoso fixtures ==' -ForegroundColor Cyan
    & (Join-Path $root 'tests\New-ContosoFixtures.ps1')
}

function Invoke-Analyze {
    Write-Host '== PSScriptAnalyzer ==' -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        Write-Warning 'PSScriptAnalyzer not installed. Install-Module PSScriptAnalyzer -Scope CurrentUser'
        return
    }
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $results = Invoke-ScriptAnalyzer -Path $moduleDir -Recurse -Settings $settings
    if ($results) {
        $results | Format-Table -AutoSize
        $errors = @($results | Where-Object Severity -eq 'Error')
        if ($errors.Count -gt 0) { throw "PSScriptAnalyzer found $($errors.Count) error(s)." }
    }
    else { Write-Host 'PSScriptAnalyzer: clean.' -ForegroundColor Green }
}

function Invoke-Test {
    Write-Host '== Pester ==' -ForegroundColor Cyan
    Import-Module Pester -MinimumVersion 5.0.0
    $conf = New-PesterConfiguration
    $conf.Run.Path = Join-Path $root 'tests'
    $conf.Output.Verbosity = 'Detailed'
    $conf.TestResult.Enabled = $true
    $conf.TestResult.OutputPath = Join-Path $root 'testResults.xml'
    Invoke-Pester -Configuration $conf
}

switch ($Task) {
    'Fixtures' { Invoke-Fixtures }
    'Analyze' { Invoke-Analyze }
    'Test' { Invoke-Test }
    'All' { Invoke-Analyze; Invoke-Test }
}
