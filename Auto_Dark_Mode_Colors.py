#!/usr/bin/env python3.7
"""
Auto_Dark_Mode_Colors auto set profile colors based on iTerm2 theme.

To configure, update the mapping in `PROFILE_PRESETS` such that the profile
name maps to the light and dark presets you'd like to use.
"""

import asyncio
import iterm2
from collections import namedtuple
from subprocess import check_output

ColorPresets = namedtuple('ColorPresets', ['light', 'dark'])

"""Mapping of Profile Name to Color presets"""
PROFILE_PRESETS = {
    # Built in presets
    'OneHalf': ColorPresets('OneHalfLight', 'OneHalfDark'),
    'Main': ColorPresets('OneHalfLight', 'OneHalfDark'),
    # Custom
    # 'Wombat (Auto)': ColorPresets('Novel', 'Wombat'),
}


async def is_dark_theme(monitor=None, app=None):
    """Return whether or not iTerm2 theme is dark"""
    theme=None
    if monitor:
        theme = await monitor.async_get()
    elif app:
        theme = await app.async_get_variable("effectiveTheme")
    else:
        raise ValueError('Need a monitor or app instance to detect theme')

    # Themes have space-delimited attributes, one of which will be light or dark.
    parts = theme.split(" ")
    return "dark" in parts


def get_color_for_profile(profile_name, dark_mode):
    """
    Get the color for a particular preset.

    If the profile is not listed in the map, return None
    """
    if profile_name not in PROFILE_PRESETS:
        return None

    color_presets = PROFILE_PRESETS[profile_name]
    if dark_mode:
        return color_presets.dark
    else:
        return color_presets.light


async def gather_presets_for_colors(connection, colors):
    """
    Return map of colors to presets

    This is used to minimize the number of async calls.
    """
    async def preset_name_to_preset(preset_name):
        preset = await iterm2.ColorPreset.async_get(connection, preset_name)
        print("Got preset for color {}: {}".format(preset_name, preset))
        return preset_name, preset

    return dict(await asyncio.gather(*[
        preset_name_to_preset(preset_name)
        for preset_name in colors
        if preset_name is not None
    ]))


def get_current_colors(partials, dark_mode):
    """
    Return a set of current colors given a list of partials

    This allows us to fetch presets only once.
    """
    return {
        get_color_for_profile(partial.name, dark_mode)
        for partial in partials
    }


async def set_dark_colors(connection, dark_mode):
    """Set dark mode for all open profiles"""
    print("Enable dark mode? {}".format(dark_mode))
    partials = (await iterm2.PartialProfile.async_query(connection))
    all_colors = get_current_colors(partials, dark_mode)
    all_colors = await gather_presets_for_colors(connection, all_colors)

    for partial in partials:
        color = get_color_for_profile(partial.name, dark_mode)
        if not color:
            continue
        preset = all_colors[color]
        await partial.async_set_color_preset(preset)


async def main(connection):
    # Set colors initially because of unknown profile defaults
    app = await iterm2.app.async_get_app(connection)
    dark_theme = await is_dark_theme(app=app)
    await set_dark_colors(connection, dark_theme)
    dark_colors = dark_theme

    # Begin monitoring the effective theme
    async with iterm2.VariableMonitor(
        connection,
        iterm2.VariableScopes.APP,
        "effectiveTheme",
        None,
    ) as monitor:
        while True:
            dark_theme = await is_dark_theme(monitor=monitor)
            if dark_theme != dark_colors:
                await set_dark_colors(connection, dark_theme)
                dark_colors = dark_theme


if __name__ == '__main__':
    iterm2.run_forever(main)

