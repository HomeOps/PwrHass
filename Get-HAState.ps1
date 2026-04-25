function Get-HAState {
    <#
    .SYNOPSIS
    Fetch one or more entity states from Home Assistant.

    .DESCRIPTION
    Wraps GET /api/states[/<entity_id>]. With no -EntityId, returns every
    entity in the registry; with one or more, returns just those.

    .PARAMETER EntityId
    Fully qualified entity id (e.g. 'cover.kitchen_vent'). Accepts pipeline
    input. Omit to dump all states.

    .EXAMPLE
    Get-HAState climate.smart_climate

    .EXAMPLE
    'cover.kitchen_vent','cover.den_vent' | Get-HAState | Select entity_id, state
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Position = 0)]
        [string[]]$EntityId
    )

    begin {
        $cfg = Get-HAConfig
        $headers = @{ Authorization = "Bearer $($cfg.Token)" }
        $common = @{
            Headers    = $headers
            TimeoutSec = 30
        }
        if ($cfg.SkipCertificateCheck) { $common.SkipCertificateCheck = $true }
    }

    process {
        if (-not $EntityId) {
            Write-Verbose "Fetching all states from '$($cfg.BaseUrl)/api/states'."
            Invoke-RestMethod @common -Uri "$($cfg.BaseUrl)/api/states"
            return
        }

        foreach ($id in $EntityId) {
            $uri = "$($cfg.BaseUrl)/api/states/$id"
            Write-Verbose "GET $uri"
            try {
                Invoke-RestMethod @common -Uri $uri
            } catch {
                Write-Error "Failed to fetch '$id': $($_.Exception.Message)"
            }
        }
    }
}
