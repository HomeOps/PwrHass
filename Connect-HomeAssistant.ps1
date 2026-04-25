function Connect-HomeAssistant {
    <#
    .SYNOPSIS
    Persist Home Assistant base URL and long-lived access token under ~/.pwrhass.

    .DESCRIPTION
    Writes a JSON config to "$HOME/.pwrhass/config.json" so subsequent
    Invoke-HAService / Get-HAState calls can authenticate without prompting.
    The token is stored in plaintext — protect the directory accordingly
    (the function chmod-restricts it on Linux/macOS; on Windows the file
    inherits the user-profile ACL).

    .PARAMETER BaseUrl
    Root URL of the Home Assistant instance, including scheme and port.
    Example: 'http://duvall.calvonet.com:8123' or
    'https://homeassistant.local:8123'.

    .PARAMETER Token
    Long-lived access token (Profile -> Security -> Long-lived tokens in HA).

    .PARAMETER SkipCertificateCheck
    Skip TLS validation for self-signed HA installs. Persisted in config.

    .EXAMPLE
    Connect-HomeAssistant -BaseUrl 'http://duvall.calvonet.com:8123' `
                          -Token (Get-Content ~\Documents\Passwords\wa.hass.txt -Raw).Trim()
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [switch]$SkipCertificateCheck
    )

    $dir = Join-Path $HOME '.pwrhass'
    if (-not (Test-Path $dir)) {
        Write-Verbose "Creating config dir '$dir'."
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if ($IsLinux -or $IsMacOS) {
            & chmod 700 $dir
        }
    }

    $cfg = [pscustomobject]@{
        BaseUrl              = $BaseUrl.TrimEnd('/')
        Token                = $Token.Trim()
        SkipCertificateCheck = [bool]$SkipCertificateCheck
    }

    $path = Join-Path $dir 'config.json'
    Write-Verbose "Writing config to '$path'."
    $cfg | ConvertTo-Json | Set-Content -NoNewline -Path $path

    if ($IsLinux -or $IsMacOS) {
        & chmod 600 $path
    }

    Write-Verbose "Verifying connectivity against '$($cfg.BaseUrl)/api/'."
    try {
        $headers = @{ Authorization = "Bearer $($cfg.Token)" }
        $params = @{
            Uri        = "$($cfg.BaseUrl)/api/"
            Headers    = $headers
            TimeoutSec = 10
        }
        if ($cfg.SkipCertificateCheck) { $params.SkipCertificateCheck = $true }
        $resp = Invoke-RestMethod @params
        Write-Verbose ("HA responded: {0}" -f $resp.message)
    } catch {
        Write-Warning "Config saved, but connectivity check failed: $($_.Exception.Message)"
    }
}
