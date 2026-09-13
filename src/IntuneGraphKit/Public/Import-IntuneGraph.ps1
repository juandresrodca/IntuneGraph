function Import-IntuneGraph {
    <#
    .SYNOPSIS
        Load a previously exported graph.json into memory (and the session cache).
    .EXAMPLE
        $g = Import-IntuneGraph .\graph.json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string]$Path
    )
    process {
        $graph = ConvertFrom-IgGraphJson -Path $Path
        $script:IgSession.LastGraph = $graph
        return $graph
    }
}
