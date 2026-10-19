#!/usr/bin/env python3
"""Merges translations from a JSON file into Localizable.xcstrings.

    python3 scripts/add_strings.py path/to/new_strings.json

The JSON maps each key to either
  - a string: the Polish translation (English is the key itself), or
  - an object {"en": [one, other], "pl": [one, few, many, other]} for plurals, or
  - an object {"en": "...", "pl": "...", "manual": true} for keys not extracted from code, or
  - null to remove the key.
Existing entries are replaced.
"""
import json
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "Biegocz" / "Resources" / "Localizable.xcstrings"


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def entry_for(value):
    if isinstance(value, str):
        return {"localizations": {"pl": unit(value)}}
    if "pl" in value and isinstance(value["pl"], list):
        en_one, en_other = value["en"]
        pl_one, pl_few, pl_many, pl_other = value["pl"]
        return {"localizations": {
            "en": {"variations": {"plural": {"one": unit(en_one), "other": unit(en_other)}}},
            "pl": {"variations": {"plural": {
                "one": unit(pl_one), "few": unit(pl_few), "many": unit(pl_many), "other": unit(pl_other)}}},
        }}
    entry = {"localizations": {"en": unit(value["en"]), "pl": unit(value["pl"])}}
    if value.get("manual"):
        entry["extractionState"] = "manual"
    return entry


def main():
    additions = json.loads(Path(sys.argv[1]).read_text())
    doc = json.loads(CATALOG.read_text())
    for key, value in additions.items():
        if value is None:
            doc["strings"].pop(key, None)
        else:
            doc["strings"][key] = entry_for(value)
    text = json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    CATALOG.write_text(text + "\n")
    print(f"Merged {len(additions)} strings.")


if __name__ == "__main__":
    main()
