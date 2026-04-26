function Get-HALegacyZWaveRouter {
    <#
    .SYNOPSIS
    Identify mains-powered Z-Wave routing nodes whose silicon vintage
    predates clean S2 support — i.e. nodes that may corrupt S2 frames
    they relay for other devices.

    .DESCRIPTION
    Wraps Get-HAZWaveNode and tiers each candidate router by silicon
    generation:

      T1 gen-1               ZW1001 plug-ins. Pre-Z-Wave-Plus. NO S2. Highest-priority swap.
      T2 gen-2 (400-series)  ZW3005, ZW4005. Z-Wave Plus but no S2. Should swap.
      T3 early 500-series    WD500Z. S2 unsupported on shipped firmware. Should swap.
      T4 mid 500-series      ZW3008, ZW4006. S2 firmware-dependent (5.39+ usually OK). Watch.

    Battery-only / non-routing devices (locks, sensors, sirens, the
    controller itself) are excluded — they don't relay frames so they
    can't corrupt them. The list focuses specifically on always-on
    mains-powered devices that participate as repeaters.

    Why this matters: a single corrupting repeater in the routing path
    can cause "Dropping message with invalid payload" log spam and lead
    to the controller marking otherwise-healthy nodes as `dead`. The
    cure is to swap the legacy hardware for S2-clean equivalents
    (700/800-series silicon).

    .PARAMETER IncludeWatchlist
    Include T4 (mid 500-series) nodes that are probably OK on current
    firmware. Default: included. Pass -IncludeWatchlist:$false to see
    only the must-go T1/T2/T3 nodes.

    .PARAMETER ModelMap
    Override the model→tier classification. Default covers the most
    common GE/Jasco/Nortek legacy hardware. Add custom entries for
    other vendors as needed:
      @{ 'YOUR_MODEL_REGEX' = 'T1 your-tier-label' }

    .EXAMPLE
    Get-HALegacyZWaveRouter

    .EXAMPLE
    # Just the must-go nodes
    Get-HALegacyZWaveRouter -IncludeWatchlist:$false

    .EXAMPLE
    # Group by tier for a quick swap-priority view
    Get-HALegacyZWaveRouter | Group-Object Tier | Format-Table Count, Name -AutoSize
    #>
    [CmdletBinding()]
    [OutputType('PwrHass.LegacyZWaveRouter')]
    param(
        [bool]$IncludeWatchlist = $true,

        [hashtable]$ModelMap = @{
            'ZW1001' = 'T1 gen-1 (no S2)'
            'ZW3005' = 'T2 gen-2 (no S2)'
            'ZW4005' = 'T2 gen-2 (no S2)'
            'WD500Z' = 'T3 early-500 (no S2)'
            'ZW3008' = 'T4 mid-500 (firmware-dependent)'
            'ZW4006' = 'T4 mid-500 (firmware-dependent)'
        }
    )

    $regex = '(' + (($ModelMap.Keys) -join '|') + ')'

    Get-HAZWaveNode |
        Where-Object { $_.Model -match $regex } |
        ForEach-Object {
            $tier = $null
            foreach ($k in $ModelMap.Keys) {
                if ($_.Model -match $k) { $tier = $ModelMap[$k]; break }
            }
            if (-not $IncludeWatchlist -and $tier -like 'T4*') { return }

            $rec = [PSCustomObject]@{
                Tier            = $tier
                NodeId          = $_.NodeId
                Model           = $_.Model
                SoftwareVersion = $_.SoftwareVersion
                Name            = $_.Name
                DeviceId        = $_.DeviceId
            }
            $rec.PSTypeNames.Insert(0, 'PwrHass.LegacyZWaveRouter')
            $rec
        } | Sort-Object Tier, NodeId
}
