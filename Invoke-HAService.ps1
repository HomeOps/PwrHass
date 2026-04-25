function Invoke-HAService {
    <#
    .SYNOPSIS
    Call a Home Assistant service against an entity.

    .DESCRIPTION
    Wraps POST /api/services/<domain>/<service>. The domain is derived from
    the entity id (everything before the first dot). Connection details are
    read from ~/.pwrhass/config.json (Connect-HomeAssistant first).

    .PARAMETER EntityId
    Target entity, e.g. 'light.den_bookshelve' or 'cover.kitchen_vent'.

    .PARAMETER Service
    Service name on the entity's domain (e.g. 'turn_on', 'set_cover_position').
    Defaults to 'turn_on'; pass -Off for the matching 'turn_off' shorthand.

    .PARAMETER Data
    Extra body fields merged into the request payload alongside entity_id.
    Example: @{ position = 100 } for cover.set_cover_position.

    .PARAMETER Off
    Shorthand: when set and -Service is unset, calls 'turn_off' instead of 'turn_on'.

    .EXAMPLE
    Invoke-HAService -EntityId light.den_bookshelve

    .EXAMPLE
    Invoke-HAService -EntityId light.den_bookshelve -Off

    .EXAMPLE
    Invoke-HAService -EntityId cover.kitchen_vent `
                     -Service set_cover_position `
                     -Data @{ position = 100 }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[a-z_]+\.[a-z0-9_]+$')]
        [string]$EntityId,

        [Parameter(Position = 1)]
        [string]$Service,

        [hashtable]$Data,

        [switch]$Off
    )

    if (-not $Service) {
        $Service = if ($Off) { 'turn_off' } else { 'turn_on' }
    }

    $cfg = Get-HAConfig
    $domain = $EntityId.Split('.')[0]
    $uri = "$($cfg.BaseUrl)/api/services/$domain/$Service"

    $payload = @{ entity_id = $EntityId }
    if ($Data) {
        foreach ($k in $Data.Keys) { $payload[$k] = $Data[$k] }
    }
    $body = $payload | ConvertTo-Json -Compress

    if (-not $PSCmdlet.ShouldProcess($EntityId, "$domain.$Service")) { return }

    Write-Verbose "POST $uri  body=$body"
    $headers = @{
        Authorization  = "Bearer $($cfg.Token)"
        'Content-Type' = 'application/json'
    }
    $params = @{
        Method     = 'Post'
        Uri        = $uri
        Headers    = $headers
        Body       = $body
        TimeoutSec = 30
    }
    if ($cfg.SkipCertificateCheck) { $params.SkipCertificateCheck = $true }

    Invoke-RestMethod @params
}
