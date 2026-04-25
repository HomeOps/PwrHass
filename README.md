# PwrHass

PowerShell client for [Home Assistant](https://www.home-assistant.io/).
One-time `Connect-HomeAssistant` persists the base URL and long-lived
access token under `~/.pwrhass`; subsequent service calls and state queries
read it implicitly.

## Install

```powershell
Install-Module PwrHass -Scope CurrentUser
```

(Or develop locally — clone this repo and add the parent dir to
`$env:PSModulePath`.)

## Quick start

```powershell
Connect-HomeAssistant `
    -BaseUrl 'http://homeassistant.local:8123' `
    -Token '<long-lived-access-token>'

# Toggle a light
Invoke-HAService light.den_bookshelve
Invoke-HAService light.den_bookshelve -Off

# Force a smart vent fully open
Invoke-HAService cover.kitchen_vent `
                 -Service set_cover_position `
                 -Data @{ position = 100 }

# Inspect entity state
Get-HAState climate.smart_climate
```

## Cmdlets

| Cmdlet | Purpose |
|--------|---------|
| `Connect-HomeAssistant` | Save base URL + token to `~/.pwrhass/config.json`. |
| `Get-HAConfig`          | Read the saved config. |
| `Get-HAState`           | GET `/api/states[/<entity_id>]`. |
| `Invoke-HAService`      | POST `/api/services/<domain>/<service>`. |

See [`CLAUDE.md`](CLAUDE.md) for the full reference and conventions.

## Releases

Conventional Commits → release-please cuts version bumps and a CHANGELOG
automatically; merging the release PR publishes to the PowerShell Gallery
(when the repo variable `PUBLISH_PSGALLERY` is `true` and the org secret
`PSGALLERY_API_KEY` is available).
