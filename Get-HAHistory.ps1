function Get-HAHistory {
    <#
    .SYNOPSIS
    Retrieve raw state history for one or more Home Assistant entities.

    .DESCRIPTION
    Pulls per-entity history from /api/history/period and emits one flat
    object per recorded state change, with the numeric value already parsed
    where possible. This is the general-purpose history accessor; use
    Get-HAEntityCorrelation instead when you specifically want a numeric
    series bucketed by another entity's active state.

    Non-numeric states ('unknown', 'unavailable', text states) are emitted
    with Value = $null unless -NumericOnly is supplied, so gaps and sensor
    dropouts stay visible rather than being silently discarded.

    Home Assistant returns timestamps in UTC. The LastChanged property is
    converted to local time, and LastChangedUtc preserves the original.

    .PARAMETER EntityId
    One or more entity IDs to fetch. Accepts pipeline input.

    .PARAMETER Hours
    Size of the lookback window ending now. Defaults to 24.

    .PARAMETER StartTime
    Explicit window start. Use with -EndTime instead of -Hours.

    .PARAMETER EndTime
    Explicit window end. Defaults to now when -StartTime is given.

    .PARAMETER NumericOnly
    Drop samples whose state will not parse as a number.

    .PARAMETER MinimalResponse
    Ask Home Assistant to omit attributes from the response. Substantially
    faster and smaller for long windows on chatty entities.

    .EXAMPLE
    Get-HAHistory sensor.tank_distance_raw -Hours 96

    .EXAMPLE
    Get-HAHistory sensor.tank_distance_raw, sensor.tank_level -Hours 96 -NumericOnly |
        Group-Object { $_.LastChanged.Hour } | Sort-Object Name

    .EXAMPLE
    Get-HAHistory sensor.foo -StartTime (Get-Date).AddDays(-7) -EndTime (Get-Date).AddDays(-6)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Hours')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$EntityId,

        [Parameter(ParameterSetName = 'Hours')]
        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [Parameter(ParameterSetName = 'Range', Mandatory)]
        [datetime]$StartTime,

        [Parameter(ParameterSetName = 'Range')]
        [datetime]$EndTime = (Get-Date),

        [switch]$NumericOnly,

        [switch]$MinimalResponse
    )

    begin {
        $collected = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($id in $EntityId) { $collected.Add($id) }
    }

    end {
        $cfg = Get-HAConfig
        if (-not $cfg) {
            Write-Error "Not connected. Run Connect-HomeAssistant first."
            return
        }

        $headers = @{ Authorization = "Bearer $($cfg.Token)" }
        $common = @{ Headers = $headers; TimeoutSec = 120 }
        if ($cfg.SkipCertificateCheck) { $common.SkipCertificateCheck = $true }

        if ($PSCmdlet.ParameterSetName -eq 'Hours') {
            $end = (Get-Date).ToUniversalTime()
            $start = $end.AddHours(-$Hours)
        } else {
            $start = $StartTime.ToUniversalTime()
            $end = $EndTime.ToUniversalTime()
        }
        if ($end -le $start) { throw "EndTime ($end) must be after StartTime ($start)." }

        $startIso = $start.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $endIso = $end.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $filter = ($collected | Select-Object -Unique) -join ','

        $uri = "$($cfg.BaseUrl)/api/history/period/$($startIso)?end_time=$($endIso)&filter_entity_id=$filter"
        if ($MinimalResponse) { $uri += '&minimal_response' }

        Write-Verbose "Window: $start UTC -> $end UTC"
        Write-Verbose "GET $uri"

        try {
            $hist = Invoke-RestMethod @common -Uri $uri -ErrorAction Stop
        } catch {
            Write-Error "History request failed: $($_.Exception.Message)"
            return
        }

        if (-not $hist) {
            Write-Warning "No history returned for: $filter"
            return
        }

        $emitted = 0
        $skipped = 0
        foreach ($series in $hist) {
            if ($series.Count -eq 0) { continue }
            # minimal_response omits entity_id on all but the first sample.
            $seriesId = $series[0].entity_id

            foreach ($s in $series) {
                $val = $null
                $parsed = 0.0
                if ([double]::TryParse($s.state, [ref]$parsed)) {
                    $val = $parsed
                } elseif ($NumericOnly) {
                    $skipped++
                    continue
                }

                # HA sends ISO8601 with offset; the cast localises it, so
                # normalise back to UTC explicitly rather than assuming kind.
                $utc = ([datetime]$s.last_changed).ToUniversalTime()
                [pscustomobject]@{
                    PSTypeName     = 'PwrHass.HistorySample'
                    EntityId       = if ($s.entity_id) { $s.entity_id } else { $seriesId }
                    State          = $s.state
                    Value          = $val
                    LastChanged    = $utc.ToLocalTime()
                    LastChangedUtc = $utc
                }
                $emitted++
            }
        }

        Write-Verbose "Emitted $emitted sample(s); skipped $skipped non-numeric."
        if ($emitted -eq 0) {
            Write-Warning "History returned no usable samples for: $filter"
        }
    }
}
