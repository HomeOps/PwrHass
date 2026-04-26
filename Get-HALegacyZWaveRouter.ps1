function Get-HALegacyZWaveRouter {
    <#
    .SYNOPSIS
    Identify mains-powered Z-Wave routing nodes whose silicon vintage
    predates clean S2 support — i.e. nodes that may corrupt S2 frames
    they relay for other devices.

    .DESCRIPTION
    Wraps Get-HAZWaveNode and assigns each candidate router a numeric
    Priority and a Generation label:

      Priority 1 (replace)       No S2 capability at all. ZW1001, ZW3005,
                                 ZW4005, WD500Z. Will never carry S2 frames
                                 cleanly regardless of firmware. Replace.
      Priority 2 (watch)         S2 firmware-dependent. ZW3008, ZW4006.
                                 Modern firmware (5.39+) usually OK; early
                                 firmware in this family had SPAN-cache and
                                 FLiRS-beam bugs.

    Battery-only / non-routing devices (locks, sensors, sirens, the
    controller itself) are excluded — they don't relay frames so they
    can't corrupt them.

    Default sort is Priority ascending, then NodeId ascending — worst
    devices first.

    .PARAMETER IncludeWatchlist
    Include Priority-2 (firmware-dependent) nodes. Default: $true.
    Pass -IncludeWatchlist:$false to see only Priority-1 (must-replace).

    .PARAMETER ModelMap
    Override the model→{Priority, Generation} classification. Format:
      @{ 'MODEL_REGEX' = @{ Priority = N; Generation = 'label' } }

    .EXAMPLE
    Get-HALegacyZWaveRouter

    .EXAMPLE
    Get-HALegacyZWaveRouter -IncludeWatchlist:$false   # must-replace only

    .EXAMPLE
    Get-HALegacyZWaveRouter | Group-Object Priority | Format-Table Count, Name -AutoSize
    #>
    [CmdletBinding()]
    [OutputType('PwrHass.LegacyZWaveRouter')]
    param(
        [bool]$IncludeWatchlist = $true,

        [hashtable]$ModelMap = @{
            'ZW1001' = @{ Priority = 1; Generation = 'gen-1';     PriorityReason = 'no S2 (pre-Z-Wave-Plus)' }
            'ZW3005' = @{ Priority = 1; Generation = 'gen-2';     PriorityReason = 'no S2 (400-series)' }
            'ZW4005' = @{ Priority = 1; Generation = 'gen-2';     PriorityReason = 'no S2 (400-series)' }
            'WD500Z' = @{ Priority = 1; Generation = 'early-500'; PriorityReason = 'no S2 in shipped firmware' }
            'ZW3008' = @{ Priority = 2; Generation = 'mid-500';   PriorityReason = 'S2 firmware-dependent' }
            'ZW4006' = @{ Priority = 2; Generation = 'mid-500';   PriorityReason = 'S2 firmware-dependent' }
        }
    )

    $regex = '(' + (($ModelMap.Keys) -join '|') + ')'

    Get-HAZWaveNode |
        Where-Object { $_.Model -match $regex } |
        ForEach-Object {
            $entry = $null
            foreach ($k in $ModelMap.Keys) {
                if ($_.Model -match $k) { $entry = $ModelMap[$k]; break }
            }
            if (-not $entry) { return }
            if (-not $IncludeWatchlist -and $entry.Priority -ge 2) { return }

            $rec = [PSCustomObject]@{
                Priority        = [int]$entry.Priority
                PriorityReason  = $entry.PriorityReason
                Generation      = $entry.Generation
                NodeId          = $_.NodeId
                Model           = $_.Model
                SoftwareVersion = $_.SoftwareVersion
                Name            = $_.Name
                DeviceId        = $_.DeviceId
            }
            $rec.PSTypeNames.Insert(0, 'PwrHass.LegacyZWaveRouter')
            $rec
        } | Sort-Object Priority, NodeId
}
