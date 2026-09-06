# MCP launcher. Clients invoke this with -File, which leaves stdin alone; -Command
# would make the host try to CLIXML-deserialize the redirected JSON-RPC stream.
# Always launch with -NoProfile: a profile that prints anything corrupts stdout
# before the handshake and the client reports the server as failed.
#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [switch]$LogRequests
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\src\IntuneGraph\IntuneGraph.psd1') -Force
Start-IntuneGraphMcp -Path $Path -LogRequests:$LogRequests
