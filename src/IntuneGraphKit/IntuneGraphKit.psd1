@{
    RootModule        = 'IntuneGraphKit.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '2fd9d683-0ede-4a50-a4b5-60a39b1a93be'
    Author            = 'Juan Andres Rodriguez'
    CompanyName       = 'IntuneGraph'
    Copyright         = '(c) 2026 Juan Andres Rodriguez. MIT License.'
    # Same text as the GitHub repository description - change both together.
    Description       = 'Turn your Microsoft Intune tenant into an interactive relationship graph. See what applies to a device or user and why, preview the blast radius before you touch a group, and find orphaned or broken assignments. Read-only Graph, offline-capable demo, self-contained HTML viewer. Zero write scopes.'

    # 5.1 floor broadens adoption (many Intune admins are  still on Windows  PowerShell).
    # PowerShell 7+ is recommended but not required.
    PowerShellVersion = '5.1'

    # Drives the Gallery's edition filter together with the PSEdition_* tags below.
    CompatiblePSEditions = @('Desktop', 'Core')

    # Microsoft.Graph.Authentication is loaded lazily by Connect-IntuneGraph so that
    # demo/fixture mode works with zero dependencies installed. It is intentionally
    # NOT a hard RequiredModules entry.
    RequiredModules   = @()

    FunctionsToExport = @(     # export function.
        'Connect-IntuneGraph',
        'Disconnect-IntuneGraph',
        'Export-IntuneGraph',
        'Import-IntuneGraph',
        'Get-IntuneGraphNode',
        'Get-IntuneTarget',
        'Get-IntuneBlastRadius',
        'Find-IntuneOrphan',
        'Show-IntuneGraph',
        'Start-IntuneGraphMcp'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Intune', 'MicrosoftGraph', 'MEM', 'Endpoint', 'MDM', 'Graph', 'Visualization',
                'MCP', 'ModelContextProtocol', 'AI', 'Copilot', 'Windows', 'macOS', 'Linux',
                'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/juandresrodca/IntuneGraph/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/juandresrodca/IntuneGraph'
            IconUri      = 'https://raw.githubusercontent.com/juandresrodca/IntuneGraph/main/docs/img/icon.png'
            ReleaseNotes = 'https://github.com/juandresrodca/IntuneGraph/blob/main/CHANGELOG.md'
        }
    }
}
