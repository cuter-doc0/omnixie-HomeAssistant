# Omnixie Component for Home Assistant

A [Home Assistant](https://www.home-assistant.io/) custom integration for the [Omnixie](https://www.omnixie.cn) Nixie tube clock. Adds the clock as a light entity in Home Assistant, which can then be exposed to Apple HomeKit via the [HomeKit Bridge](https://www.home-assistant.io/integrations/homekit/) integration.

## Features

- **On/Off control** via Home Assistant
- **On** = auto brightness (clock adjusts to ambient light)
- **Off** = minimum brightness (preserves tube life)
- Expose to **Apple HomeKit** through HA's built-in HomeKit Bridge

## Installation

### Prerequisites

- Home Assistant (tested with 2024.x)
- Omnixie clock on the same network as HA

### Install the integration

1. Open the **Terminal** add-on in Home Assistant (install from the Add-on Store if needed)
2. Paste and run the contents of `deploy.sh`
3. Restart Home Assistant
4. Go to **Settings > Devices & Services > + Add Integration > Omnixie Clock**
5. Enter your clock's hostname (default: `omnixie.local`) and a name

### HomeKit setup (optional)

1. Ensure the **HomeKit Bridge** integration is set up in HA
2. In the HomeKit Bridge, enable the Omnixie light entity
3. Open the **Apple Home** app — the clock now appears as a light

### Automations

Create automations in the Apple Home app:

- **When I leave home** → Turn off Omnixie Clock
- **When I arrive home** → Turn on Omnixie Clock

## How it works

The integration communicates with the Omnixie clock's built-in web dashboard via HTTP:

| Action | API call |
|--------|----------|
| Read state | `GET /jsonload?f=basicset.json` |
| Save settings | `POST /jsonsave?f=basicset.json` |
| Apply to MCU | `GET /updatebasic` |

The `/updatebasic` endpoint triggers the clock's MCU to reload settings from flash — without this call, saved changes won't take effect on the display.

## File structure

```
custom_components/omnixie/
├── manifest.json      # HA integration metadata
├── const.py           # Domain constants
├── __init__.py        # Integration setup
├── config_flow.py     # UI configuration (host, name)
├── light.py           # Light entity (on/off)
└── strings.json       # Translations
deploy.sh             # One-shot deploy script for HA Terminal
```

## License

MIT
