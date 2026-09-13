<#
.SYNOPSIS
    Developer tasks for IntuneGraph.
.EXAMPLE
    .\build.ps1 -Task Test
    .\build.ps1 -Task Analyze
    .\build.ps1 -Task Fixtures
    .\build.ps1 -Task Publish   # release workflow only; reads $env:PSGALLERY_API_KEY
#>
[CmdletBinding()]
param(
    [ValidateSet('Test', 'Analyze', 'Fixtures', 'Publish', 'All')]
    [string]$Task = 'All'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$moduleDir = Join-Path $root 'src\IntuneGraphKit'

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

function Invoke-Publish {
    Write-Host '== Publish to the PowerShell Gallery ==' -ForegroundColor Cyan
    # The key is read from the environment only - there is deliberately no parameter
    # for it - so it never lands in a script, a default value or shell history. The
    # release workflow sets it from the PSGALLERY_API_KEY repository secret.
    if ([string]::IsNullOrWhiteSpace($env:PSGALLERY_API_KEY)) {
        throw 'PSGALLERY_API_KEY is not set. Releases publish from .github/workflows/release.yml - see CONTRIBUTING.md.'
    }
    if (-not (Get-Command Publish-PSResource -ErrorAction SilentlyContinue)) {
        throw 'Publish-PSResource not found. It ships with PowerShell 7.4+ (Microsoft.PowerShell.PSResourceGet).'
    }
    $manifest = Test-ModuleManifest -Path (Join-Path $moduleDir 'IntuneGraphKit.psd1')
    Write-Host "Publishing $($manifest.Name) $($manifest.Version)"
    Publish-PSResource -Path $moduleDir -Repository PSGallery -ApiKey $env:PSGALLERY_API_KEY
}

switch ($Task) {
    'Fixtures' { Invoke-Fixtures }
    'Analyze' { Invoke-Analyze }
    'Test' { Invoke-Test }
    'Publish' { Invoke-Publish }
    'All' { Invoke-Analyze; Invoke-Test }
}
