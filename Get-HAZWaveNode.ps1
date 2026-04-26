function Get-HAZWaveNode {
    <#
    .SYNOPSIS
    Inventory of every Z-Wave node known to Home Assistant, with the
    metadata available from the device registry.

    .DESCRIPTION
    Walks every entity owned by the `zwave_js` integration, dedupes to
    one record per device, and resolves Z-Wave node_id from the device's
    identifiers. Returns a PwrHass.ZWaveNode per device with:

      NodeId           Z-Wave node_id (1 = controller, others are nodes)
      Manufacturer     device.manufacturer
      Model            device.model
      SoftwareVersion  device.sw_version (firmware)
      HardwareVersion  device.hw_version
      Name             device.name_by_user (or device.name)
      DeviceId         HA device UUID (handy for further lookups)
      EntryId          HA config-entry UUID (for Restart-HAIntegration)

    Resolved in a single template-engine round trip rather than per
    device.

    Note: HA's device registry does NOT expose Z-Wave security class
    (None / S0 / S2-Authenticated). That information lives in Z-Wave-JS
    over its WebSocket, not REST. Use the Z-Wave-JS UI add-on to confirm
    security classification per node.

    .PARAMETER IncludeController
    Include the controller (typically node 1). Hidden by default since
    most reports want endpoints, not the stick itself.

    .EXAMPLE
    Get-HAZWaveNode | Sort-Object NodeId

    .EXAMPLE
    # Group by model to spot legacy hardware
    Get-HAZWaveNode | Group-Object Model | Sort-Object Count -Descending |
        Format-Table Count, Name -AutoSize

    .EXAMPLE
    # Filter to mains-powered candidates by inferring from model name
    Get-HAZWaveNode | Where Model -match 'ZW(10|30|40)\d{2}|WD500Z'
    #>
    [CmdletBinding()]
    [OutputType('PwrHass.ZWaveNode')]
    param(
        [switch]$IncludeController
    )

    $cfg = Get-HAConfig
    $headers = @{ Authorization = "Bearer $($cfg.Token)"; 'Content-Type' = 'application/json' }

    $tpl = @'
{%- set ents = integration_entities('zwave_js') -%}
{%- set ns = namespace(devices=[]) -%}
{%- for e in ents -%}
{%- set d = device_id(e) -%}
{%- if d and d not in ns.devices -%}{%- set ns.devices = ns.devices + [d] -%}{%- endif -%}
{%- endfor -%}
{%- for d in ns.devices -%}
{%- set inner = namespace(node_id='?') -%}
{%- for id in device_attr(d, 'identifiers') | list if id[0] == 'zwave_js' and ':' not in id[1] -%}
{%- set inner.node_id = id[1].split('-')[1] -%}
{%- endfor -%}
{%- set entries = device_attr(d, 'config_entries') -%}
{%- set entry_id = (entries | first) if entries else '' -%}
{{ inner.node_id }}|{{ device_attr(d, 'manufacturer') | default('', true) }}|{{ device_attr(d, 'model') | default('', true) }}|{{ device_attr(d, 'sw_version') | default('', true) }}|{{ device_attr(d, 'hw_version') | default('', true) }}|{{ device_attr(d, 'name_by_user') or device_attr(d, 'name') or '' }}|{{ d }}|{{ entry_id }}
{% endfor -%}
'@

    Write-Verbose "Posting Z-Wave inventory template to HA."
    $body = @{ template = $tpl } | ConvertTo-Json -Compress
    $params = @{
        Method     = 'Post'
        Uri        = "$($cfg.BaseUrl)/api/template"
        Headers    = $headers
        Body       = $body
        TimeoutSec = 90
    }
    if ($cfg.SkipCertificateCheck) { $params.SkipCertificateCheck = $true }
    $resp = Invoke-RestMethod @params

    foreach ($line in ($resp -split "`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        $parts = $line -split '\|', 8
        if ($parts.Count -lt 8) { continue }

        $nodeId = if ($parts[0] -match '^\d+$') { [int]$parts[0] } else { $null }
        if (-not $IncludeController -and $nodeId -eq 1) { continue }

        $rec = [PSCustomObject]@{
            PSTypeName       = 'PwrHass.ZWaveNode'
            NodeId           = $nodeId
            Manufacturer     = $parts[1]
            Model            = $parts[2]
            SoftwareVersion  = $parts[3]
            HardwareVersion  = $parts[4]
            Name             = $parts[5]
            DeviceId         = $parts[6]
            EntryId          = $parts[7]
        }
        $rec
    }
}
