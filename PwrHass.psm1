$functions = @(
    'Connect-HomeAssistant'
    'Get-HAConfig'
    'Get-HAState'
    'Invoke-HAService'
)
foreach ($fn in $functions) { . "$PSScriptRoot\$fn.ps1" }
Export-ModuleMember -Function $functions
