function Get-HAEntityCorrelation {
    <#
    .SYNOPSIS
    Bucket a numeric Home Assistant entity's history by the active state of
    one or more boolean / categorical indicator entities.

    .DESCRIPTION
    Pulls per-entity history from /api/history/period for a -Numeric entity
    and one or more -Indicator entities, then samples each at -StepMinutes
    resolution as a step function. For each sample, it forms a bucket key
    from the indicator activations (per -Predicate) and accumulates the
    numeric value into that bucket.

    Returns one PwrHass.EntityCorrelationBucket per observed combination of
    indicator states, with sample count, mean, p50, p90 and max.

    Two common uses:

    1. Correlating a power sensor (like a Sense-detected device) with the
       on/off state of one or more candidate physical devices, to verify
       which device the power reading actually represents.

    2. Bucketing any continuous sensor (vent pressure, vent temperature,
       sub-meter power, etc.) by another entity's state to see how that
       state explains the variation.

    .PARAMETER Numeric
    The continuous numeric entity to bucket (e.g. sensor.heat_pump_power).

    .PARAMETER Indicator
    One or more entity ids whose active/inactive state defines the bucket
    grouping. Can be passed by name or pipeline.

    .PARAMETER Hours
    History window ending now. Default 24. Mutually exclusive with
    -StartTime / -EndTime.

    .PARAMETER StartTime
    Explicit window start (UTC will be sent to HA). Use with -EndTime.

    .PARAMETER EndTime
    Explicit window end. Defaults to now if -StartTime is given alone.

    .PARAMETER Predicate
    Hashtable of entity_id -> scriptblock returning $true when the entity
    is "active" for bucketing. Each scriptblock receives the raw history
    sample piped in (use $_ to inspect, e.g. $_.state, $_.attributes.x).
    Default heuristic:

      - state in 'on','heating','cooling','open','playing','home','active'
        -> active
      - hvac_action attribute (any entity) in 'heating','cooling' -> active
      - everything else -> inactive

    .PARAMETER StepMinutes
    Sample resolution. Default 1 (one sample per minute). Smaller =
    higher fidelity, more memory; larger = coarser, faster.

    .EXAMPLE
    Get-HAEntityCorrelation -Numeric sensor.heat_pump_power `
        -Indicator climate.thermostat,
                   binary_sensor.heat_pump_water_heater_running

    .EXAMPLE
    Get-HAEntityCorrelation -Numeric sensor.whole_home_vent_average_pressure `
        -Indicator climate.thermostat -Hours 6 |
        Sort-Object Mean -Descending

    .EXAMPLE
    # Custom predicate using $_ for the history sample
    $pred = @{ 'climate.thermostat' = { $_.attributes.hvac_action -eq 'cooling' } }
    Get-HAEntityCorrelation -Numeric sensor.heat_pump_power `
        -Indicator climate.thermostat -Predicate $pred
    #>
    [CmdletBinding(DefaultParameterSetName = 'Hours')]
    [OutputType('PwrHass.EntityCorrelationBucket')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[a-z_]+\.[a-z0-9_]+$')]
        [string]$Numeric,

        [Parameter(Mandatory, Position = 1)]
        [ValidatePattern('^[a-z_]+\.[a-z0-9_]+$')]
        [string[]]$Indicator,

        [Parameter(ParameterSetName = 'Hours')]
        [ValidateRange(1, 8760)]
        [int]$Hours = 24,

        [Parameter(ParameterSetName = 'Range', Mandatory)]
        [datetime]$StartTime,

        [Parameter(ParameterSetName = 'Range')]
        [datetime]$EndTime = (Get-Date),

        [hashtable]$Predicate = @{},

        [ValidateRange(1, 60)]
        [int]$StepMinutes = 1
    )

    $cfg = Get-HAConfig
    $headers = @{ Authorization = "Bearer $($cfg.Token)" }
    $common = @{ Headers = $headers; TimeoutSec = 60 }
    if ($cfg.SkipCertificateCheck) { $common.SkipCertificateCheck = $true }

    if ($PSCmdlet.ParameterSetName -eq 'Hours') {
        $end = (Get-Date).ToUniversalTime()
        $start = $end.AddHours(-$Hours)
    } else {
        $start = $StartTime.ToUniversalTime()
        $end = $EndTime.ToUniversalTime()
    }
    if ($end -le $start) { throw "EndTime ($end) must be after StartTime ($start)." }

    $startIso = $start.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endIso = $end.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $allEntities = @($Numeric) + @($Indicator)
    $filter = $allEntities -join ','
    $uri = "$($cfg.BaseUrl)/api/history/period/$($startIso)?end_time=$($endIso)&filter_entity_id=$filter"

    Write-Verbose "GET $uri"
    Write-Verbose "Window: $start UTC -> $end UTC ($($Hours)h)"
    $hist = Invoke-RestMethod @common -Uri $uri

    if (-not $hist) {
        Write-Warning "No history returned for $allEntities."
        return
    }

    $series = @{}
    foreach ($s in $hist) {
        if ($s.Count -gt 0) {
            $series[$s[0].entity_id] = @($s | Sort-Object last_changed)
        }
    }

    foreach ($id in $allEntities) {
        if (-not $series.ContainsKey($id)) {
            Write-Warning "No history for '$id' in the requested window."
            return
        }
        Write-Verbose ("  {0}: {1} samples" -f $id, $series[$id].Count)
    }

    # Default predicate: state in a known-active vocabulary, OR an
    # hvac_action attribute reports an active stage (climate entities
    # store the running stage there, not in .state which holds the mode).
    $defaultActiveStates = 'on','heating','cooling','open','playing','home','active'
    $defaultPred = {
        $st = "$($_.state)".ToLower()
        if ($st -in $defaultActiveStates) { return $true }
        $action = "$($_.attributes.hvac_action)".ToLower()
        return ($action -in 'heating','cooling')
    }

    function Get-LastBefore {
        param($samples, [datetime]$time)
        $cur = $null
        foreach ($s in $samples) {
            if ($s.last_changed -le $time) { $cur = $s } else { break }
        }
        return $cur
    }

    $stepCount = [int][math]::Floor((($end - $start).TotalMinutes) / $StepMinutes)
    Write-Verbose "Sampling $stepCount steps at $StepMinutes-minute resolution."

    # bucketKey -> @{ Indicators=ordered hashtable; Values=ArrayList; SkippedNumeric=int }
    $buckets = @{}
    $skippedNoNumeric = 0
    $skippedNoIndicator = 0

    for ($i = 0; $i -lt $stepCount; $i++) {
        $t = $start.AddMinutes($i * $StepMinutes)

        $numSample = Get-LastBefore $series[$Numeric] $t
        if (-not $numSample) { $skippedNoNumeric++; continue }
        $numVal = $null
        try {
            $raw = "$($numSample.state)"
            if ($raw -in 'unavailable','unknown','none','') { continue }
            $numVal = [double]$raw
        } catch { continue }
        if ([double]::IsNaN($numVal)) { continue }

        # Build the bucket key from each indicator's activation
        $indicatorStates = [ordered]@{}
        $missing = $false
        foreach ($ind in $Indicator) {
            $sample = Get-LastBefore $series[$ind] $t
            if (-not $sample) { $missing = $true; break }
            $pred = if ($Predicate.ContainsKey($ind)) { $Predicate[$ind] } else { $defaultPred }
            # Pipe the sample so $_ inside the scriptblock refers to it
            # (& $pred $sample would put it in $args instead).
            $isActive = $sample | ForEach-Object $pred
            $indicatorStates[$ind] = [bool]$isActive
        }
        if ($missing) { $skippedNoIndicator++; continue }

        $key = ($indicatorStates.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$($_.Value)"
        }) -join ';'

        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = @{
                Indicators = $indicatorStates
                Values = New-Object System.Collections.ArrayList
            }
        }
        [void]$buckets[$key].Values.Add($numVal)
    }

    if ($skippedNoNumeric -gt 0) {
        Write-Verbose "$skippedNoNumeric samples skipped: numeric value missing/unparseable."
    }
    if ($skippedNoIndicator -gt 0) {
        Write-Verbose "$skippedNoIndicator samples skipped: indicator value not yet recorded."
    }

    $stepMin = $StepMinutes  # capture for nested helper
    foreach ($entry in $buckets.GetEnumerator()) {
        $vals = @($entry.Value.Values | Sort-Object)
        $n = $vals.Count
        if ($n -eq 0) { continue }
        $mean = ($vals | Measure-Object -Average).Average
        $p50 = $vals[[int][math]::Floor($n * 0.5)]
        $p90 = $vals[[int][math]::Floor($n * 0.9)]
        $mx  = ($vals | Measure-Object -Maximum).Maximum

        [PSCustomObject]@{
            PSTypeName    = 'PwrHass.EntityCorrelationBucket'
            Numeric       = $Numeric
            Indicators    = $entry.Value.Indicators
            SampleCount   = $n
            SampleMinutes = $n * $stepMin
            Mean          = [math]::Round($mean, 2)
            P50           = [math]::Round([double]$p50, 2)
            P90           = [math]::Round([double]$p90, 2)
            Max           = [math]::Round([double]$mx, 2)
        }
    }
}
