# PwrHass — Home Assistant client for PowerShell

PwrHass talks to a Home Assistant install over its REST API. Connection
details live in `~/.pwrhass/config.json` so cmdlets can be called without
a token argument every time.

## One-time setup

```powershell
Connect-HomeAssistant `
    -BaseUrl 'http://duvall.calvonet.com:8123' `
    -Token (Get-Content ~\OneDrive\Documents\Passwords\wa.hass.txt -Raw).Trim()
```

`Connect-HomeAssistant` writes `~/.pwrhass/config.json` with three fields:

| Field                   | Notes |
|-------------------------|-------|
| `BaseUrl`               | scheme + host + port, no trailing slash |
| `Token`                 | long-lived access token (HA → Profile → Security) |
| `SkipCertificateCheck`  | true for self-signed HTTPS; persisted from `-SkipCertificateCheck` |

The token is plaintext in the file. The directory is `chmod 700` and the
file `chmod 600` on Linux/macOS; on Windows the user-profile ACL applies.

## Cmdlets

| Cmdlet | Purpose |
|--------|---------|
| `Connect-HomeAssistant -BaseUrl <url> -Token <pat> [-SkipCertificateCheck]` | Persist config, ping `/api/` to confirm it works. |
| `Get-HAConfig` | Read the persisted config (throws if not connected). |
| `Get-HAState [-EntityId <id[]>]` | GET `/api/states[/<id>]`. No id → dump everything. Pipeline-friendly. |
| `Invoke-HAService -EntityId <id> [-Service <name>] [-Data <hashtable>] [-Off]` | POST `/api/services/<domain>/<service>`. Domain inferred from entity id. Defaults to `turn_on`; `-Off` flips to `turn_off`. |
| `Get-HAEntityCorrelation -Numeric <id> -Indicator <id[]> [-Hours N] [-Predicate @{}] [-StepMinutes N]` | Bucket a numeric entity's history by the active state of one or more indicator entities. Pulls `/api/history/period`, samples at fixed steps, returns per-bucket count / mean / p50 / p90 / max. Default predicate treats `state in 'on','heating','cooling','open','playing','home','active'` (and `climate.*` `hvac_action in 'heating','cooling'`) as active. |

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

# Confirm a Sense-detected device IS the climate device (not a same-named
# water heater): bucket the Sense power by climate.thermostat being active
# vs the HPWH being active.  If the "only HPWH on" bucket has p50≈0 then
# the Sense reading is NOT tracking the water heater.
Get-HAEntityCorrelation -Numeric sensor.heat_pump_power `
    -Indicator climate.thermostat,
               binary_sensor.heat_pump_water_heater_running -Hours 24
```

## Conventions

- All cmdlets honour `-Verbose` for HTTP traces and `-WhatIf` /
  `-Confirm` (where it changes state).
- HTTP errors are surfaced via `Write-Error`, not swallowed.
- `EntityId` is validated against `^[a-z_]+\.[a-z0-9_]+$` to catch typos
  before the round-trip.
- `-SkipCertificateCheck` persisted in config rather than passed each
  call — flip it once at `Connect-HomeAssistant` time.

## Release process

This repo uses [release-please](https://github.com/googleapis/release-please)
with [Conventional Commits](https://www.conventionalcommits.org/).

| Type | Bump |
|------|------|
| `feat:` | minor |
| `fix:` / `perf:` / `refactor:` | patch |
| `feat!:` / `fix!:` / `BREAKING CHANGE:` footer | major |
| `docs:` / `chore:` / `ci:` / `test:` | none |

Never commit directly to `main` — open a PR with a Conventional Commit
title and let release-please cut the release PR.

The publish job (`.github/workflows/release-please.yml`) pushes to the
PowerShell Gallery when a release is created **and** the repo variable
`PUBLISH_PSGALLERY` is set to `true`. The org secret `PSGALLERY_API_KEY`
is consumed by the publish step.

---
*Last garbage-collected: 2026-04-25*
