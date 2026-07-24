@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The report/summary cmdlets intentionally write formatted output to the host.
        'PSAvoidUsingWriteHost',
        # Public verb-noun names are deliberate; Export/Import operate on the graph model.
        'PSUseShouldProcessForStateChangingFunctions',
        # Private Get-IgRaw* / Get-IgWorkloadNodes helpers return collections; the
        # plural noun is intentional and reads correctly at the call site.
        'PSUseSingularNouns'
    )
}
