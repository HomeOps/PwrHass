function Invoke-HAService {
    <#
    .SYNOPSIS
    Call a Home Assistant service against an entity.

    .DESCRIPTION
    Wraps POST /api/services/<domain>/<service>. By default the domain is
    derived from the entity id (everything before the first dot); pass
    -Domain to override when the service lives on a different integration
    than the entity (e.g. zwave_js.refresh_value targeting a sensor.*).
    Connection details are read from ~/.pwrhass/config.json
    (Connect-HomeAssistant first).

    .PARAMETER EntityId
    Target entity, e.g. 'light.den_bookshelve' or 'cover.kitchen_vent'.

    .PARAMETER Service
    Service name on the target domain (e.g. 'turn_on',
    'set_cover_position', 'refresh_value'). Defaults to 'turn_on'; pass
    -Off for the matching 'turn_off' shorthand.

    .PARAMETER Data
    Extra body fields merged into the request payload alongside entity_id.
    Example: @{ position = 100 } for cover.set_cover_position.

    .PARAMETER Off
    Shorthand: when set and -Service is unset, calls 'turn_off' instead of 'turn_on'.

    .PARAMETER Domain
    Override the service domain. Defaults to the entity's domain prefix.
    Use this for cross-integration services like zwave_js.refresh_value
    against a sensor.*, or homeassistant.turn_off against any entity.

    .EXAMPLE
    Invoke-HAService -EntityId light.den_bookshelve

    .EXAMPLE
    Invoke-HAService -EntityId light.den_bookshelve -Off

    .EXAMPLE
    Invoke-HAService -EntityId cover.kitchen_vent `
                     -Service set_cover_position `
                     -Data @{ position = 100 }

    .EXAMPLE
    # Force a Z-Wave node to push fresh values to HA
    Invoke-HAService -EntityId sensor.east_bedroom_sensor_air_temperature `
                     -Domain zwave_js -Service refresh_value
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[a-z_]+\.[a-z0-9_]+$')]
        [string]$EntityId,

        [Parameter(Position = 1)]
        [string]$Service,

        [hashtable]$Data,

        [switch]$Off,

        [string]$Domain
    )

    if (-not $Service) {
        $Service = if ($Off) { 'turn_off' } else { 'turn_on' }
    }

    $cfg = Get-HAConfig
    if (-not $Domain) { $Domain = $EntityId.Split('.')[0] }
    $uri = "$($cfg.BaseUrl)/api/services/$Domain/$Service"

    $payload = @{ entity_id = $EntityId }
    if ($Data) {
        foreach ($k in $Data.Keys) { $payload[$k] = $Data[$k] }
    }
    $body = $payload | ConvertTo-Json -Compress

    if (-not $PSCmdlet.ShouldProcess($EntityId, "$Domain.$Service")) { return }

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
