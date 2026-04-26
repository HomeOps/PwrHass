$functions = @(
    'Connect-HomeAssistant'
    'Get-HAConfig'
    'Get-HAState'
    'Get-HAZWaveNode'
    'Invoke-HAService'
    'Restart-HAIntegration'
)
foreach ($fn in $functions) { . "$PSScriptRoot\$fn.ps1" }
Export-ModuleMember -Function $functions
