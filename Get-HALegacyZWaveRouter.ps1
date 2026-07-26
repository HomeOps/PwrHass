function Get-HALegacyZWaveRouter {
    <#
    .SYNOPSIS
    Identify mains-powered Z-Wave routing nodes whose silicon vintage
    or installed firmware predates clean S2 support — i.e. nodes that
    may corrupt S2 frames they relay for other devices. Ranks with
    fractional priorities so worst-in-class is distinguishable from
    bad-but-modern.

    .DESCRIPTION
    Wraps Get-HAZWaveNode and assigns each candidate router a numeric
    Priority (double) and a Generation label, taking chip family,
    Z-Wave Plus support, data-rate class, beaming capability, and the
    actually-installed firmware version into account.

    Priority scale (lower = worse, decimals are meaningful):

      1.1 — worst legacy router. Pre-Z-Wave-Plus 300-series silicon:
            40 kbps max, no beaming, no S2. Drags every route that
            passes through it down to 40 kbps. (ZW1001.)

      1.5 — Z-Wave Plus capable router with no usable S2. 100 kbps,
            beaming-capable, but cannot carry S2 frames cleanly.
            Doesn't slow neighbors but still corrupts encrypted relays.
            (ZW3005, ZW4005, WD500Z, and mid-500 chips like ZW3008 /
            ZW4006 whose installed firmware is below MinSafeFirmware
            and whose OEM never shipped a clean firmware — e.g.
            GE/Enbrighten 26933 stuck at 5.32.)

      2.0 — mid-500 chip family on firmware at or above MinSafeFirmware.
            Historical S2 bugs (SPAN-cache, FLiRS-beam) were fixed at
            the chip-family level by FW ≥ 5.39, but OEM products may
            not have inherited those fixes — monitor and verify against
            the device's actual `security` field in Z-Wave-JS-UI.
            (ZW3008, ZW4006 at firmware ≥ 5.39.)

      3.0+ — reserved for future watchlist categories (Z-Wave Plus 2
            informational, Z-Wave Long Range advisories, etc.).

    Battery-only / non-routing devices (locks, sensors, sirens, the
    controller itself) are excluded — they don't relay frames so they
    can't corrupt them.

    Default sort is Priority ascending, then NodeId ascending — worst
    devices first.

    HA's device registry does NOT expose the authoritative S2 capability
    (`supportsSecurity`, `security`) — that lives in Z-Wave-JS over
    WebSocket. The chip-family + firmware heuristic here is the best
    REST-only approximation. For ground truth on any flagged node, open
    Z-Wave-JS-UI → Node → check `Security` field.

    .PARAMETER IncludeWatchlist
    Include Priority ≥ 2 (firmware-dependent) nodes. Default: $true.
    Pass -IncludeWatchlist:$false to see only must-replace (Priority < 2).

    .PARAMETER ModelMap
    Override the model→classification map. Each entry is keyed by a
    regex matched against `Get-HAZWaveNode`'s Model field. Value
    hashtable supports:

      Priority             (double) Default classification before firmware check.
      Generation           (string) Free-form label ('gen-1', 'mid-500', etc.).
      PriorityReason       (string) One-line explanation surfaced in output.
      MinSafeFirmware      (string) Optional. Nodes whose SoftwareVersion is
                                    less than this (parsed as [version]) are
                                    promoted from their default Priority down
                                    to BelowMinSafePriority, with reason
                                    updated to explain the version gap.
      BelowMinSafePriority (double) Optional. The promoted priority when
                                    firmware is below MinSafeFirmware.
                                    Defaults to 1.5 (the "ZWP + no S2"
                                    bucket) — appropriate for mid-500 chips
                                    that retain Z-Wave Plus / 100 kbps /
                                    beaming features even when S2 is broken.

    .EXAMPLE
    Get-HALegacyZWaveRouter

    .EXAMPLE
    Get-HALegacyZWaveRouter -IncludeWatchlist:$false   # must-replace only (Priority < 2)

    .EXAMPLE
    Get-HALegacyZWaveRouter -Verbose                   # show per-node decisions

    .EXAMPLE
    Get-HALegacyZWaveRouter | Group-Object Priority | Format-Table Count, Name -AutoSize
    #>
    [CmdletBinding()]
    [OutputType('PwrHass.LegacyZWaveRouter')]
    param(
        [bool]$IncludeWatchlist = $true,

        [hashtable]$ModelMap = @{
            'ZW1001' = @{ Priority = 1.1; Generation = 'gen-1';     PriorityReason = '40 kbps, pre-Z-Wave-Plus, no beaming, no S2' }
            'ZW3005' = @{ Priority = 1.5; Generation = 'gen-2';     PriorityReason = '100 kbps Z-Wave Plus, no S2 (400-series)' }
            'ZW4005' = @{ Priority = 1.5; Generation = 'gen-2';     PriorityReason = '100 kbps Z-Wave Plus, no S2 (400-series)' }
            'WD500Z' = @{ Priority = 1.5; Generation = 'early-500'; PriorityReason = '100 kbps Z-Wave Plus, no S2 in shipped firmware' }
            'ZW3008' = @{ Priority = 2.0; Generation = 'mid-500';   PriorityReason = 'S2 firmware-dependent (≥5.39)';
                          MinSafeFirmware = '5.39'; BelowMinSafePriority = 1.5 }
            'ZW4006' = @{ Priority = 2.0; Generation = 'mid-500';   PriorityReason = 'S2 firmware-dependent (≥5.39)';
                          MinSafeFirmware = '5.39'; BelowMinSafePriority = 1.5 }
        }
    )

    # Compare two firmware strings as [version] (1.2.3.4 layout). Returns
    # $true when $Actual is strictly less than $Min. Falls back to a
    # lexical compare when either string isn't parseable.
    function Test-FirmwareBelow {
        param([string]$Actual, [string]$Min)
        if ([string]::IsNullOrWhiteSpace($Actual) -or [string]::IsNullOrWhiteSpace($Min)) { return $false }
        try {
            return ([version]$Actual) -lt ([version]$Min)
        } catch {
            Write-Verbose "Firmware '$Actual' vs '$Min' not parseable as [version]; lexical compare."
            return ([string]::Compare($Actual, $Min) -lt 0)
        }
    }

    $regex = '(' + (($ModelMap.Keys) -join '|') + ')'
    Write-Verbose "Matching node models against: $regex"

    Get-HAZWaveNode |
        Where-Object { $_.Model -match $regex } |
        ForEach-Object {
            $node = $_
            $entry = $null
            $matchedKey = $null
            foreach ($k in $ModelMap.Keys) {
                if ($node.Model -match $k) { $entry = $ModelMap[$k]; $matchedKey = $k; break }
            }
            if (-not $entry) { return }

            $priority   = [double]$entry.Priority
            $reason     = [string]$entry.PriorityReason
            $generation = [string]$entry.Generation

            # Promote to the chip's BelowMinSafePriority when installed
            # firmware is below the known-clean threshold. A mid-500 chip
            # on stale firmware loses S2 cleanly but still has Z-Wave Plus
            # / 100 kbps / beaming — so promote to 1.5 (the ZWP-no-S2
            # bucket) by default, not all the way to 1.1 (the worst-bucket
            # reserved for pre-ZWP 40 kbps silicon). When the OEM never
            # shipped a fix (e.g. GE/Enbrighten 26933 / ZW3008 stuck at
            # 5.32 — Jasco's firmware repo only contains 5.32) the
            # promotion is effectively permanent.
            if ($entry.ContainsKey('MinSafeFirmware') -and $entry.MinSafeFirmware) {
                if (Test-FirmwareBelow -Actual $node.SoftwareVersion -Min $entry.MinSafeFirmware) {
                    $belowPri = if ($entry.ContainsKey('BelowMinSafePriority')) {
                        [double]$entry.BelowMinSafePriority
                    } else { 1.5 }
                    Write-Verbose "[Node $($node.NodeId)] $matchedKey FW $($node.SoftwareVersion) < MinSafe $($entry.MinSafeFirmware); promoting Priority $priority -> $belowPri."
                    $priority = $belowPri
                    $reason   = "$matchedKey FW $($node.SoftwareVersion) below MinSafe $($entry.MinSafeFirmware); 100 kbps Z-Wave Plus, no clean S2 path"
                } else {
                    Write-Verbose "[Node $($node.NodeId)] $matchedKey FW $($node.SoftwareVersion) >= MinSafe $($entry.MinSafeFirmware); keeping default Priority $priority."
                }
            }

            if (-not $IncludeWatchlist -and $priority -ge 2) { return }

            $rec = [PSCustomObject]@{
                Priority        = $priority
                PriorityReason  = $reason
                Generation      = $generation
                NodeId          = $node.NodeId
                Model           = $node.Model
                SoftwareVersion = $node.SoftwareVersion
                Name            = $node.Name
                DeviceId        = $node.DeviceId
            }
            $rec.PSTypeNames.Insert(0, 'PwrHass.LegacyZWaveRouter')
            $rec
        } | Sort-Object Priority, NodeId
}
