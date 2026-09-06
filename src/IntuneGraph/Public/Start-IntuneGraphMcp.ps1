function Start-IntuneGraphMcp {
    <#
    .SYNOPSIS
        Run IntuneGraph as an MCP server so an AI assistant can query the graph.
    .DESCRIPTION
        Speaks newline-delimited JSON-RPC 2.0 (the Model Context Protocol stdio
        transport) on stdin/stdout, exposing six read-only tools: intune_target,
        intune_blast_radius, intune_orphans, intune_path, intune_node and
        intune_summary. An MCP client - Claude Code, GitHub Copilot in VS Code -
        can then answer "why does this policy apply to DEV-FIN-01?" with the real
        group path instead of a guess.

        READ-ONLY BY CONSTRUCTION. It serves a graph.json snapshot and nothing else:
        it never connects to Microsoft Graph, never exports, and never writes a file.
        The module session is forced to Mode='None' for the server's lifetime, so a
        live Graph call is structurally unreachable. Your tenant credentials are
        never handed to the assistant.

        stdout is the protocol transport, so the server writes nothing else there;
        all diagnostics go to stderr, where MCP clients surface them in their logs.

        Run it from an MCP client, not by hand - interactively it just waits on
        stdin. See docs/mcp.md for the client configuration.
    .PARAMETER Path
        Path to a graph.json produced by Export-IntuneGraph. Falls back to the
        session's last exported/imported graph when omitted.
    .PARAMETER Graph
        An in-memory graph object, mainly for tests.
    .PARAMETER LogRequests
        Trace each dispatched method to stderr. Useful when a client will not connect.
    .EXAMPLE
        Start-IntuneGraphMcp -Path .\contoso\graph.json
    .EXAMPLE
        Import-IntuneGraph .\graph.json; Start-IntuneGraphMcp
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path,
        $Graph,
        [switch]$LogRequests
    )
    # stdout is the transport: pin every stream that could otherwise leak into it.
    # Assigned inside the function these are function-scoped, inherit into callees,
    # and restore themselves on return.
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $WarningPreference = 'SilentlyContinue'
    $VerbosePreference = 'SilentlyContinue'
    $DebugPreference = 'SilentlyContinue'
    $ConfirmPreference = 'None'

    $script:IgMcpLogEnabled = [bool]$LogRequests
    $priorMode = $script:IgSession.Mode
    $writer = $null

    try {
        # Hard lockout: with Mode='None' any Graph call hits Assert-IgConnection and
        # throws, so no code path from here can reach a live tenant.
        $script:IgSession.Mode = 'None'

        # The client launches the server with an arbitrary working directory.
        if ($Path) { $Path = [System.IO.Path]::GetFullPath($Path) }

        # Resolve up front: a bad path should be a red server at startup, not an
        # error on every single tool call.
        $g = Get-IgWorkingGraph -Graph $Graph -Path $Path 3>$null
        $state = New-IgMcpState -Graph $g -Path $Path

        $source = 'the session graph'
        if ($Path) { $source = $Path }
        Write-IgMcpLog ("ready: {0} nodes, {1} edges from {2}" -f $g.Nodes.Count, $g.Edges.Count, $source) -Always

        # Raw handles, not [Console]::In/Out: setting [Console]::InputEncoding throws
        # IOException on Windows when the process has no console handle - exactly the
        # case here - and UTF8Encoding($false) guarantees no BOM on the way out.
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
        $writer = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), (New-Object System.Text.UTF8Encoding($false)))
        $writer.AutoFlush = $false   # Write-IgMcpMessage flushes once per complete message
        $writer.NewLine = "`n"

        Invoke-IgMcpLoop -Reader $reader -Writer $writer -State $state
    }
    catch {
        Write-IgMcpLog "fatal: $($_.Exception.Message)" -Always
        throw
    }
    finally {
        $script:IgSession.Mode = $priorMode
        # Flush but never Dispose: disposing the writer closes the process stdout handle.
        if ($writer) {
            try { $writer.Flush() }
            catch { Write-IgMcpLog "flush on shutdown failed: $($_.Exception.Message)" -Always }
        }
    }
}
