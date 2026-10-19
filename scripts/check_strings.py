#!/usr/bin/env python3
"""Checks that every string the compiler extracted is in Localizable.xcstrings
and that every catalog entry is fully translated to Polish.

Run after a build (scripts/build.sh), which produces the .stringsdata files.
Exits 1 if anything is missing.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Biegocz" / "Resources" / "Localizable.xcstrings"
INFOPLIST_CATALOG = ROOT / "Biegocz" / "Resources" / "InfoPlist.xcstrings"
STRINGSDATA_DIR = (
    ROOT / "build" / "DerivedData" / "Build" / "Intermediates.noindex"
    / "Biegocz.build" / "Debug-iphonesimulator" / "Biegocz.build"
)
POLISH_PLURALS = {"one", "few", "many", "other"}
INFOPLIST_KEYS = {
    "CFBundleDisplayName",
    "NSLocationWhenInUseUsageDescription",
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
}


def extracted_keys():
    keys = {}
    for path in STRINGSDATA_DIR.rglob("*.stringsdata"):
        data = json.loads(path.read_text())
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.setdefault(entry["key"], Path(data["source"]).name)
    return keys


def translation_problems(key, entry, languages):
    problems = []
    localizations = entry.get("localizations", {})
    for lang in languages:
        loc = localizations.get(lang)
        if loc is None:
            if lang != "en":
                problems.append(f"{key!r}: no {lang} translation")
            continue
        if "stringUnit" in loc:
            if loc["stringUnit"].get("state") != "translated" or not loc["stringUnit"].get("value"):
                problems.append(f"{key!r}: {lang} not translated")
        elif "variations" in loc:
            plural = loc["variations"].get("plural", {})
            required = POLISH_PLURALS if lang == "pl" else {"one", "other"}
            missing = required - plural.keys()
            if missing:
                problems.append(f"{key!r}: {lang} missing plural forms {sorted(missing)}")
            for form, value in plural.items():
                unit = value.get("stringUnit", {})
                if unit.get("state") != "translated" or not unit.get("value"):
                    problems.append(f"{key!r}: {lang} plural {form} not translated")
        else:
            problems.append(f"{key!r}: {lang} has no value")
    return problems


def main():
    if not STRINGSDATA_DIR.exists():
        print("No build output found. Run scripts/build.sh first.")
        return 1

    catalog = json.loads(CATALOG.read_text())["strings"]
    problems = []

    code_keys = extracted_keys()
    for key, source in sorted(code_keys.items()):
        if key not in catalog:
            problems.append(f"{key!r}: used in {source} but missing from the catalog")

    for key, entry in sorted(catalog.items()):
        if entry.get("shouldTranslate") is False:
            continue
        if key not in code_keys and entry.get("extractionState") != "manual":
            problems.append(f"{key!r}: in the catalog but not used in code (stale)")
        problems += translation_problems(key, entry, ["en", "pl"])

    infoplist = json.loads(INFOPLIST_CATALOG.read_text())["strings"]
    for key in sorted(INFOPLIST_KEYS):
        if key not in infoplist:
            problems.append(f"InfoPlist {key!r}: missing")
        else:
            problems += [f"InfoPlist {p}" for p in translation_problems(key, infoplist[key], ["pl"])]

    for problem in problems:
        print(problem)
    print(f"{len(code_keys)} strings in code, {len(catalog)} in catalog, {len(problems)} problems.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
