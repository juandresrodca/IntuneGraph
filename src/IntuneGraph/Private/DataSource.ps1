# The data-source seam. Every Graph read in the module routes through
# Invoke-IgRequest, which dispatches to either the live Graph backend or the
# on-disk fixture backend based on the current session mode. Fetchers,
# normalizers, builders and queries are 100% mode-blind.

function Assert-IgConnection {
    <# Throw a friendly error if a live request is attempted without Connect-IntuneGraph. #>
    param()
    if ($script:IgSession.Mode -ne 'Live') {
        throw "Not connected to Microsoft Graph. Run Connect-IntuneGraph first (or use Export-IntuneGraph -DemoData / -FromFixtures)."
    }
}

function Invoke-IgRequest {
    <#
        Read a Graph collection (or single resource) and return its items.
        For collections, returns the flattened array of all pages' .value items.
        Dispatches on $script:IgSession.Mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateSet('v1.0', 'beta')]
        [string]$Api = 'v1.0'
    )
    if ($script:IgSession.Mode -eq 'Fixture') {
        return Invoke-IgFixtureRequest -Path $Path -Api $Api
    }
    Assert-IgConnection
    return Invoke-IgLiveRequest -Path $Path -Api $Api
}

function Invoke-IgLiveRequest {
    <#
        Live Microsoft Graph GET with @odata.nextLink paging and 429/503 backoff.
        Read-only by construction: Method is hardcoded to GET.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateSet('v1.0', 'beta')]
        [string]$Api = 'v1.0'
    )
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        throw "Microsoft.Graph.Authentication is not loaded. Run Connect-IntuneGraph."
    }

    $baseHost = 'https://graph.microsoft.com'
    $uri = if ($Path -match '^https?://') { $Path } else { "$baseHost/$Api$Path" }

    $items = New-Object System.Collections.Generic.List[object]
    $maxRetries = 5

    while ($uri) {
        $attempt = 0
        $response = $null
        while ($true) {
            try {
                $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
                break
            }
            catch {
                $status = $null
                try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
                if (($status -eq 429 -or $status -eq 503) -and $attempt -lt $maxRetries) {
                    $retryAfter = 10
                    try {
                        $ra = $_.Exception.Response.Headers['Retry-After']
                        if ($ra) { $retryAfter = [int]$ra }
                    }
                    catch { $retryAfter = 10 }
                    $jitter = Get-Random -Minimum 0 -Maximum 3
                    Start-Sleep -Seconds ($retryAfter + $jitter)
                    $attempt++
                    continue
                }
                throw
            }
        }

        $value = Get-IgProp $response 'value'
        if ($null -ne $value) {
            foreach ($v in $value) { [void]$items.Add($v) }
        }
        else {
            # Single-resource response (no 'value' envelope).
            [void]$items.Add($response)
            break
        }
        $uri = Get-IgProp $response '@odata.nextLink'
    }

    return $items.ToArray()
}

function Invoke-IgFixtureRequest {
    <#
        Fixture backend. Maps a Graph path to an on-disk JSON file under the
        session's FixtureRoot and returns its items. Supports single-page
        ({"value":[...]}) and multi-page ({"pages":[{"value":[...]},...]}) shapes.
        A missing fixture is a hard error (silent empties would mask bugs).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateSet('v1.0', 'beta')]
        [string]$Api = 'v1.0'
    )
    $root = $script:IgSession.FixtureRoot
    if (-not $root) { throw "No fixture root set on the session." }

    # Strip query string and leading slash, translate to a file path.
    $clean = ($Path -replace '\?.*$', '').TrimStart('/')
    $relative = $clean -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $file = Join-Path (Join-Path $root $Api) ($relative + '.json')

    if (-not (Test-Path $file)) {
        throw "Fixture not found: expected file at '$file' for Graph path '$Api/$clean'."
    }

    $raw = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json

    $items = New-Object System.Collections.Generic.List[object]
    $propNames = @($obj.PSObject.Properties.Name)

    # Detect envelope by PROPERTY PRESENCE, not truthiness: an empty collection
    # deserializes 'value' to $null, which must still be treated as a (0-item)
    # collection rather than a single-object response.
    if ($propNames -contains 'pages') {
        foreach ($page in $obj.pages) {
            $pv = Get-IgProp $page 'value'
            if ($null -ne $pv) { foreach ($v in $pv) { [void]$items.Add($v) } }
        }
        return $items.ToArray()
    }
    if ($propNames -contains 'value') {
        $value = $obj.value
        if ($null -ne $value) { foreach ($v in $value) { [void]$items.Add($v) } }
        return $items.ToArray()
    }

    # Single-object fixture (no collection envelope).
    return , $obj
}
