function Restart-HAIntegration {
    <#
    .SYNOPSIS
    Reload a Home Assistant integration's config entry.

    .DESCRIPTION
    Wraps `homeassistant.reload_config_entry`. Either pass `-EntryId` (the
    config-entry UUID, which you can copy from the integration's URL in
    Settings → Devices & Services) or `-EntityId` (any entity that belongs
    to the integration; HA will resolve the config entry from it).

    Common use: bring a Z-Wave-JS or Zigbee integration back into sync
    after the underlying mesh has stalled and been recovered. Faster
    than restarting all of Home Assistant.

    .PARAMETER EntityId
    Any entity that belongs to the integration you want to reload.
    HA looks up its config entry and reloads that. Easier than finding
    the entry_id UUID by hand.

    .PARAMETER EntryId
    The config-entry UUID directly. Use when no entity exists or when
    you've cached the UUID.

    .EXAMPLE
    # Reload Z-Wave-JS by pointing at any Z-Wave entity
    Restart-HAIntegration -EntityId sensor.den_sensor_node_status

    .EXAMPLE
    # Reload by entry UUID
    Restart-HAIntegration -EntryId 8955375327824e14ba89e4b29cc3ec9a
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High',
                   DefaultParameterSetName = 'ByEntity')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByEntity', Position = 0)]
        [ValidatePattern('^[a-z_]+\.[a-z0-9_]+$')]
        [string]$EntityId,

        [Parameter(Mandatory, ParameterSetName = 'ByEntryId')]
        [ValidatePattern('^[0-9a-f]{32}$')]
        [string]$EntryId
    )

    $cfg = Get-HAConfig
    $payload = if ($PSCmdlet.ParameterSetName -eq 'ByEntryId') {
        @{ entry_id = $EntryId }
    } else {
        @{ entity_id = $EntityId }
    }
    $body = $payload | ConvertTo-Json -Compress

    $target = if ($EntryId) { "entry_id $EntryId" } else { "entity_id $EntityId" }
    if (-not $PSCmdlet.ShouldProcess($target, 'homeassistant.reload_config_entry')) { return }

    $uri = "$($cfg.BaseUrl)/api/services/homeassistant/reload_config_entry"
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
        TimeoutSec = 60
    }
    if ($cfg.SkipCertificateCheck) { $params.SkipCertificateCheck = $true }

    Invoke-RestMethod @params
}
