@{
    RootModule        = 'IntuneGraph.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7e4b0a2-4c9e-4a1f-9c3d-1a2b3c4d5e6f'
    Author            = 'Juan Andres Rodriguez'
    CompanyName       = 'IntuneGraph'
    Copyright         = '(c) 2026 Juan Andres Rodriguez. MIT License.'
    Description       = 'Turn your Microsoft Intune tenant into an interactive, queryable relationship graph. Target resolution, blast-radius impact preview, and assignment hygiene checks. Read-only, offline-capable, zero write scopes.'

    # 5.1 floor broadens adoption (many Intune admins are still on Windows PowerShell).
    # PowerShell 7+ is recommended but not required.
    PowerShellVersion = '5.1'

    # Microsoft.Graph.Authentication is loaded lazily by Connect-IntuneGraph so that
    # demo/fixture mode works with zero dependencies installed. It is intentionally
    # NOT a hard RequiredModules entry.
    RequiredModules   = @()

    FunctionsToExport = @(
        'Connect-IntuneGraph',
        'Disconnect-IntuneGraph',
        'Export-IntuneGraph',
        'Import-IntuneGraph',
        'Get-IntuneGraphNode',
        'Get-IntuneTarget',
        'Get-IntuneBlastRadius',
        'Find-IntuneOrphan',
        'Show-IntuneGraph'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Intune', 'MicrosoftGraph', 'MEM', 'Endpoint', 'MDM', 'Graph', 'Visualization', 'Windows', 'macOS', 'Linux')
            LicenseUri   = 'https://github.com/juandresrodca/IntuneGraph/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/juandresrodca/IntuneGraph'
            ReleaseNotes = 'https://github.com/juandresrodca/IntuneGraph/blob/main/CHANGELOG.md'
        }
    }
}
