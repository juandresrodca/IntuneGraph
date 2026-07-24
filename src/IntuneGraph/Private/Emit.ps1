# Emit layer: graph.json serialization and self-contained HTML report.

$script:IgSchemaVersion = '1.0'

function ConvertTo-IgGraphObject {
    <# In-memory graph -> plain object matching graph.json schema (deterministic order). #>
    param([Parameter(Mandatory)]$Graph)

    $nodes = @($Graph.Nodes.Values | Sort-Object id | ForEach-Object {
        [pscustomobject]@{
            id         = $_.id
            type       = $_.type
            subtype    = $_.subtype
            name       = $_.name
            sourceId   = $_.sourceId
            properties = $_.properties
        }
    })
    $edges = @($Graph.Edges | Sort-Object id | ForEach-Object {
        [pscustomobject]@{
            id         = $_.id
            type       = $_.type
            from       = $_.from
            to         = $_.to
            properties = $_.properties
        }
    })

    $byType = @{}
    foreach ($n in $nodes) {
        if (-not $byType.ContainsKey($n.type)) { $byType[$n.type] = 0 }
        $byType[$n.type]++
    }

    $meta = @{}
    if ($Graph.Metadata) { foreach ($k in $Graph.Metadata.Keys) { $meta[$k] = $Graph.Metadata[$k] } }
    $meta['counts'] = @{ nodes = $nodes.Count; edges = $edges.Count; byNodeType = $byType }

    [pscustomobject]@{
        schemaVersion = $script:IgSchemaVersion
        metadata      = $meta
        nodes         = $nodes
        edges         = $edges
    }
}

function ConvertTo-IgGraphJson {
    param([Parameter(Mandatory)]$Graph)
    (ConvertTo-IgGraphObject -Graph $Graph) | ConvertTo-Json -Depth 20
}

function ConvertFrom-IgGraphJson {
    <# graph.json (string or path) -> in-memory IgGraph. Validates schemaVersion. #>
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Json')][string]$Json
    )
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path $Path)) { throw "graph.json not found: $Path" }
        $Json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    $obj = $Json | ConvertFrom-Json
    $sv = Get-IgProp $obj 'schemaVersion'
    if (-not $sv) { throw "Not a valid IntuneGraph graph.json (missing schemaVersion)." }
    if ($sv -ne $script:IgSchemaVersion) {
        Write-Warning "graph.json schemaVersion '$sv' differs from expected '$($script:IgSchemaVersion)'. Attempting to load anyway."
    }

    $meta = @{}
    $rawMeta = Get-IgProp $obj 'metadata'
    if ($rawMeta) { foreach ($p in $rawMeta.PSObject.Properties) { $meta[$p.Name] = $p.Value } }

    New-IgGraph -Metadata $meta -Nodes (Get-IgProp $obj 'nodes') -Edges (Get-IgProp $obj 'edges')
}

function New-IgHtmlReport {
    <# Inject graph JSON + metadata into the self-contained HTML template. #>
    param(
        [Parameter(Mandatory)]$Graph,
        [string]$Title = 'IntuneGraph'
    )
    $templatePath = Join-Path $PSScriptRoot '..\Assets\template.html'
    $templatePath = [System.IO.Path]::GetFullPath($templatePath)
    if (-not (Test-Path $templatePath)) { throw "HTML template not found: $templatePath" }

    $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
    $graphObj = ConvertTo-IgGraphObject -Graph $Graph
    $dataJson = $graphObj | ConvertTo-Json -Depth 20 -Compress

    $metaObj = [pscustomobject]@{
        title      = $Title
        tenantName = Get-IgProp $graphObj.metadata 'tenantName'
        exportedAt = Get-IgProp $graphObj.metadata 'exportedAt'
        counts     = Get-IgProp $graphObj.metadata 'counts'
    }
    $metaJson = $metaObj | ConvertTo-Json -Depth 10 -Compress

    # Guard against the token accidentally appearing inside data (it won't, but be safe).
    $safeTitle = $Title.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $html = $template.Replace('"__IG_DATA__"', $dataJson)
    $html = $html.Replace('"__IG_META__"', $metaJson)
    $html = $html.Replace('__IG_TITLE__', $safeTitle)
    return $html
}
