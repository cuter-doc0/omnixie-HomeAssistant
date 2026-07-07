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
