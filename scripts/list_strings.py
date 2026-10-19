#!/usr/bin/env python3
"""Prints every string key the compiler extracted, one per line, with its source file."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STRINGSDATA_DIR = (
    ROOT / "build" / "DerivedData" / "Build" / "Intermediates.noindex"
    / "Biegocz.build" / "Debug-iphonesimulator" / "Biegocz.build"
)

keys = {}
for path in STRINGSDATA_DIR.rglob("*.stringsdata"):
    data = json.loads(path.read_text())
    for entry in data.get("tables", {}).get("Localizable", []):
        keys.setdefault(entry["key"], Path(data["source"]).name)

for key, source in sorted(keys.items()):
    print(f"{source}\t{key}")
