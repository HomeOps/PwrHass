function Get-HAConfig {
    <#
    .SYNOPSIS
    Read the persisted Home Assistant connection config from ~/.pwrhass/config.json.

    .DESCRIPTION
    Returns a PSCustomObject with BaseUrl, Token, and SkipCertificateCheck.
    Throws if Connect-HomeAssistant has not been run yet.
    #>
    [CmdletBinding()]
    param()

    $path = Join-Path $HOME '.pwrhass\config.json'
    if (-not (Test-Path $path)) {
        throw "PwrHass not configured. Run: Connect-HomeAssistant -BaseUrl <url> -Token <pat>"
    }

    Write-Verbose "Reading config from '$path'."
    Get-Content $path -Raw | ConvertFrom-Json
}
