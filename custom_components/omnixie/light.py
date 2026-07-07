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
                        self._attr_is_on = raw == 0  # 0 = auto = on
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
