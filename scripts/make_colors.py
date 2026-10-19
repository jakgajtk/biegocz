#!/usr/bin/env python3
"""Writes the app's color palette as asset catalog color sets (light + dark).

Edit the PALETTE below and re-run; Xcode generates `Color.<name>` symbols
(e.g. `Color.appBackground`) from these.
"""
import json
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "Biegocz" / "Resources" / "Assets.xcassets"

# name: (light hex, dark hex)
PALETTE = {
    # Navy brand accent: buttons, tab bar, links.
    "AccentColor": ("1F3C88", "8AB4FF"),
    # Screen background and cards.
    "AppBackground": ("F3F5FA", "0B1324"),
    "CardBackground": ("FFFFFF", "15203A"),
    # Fills inside cards (stepper buttons, chips).
    "CardFill": ("EAEFF7", "1F2C4A"),
    # Hero gradient (week summary, workout summary).
    "BrandNavy": ("1B3170", "1F3A7A"),
    "BrandNavyDeep": ("0B1838", "0D1A3A"),
    # Semantic.
    "Success": ("1F9D6B", "3DD68C"),
    "Warning": ("D9801A", "FFB547"),
    "Danger": ("D93F4C", "FF6B76"),
    # Activity tints, kept muted so navy stays dominant.
    "GymTint": ("4F6BED", "8C9EFF"),
    "RunTint": ("E2694F", "FF8E70"),
    "RideTint": ("1A958F", "4FD1C5"),
}


def components(hex_value):
    r, g, b = (int(hex_value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return {"alpha": "1.000", "red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}"}


def colorset(light, dark):
    return {
        "colors": [
            {"color": {"color-space": "srgb", "components": components(light)}, "idiom": "universal"},
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "color": {"color-space": "srgb", "components": components(dark)},
                "idiom": "universal",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }


for name, (light, dark) in PALETTE.items():
    folder = ASSETS / f"{name}.colorset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps(colorset(light, dark), indent=2) + "\n")
print(f"Wrote {len(PALETTE)} color sets.")
