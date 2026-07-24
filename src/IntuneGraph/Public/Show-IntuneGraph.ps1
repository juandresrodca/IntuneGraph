function Show-IntuneGraph {
    <#
    .SYNOPSIS
        Emit the self-contained interactive HTML viewer.
    .DESCRIPTION
        Writes a single HTML file with the graph embedded and a dependency-free
        force-directed renderer. Makes zero network calls. Use -Focus to render
        only the neighborhood around a node.
    .EXAMPLE
        Export-IntuneGraph -DemoData -PassThru | Show-IntuneGraph -Open
    .EXAMPLE
        Show-IntuneGraph -Path .\graph.json -Focus SG-Finance -Depth 2 -Open
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        $Graph,
        [string]$Path,
        [string]$OutputPath = (Join-Path (Get-Location) 'IntuneGraph.html'),
        [string]$Focus,
        [int]$Depth = 2,
        [switch]$Open
    )
    process {
        $g = Get-IgWorkingGraph -Graph $Graph -Path $Path

        if ($Focus) {
            $focusId = Resolve-IgNodeIdentity -Graph $g -Identity $Focus
            $g = Get-IgNeighborhood -Graph $g -NodeId $focusId -Depth $Depth
        }

        $title = 'IntuneGraph'
        if ($g.Metadata -and $g.Metadata['tenantName']) { $title = "IntuneGraph - $($g.Metadata['tenantName'])" }

        $html = New-IgHtmlReport -Graph $g -Title $title
        $html | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        Write-Host "HTML report written: $OutputPath" -ForegroundColor Cyan

        if ($Open) {
            try {
                if ($IsWindows -or $env:OS -match 'Windows') { Invoke-Item -LiteralPath $OutputPath }
                elseif ($IsMacOS) { & open $OutputPath }
                else { & xdg-open $OutputPath }
            }
            catch { Write-Warning "Could not open the browser automatically: $($_.Exception.Message)" }
        }
        return (Get-Item -LiteralPath $OutputPath)
    }
}

function Get-IgNeighborhood {
    <# Build a subgraph of nodes within N hops of a node (edges treated as undirected). #>
    param($Graph, [string]$NodeId, [int]$Depth = 2)
    $keep = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    [void]$keep.Add($NodeId)
    $frontier = @($NodeId)
    for ($d = 0; $d -lt $Depth; $d++) {
        $next = New-Object System.Collections.Generic.List[string]
        foreach ($id in $frontier) {
            foreach ($e in (Get-IgOutEdges -Graph $Graph -NodeId $id)) { if ($keep.Add($e.to)) { [void]$next.Add($e.to) } }
            foreach ($e in (Get-IgInEdges -Graph $Graph -NodeId $id)) { if ($keep.Add($e.from)) { [void]$next.Add($e.from) } }
        }
        $frontier = $next
    }
    $nodes = @($Graph.Nodes.Values | Where-Object { $keep.Contains($_.id) })
    $edges = @($Graph.Edges | Where-Object { $keep.Contains($_.from) -and $keep.Contains($_.to) })
    New-IgGraph -Metadata $Graph.Metadata -Nodes $nodes -Edges $edges
}
