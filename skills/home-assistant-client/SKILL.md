---
name: home-assistant-client
description: "Read when reading or changing anything in Home Assistant from PowerShell - entity states, lights, covers, vents, climate, notifications - or when correlating a numeric sensor against other entities' activity. Covers PwrHass's Connect-HomeAssistant one-time config in ~/.pwrhass/config.json, Get-HAState, Invoke-HAService with its inferred domain and -Off switch, Get-HAEntityCorrelation history bucketing, and the entity-id validation and -SkipCertificateCheck conventions."
---

# PwrHass - Home Assistant from PowerShell

Talks to Home Assistant over its REST API. Connection details persist in
`~/.pwrhass/config.json`, so cmdlets need no token argument.

## One-time setup

```powershell
Connect-HomeAssistant `
    -BaseUrl 'http://duvall.calvonet.com:8123' `
    -Token (Get-Content ~\OneDrive\Documents\Passwords\wa.hass.txt -Raw).Trim()
```

Writes three fields:

| Field | Notes |
|---|---|
| `BaseUrl` | scheme + host + port, no trailing slash |
| `Token` | long-lived access token (HA → Profile → Security) |
| `SkipCertificateCheck` | true for self-signed HTTPS; persisted from the switch |

The token is plaintext in the file. The directory is `700` and the file `600` on
Linux/macOS; on Windows the user-profile ACL applies. Do not echo the token into
chat - read it from the password file as above.

## Cmdlets

| Cmdlet | Purpose |
|---|---|
| `Connect-HomeAssistant -BaseUrl <url> -Token <pat> [-SkipCertificateCheck]` | Persist config, ping `/api/` to confirm |
| `Get-HAConfig` | Read persisted config; throws if not connected |
| `Get-HAState [-EntityId <id[]>]` | GET `/api/states[/<id>]`. No id dumps everything. Pipeline-friendly |
| `Invoke-HAService -EntityId <id> [-Service <name>] [-Data <hashtable>] [-Off]` | POST `/api/services/<domain>/<service>`. Domain inferred from the entity id. Defaults to `turn_on`; `-Off` flips to `turn_off` |
| `Get-HAEntityCorrelation -Numeric <id> -Indicator <id[]> [-Hours N] [-Predicate @{}] [-StepMinutes N]` | Bucket a numeric entity's history by the active state of one or more indicator entities |

`Get-HAEntityCorrelation` pulls `/api/history/period`, samples at fixed steps and
returns per-bucket count / mean / p50 / p90 / max. Its default predicate treats
`state` in `on, heating, cooling, open, playing, home, active` as active, and for
`climate.*` also `hvac_action` in `heating, cooling`.

## Examples

```powershell
# Toggle a light
Invoke-HAService light.den_bookshelve
Invoke-HAService light.den_bookshelve -Off

# Force a smart vent fully open
Invoke-HAService cover.kitchen_vent `
                 -Service set_cover_position `
                 -Data @{ position = 100 }

# Bulk-query vent positions
'cover.kitchen_vent','cover.den_vent' |
    Get-HAState |
    Select-Object entity_id, state, @{n='pos';e={$_.attributes.current_position}}

# Decide whether a Sense-detected device is the climate device rather than a
# same-named water heater: bucket Sense power by the thermostat being active
# vs the HPWH. If the "only HPWH on" bucket has p50 near 0, the Sense reading
# is NOT tracking the water heater.
Get-HAEntityCorrelation -Numeric sensor.heat_pump_power `
    -Indicator climate.thermostat,
               binary_sensor.heat_pump_water_heater_running -Hours 24
```

## Conventions

- All cmdlets honour `-Verbose` for HTTP traces, and `-WhatIf`/`-Confirm` where
  they change state.
- HTTP errors surface via `Write-Error`, never swallowed.
- `EntityId` is validated against `^[a-z_]+\.[a-z0-9_]+$` to catch typos before
  the round-trip.
- `-SkipCertificateCheck` is persisted in config rather than passed per call -
  set it once at `Connect-HomeAssistant` time.

## Release process

release-please with Conventional Commits; never commit directly to `main`. The
publish job pushes to the PowerShell Gallery when a release is created **and** the
repo variable `PUBLISH_PSGALLERY` is `true`; the org secret `PSGALLERY_API_KEY`
is consumed by the publish step. See the `release-please-prs` skill for the title
grammar.
