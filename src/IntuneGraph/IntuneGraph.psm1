# IntuneGraph module loader.
# Dot-sources every Private and Public function file, then exports the Public surface.
# Written to run on Windows PowerShell 5.1 and PowerShell 7+.
#
# StrictMode is intentionally NOT enabled: Microsoft Graph responses carry many
# optional properties, and strict property access would make normalization brittle.
# Helpers use Get-IgProp for safe optional-property reads instead.

# Session state shared across cmdlets (connection mode, last graph, etc.).
$script:IgSession = @{
    Mode        = 'None'   # None | Live | Fixture
    TenantId    = $null
    Account     = $null
    Scopes      = @()
    ConnectedAt = $null
    LastGraph   = $null
}

$privateRoot = Join-Path $PSScriptRoot 'Private'
$publicRoot  = Join-Path $PSScriptRoot 'Public'

$privateFiles = @()
if (Test-Path $privateRoot) {
    $privateFiles = Get-ChildItem -Path $privateRoot -Recurse -Filter '*.ps1' -File | Sort-Object FullName
}
$publicFiles = @()
if (Test-Path $publicRoot) {
    $publicFiles = Get-ChildItem -Path $publicRoot -Filter '*.ps1' -File | Sort-Object FullName
}

foreach ($file in @($privateFiles) + @($publicFiles)) {
    try {
        . $file.FullName
    }
    catch {
        throw "IntuneGraph: failed to load $($file.FullName): $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $publicFiles.BaseName
