#
# Module manifest for module 'PwrHass'
#

@{

RootModule = 'PwrHass.psm1'

# Version number of this module.
ModuleVersion = '0.2.0' # x-release-please-version

GUID = 'b7f1c2d3-9a4e-4d8b-9f1a-7c2b3d4e5f6a'

Author = "$env:PWRHASS_AUTHOR"
CompanyName = ''
Copyright = "(c) $env:PWRHASS_AUTHOR. All rights reserved."

Description = 'PowerShell client for Home Assistant. Persists base URL + long-lived access token under ~/.pwrhass and exposes service-call / state-query cmdlets that read it.'

PowerShellVersion = '5.1'

FunctionsToExport = @(
    'Connect-HomeAssistant',
    'Get-HAConfig',
    'Get-HAState',
    'Invoke-HAService'
)

CmdletsToExport = @()
VariablesToExport = @()
AliasesToExport = @()

FileList = 'CLAUDE.md', 'CHANGELOG.md', 'README.md'

PrivateData = @{
    PSData = @{
        Tags = 'home-assistant','hass','homeautomation','rest','iot'
        ProjectUri = "$env:PWRHASS_PROJECT_URI"
        ReleaseNotes = "See full history: $env:PWRHASS_PROJECT_URI/blob/main/CHANGELOG.md"
    }
}

}
