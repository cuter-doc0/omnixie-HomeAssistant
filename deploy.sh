#!/bin/bash
# Deploy Omnixie integration to Home Assistant
# Run this in the HA Terminal add-on

set -e

DIR="/config/custom_components/omnixie"

# Clean up old files
echo "Cleaning up old files..."
rm -f "$DIR"/*.py "$DIR"/*.json 2>/dev/null || true
mkdir -p "$DIR"

cat > "$DIR/manifest.json" << 'EOF'
{
  "domain": "omnixie",
  "name": "Omnixie Clock",
  "codeowners": [],
  "config_flow": true,
  "documentation": "https://www.omnixie.cn",
  "integration_type": "device",
  "iot_class": "local_polling",
  "requirements": [],
  "version": "1.0.0"
}
EOF

cat > "$DIR/const.py" << 'EOF'
"""Constants for the Omnixie Clock integration."""
DOMAIN = "omnixie"
DEFAULT_NAME = "Omnixie Clock"
EOF

cat > "$DIR/__init__.py" << 'EOF'
"""The Omnixie Clock integration."""
from __future__ import annotations

import logging

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_HOST, CONF_NAME, Platform
from homeassistant.core import HomeAssistant

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)

PLATFORMS: list[Platform] = [Platform.LIGHT]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up Omnixie Clock from a config entry."""
    hass.data.setdefault(DOMAIN, {})
    hass.data[DOMAIN][entry.entry_id] = {
        CONF_HOST: entry.data[CONF_HOST],
        CONF_NAME: entry.data[CONF_NAME],
    }

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a config entry."""
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unload_ok
EOF

cat > "$DIR/config_flow.py" << 'EOF'
"""Config flow for Omnixie Clock integration."""
from __future__ import annotations

import logging
from typing import Any

import aiohttp
import voluptuous as vol

from homeassistant import config_entries
from homeassistant.const import CONF_HOST, CONF_NAME
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResult

from .const import DEFAULT_NAME, DOMAIN

_LOGGER = logging.getLogger(__name__)

STEP_USER_DATA_SCHEMA = vol.Schema(
    {
        vol.Required(CONF_HOST, default="omnixie.local"): str,
        vol.Optional(CONF_NAME, default=DEFAULT_NAME): str,
    }
)


async def _test_connection(hass: HomeAssistant, host: str) -> bool:
    """Test if we can connect to the Omnixie clock."""
    url = f"http://{host}/jsonload?f=basicset.json"
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as resp:
                return resp.status == 200
    except (aiohttp.ClientError, TimeoutError):
        return False


class OmnixieConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Handle a config flow for Omnixie Clock."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> FlowResult:
        """Handle the initial step."""
        errors: dict[str, str] = {}

        if user_input is not None:
            host = user_input[CONF_HOST]

            await self.async_set_unique_id(host)
            self._abort_if_unique_id_configured()

            if not await _test_connection(self.hass, host):
                errors["base"] = "cannot_connect"
            else:
                return self.async_create_entry(
                    title=user_input[CONF_NAME],
                    data=user_input,
                )

        return self.async_show_form(
            step_id="user",
            data_schema=STEP_USER_DATA_SCHEMA,
            errors=errors,
        )
EOF

cat > "$DIR/light.py" << 'EOF'
"""Light platform for Omnixie Clock."""
from __future__ import annotations

import logging
from typing import Any

import aiohttp
from homeassistant.components.light import (
    ColorMode,
    LightEntity,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_HOST, CONF_NAME
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up Omnixie light from a config entry."""
    data = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([OmnixieLight(entry, data[CONF_HOST], data[CONF_NAME])])


class OmnixieLight(LightEntity):
    """Representation of an Omnixie Clock as a light (on/off only)."""

    _attr_has_entity_name = True
    _attr_supported_color_modes = {ColorMode.ONOFF}
    _attr_color_mode = ColorMode.ONOFF

    def __init__(self, entry: ConfigEntry, host: str, name: str) -> None:
        """Initialize the light."""
        self._entry = entry
        self._host = host
        self._attr_name = name
        self._attr_unique_id = f"omnixie_{entry.entry_id}"
        self._attr_is_on = True

    @property
    def device_info(self) -> dict:
        """Return device info."""
        return {
            "identifiers": {(DOMAIN, self._entry.entry_id)},
            "name": self._attr_name,
            "manufacturer": "Omnixie",
        }

    async def _fetch_state(self) -> None:
        """Fetch current brightness from the clock."""
        url = f"http://{self._host}/jsonload?f=basicset.json"
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as resp:
                    if resp.status == 200:
                        data = await resp.json(content_type=None)
                        raw = int(data.get("FormatBrightness", 0))
                        self._attr_is_on = raw == 0
        except (aiohttp.ClientError, TimeoutError) as err:
            _LOGGER.warning("Failed to fetch Omnixie state: %s", err)

    async def async_added_to_hass(self) -> None:
        """Fetch state when added to hass."""
        await self._fetch_state()

    async def async_update(self) -> None:
        """Update the entity."""
        await self._fetch_state()

    async def _save_brightness(self, clock_val: str) -> None:
        """Save brightness to the clock and trigger MCU reload."""
        read_url = f"http://{self._host}/jsonload?f=basicset.json"
        save_url = f"http://{self._host}/jsonsave?f=basicset.json"
        apply_url = f"http://{self._host}/updatebasic"

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(read_url, timeout=aiohttp.ClientTimeout(total=5)) as resp:
                    if resp.status != 200:
                        _LOGGER.warning("Omnixie: failed to read state, HTTP %s", resp.status)
                        return
                    current = await resp.json(content_type=None)

                current["FormatBrightness"] = clock_val

                async with session.post(
                    save_url,
                    json=current,
                    timeout=aiohttp.ClientTimeout(total=5),
                ) as resp:
                    if resp.status != 200:
                        _LOGGER.warning("Omnixie: failed to save, HTTP %s", resp.status)
                        return

                # Trigger MCU to reload settings from flash
                await session.get(apply_url, timeout=aiohttp.ClientTimeout(total=5))

        except (aiohttp.ClientError, TimeoutError) as err:
            _LOGGER.error("Omnixie: error setting brightness: %s", err)

    async def async_turn_on(self, **kwargs: Any) -> None:
        """Turn the clock on (auto brightness)."""
        await self._save_brightness("0")
        self._attr_is_on = True

    async def async_turn_off(self, **kwargs: Any) -> None:
        """Turn the clock off (minimum brightness)."""
        await self._save_brightness("1")
        self._attr_is_on = False
EOF

cat > "$DIR/strings.json" << 'EOF'
{
  "config": {
    "step": {
      "user": {
        "title": "Omnixie Clock",
        "description": "Set up your Omnixie Nixie tube clock.",
        "data": {
          "host": "Host",
          "name": "Name"
        }
      }
    },
    "error": {
      "cannot_connect": "Failed to connect to the Omnixie clock.",
      "unknown": "Unexpected error."
    },
    "abort": {
      "already_configured": "This clock is already configured."
    }
  }
}
EOF

echo ""
echo "Done! Omnixie integration updated."
echo "1. Restart Home Assistant (Settings > System > Restart)"
echo "2. The existing Omnixie light entity will now use on/off only"
echo "   - On  = auto brightness"
echo "   - Off = minimum brightness"
