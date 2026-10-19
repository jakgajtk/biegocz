# Biegocz

A personal iPhone app for logging gym workouts and GPS-tracked runs and rides. Everything stays on the device: no account, no backend, no sync. Available in English and Polish.

<p>
  <img src="docs/screenshots/start-pl-dark.png" width="200" alt="Start screen">
  <img src="docs/screenshots/gym-pl-dark.png" width="200" alt="Gym workout">
  <img src="docs/screenshots/prestart-pl-dark.png" width="200" alt="Run pre-start">
  <img src="docs/screenshots/activityDetail-pl-dark.png" width="200" alt="Run detail with splits">
</p>

## Features

**Gym**
- Library of 44 common exercises grouped by muscle group, plus your own custom exercises (rename, archive).
- Fast logging: weight and reps steppers sized for sweaty hands, sets prefilled from your last session, and a "Last time: 3 × 8 @ 80 kg" hint.
- Rest timer with +30 s and skip, plus a notification when rest is over and the app is in the background.
- Repeat a past workout with one tap.
- Per-exercise history with best set, estimated 1RM (Epley) and a progress chart.

**Run and ride**
- GPS tracking that keeps going with the screen locked, with a live map, pace or speed, and moving vs. elapsed time.
- Filtering of noisy, stale and impossible GPS fixes, plus optional auto-pause.
- Per-kilometer splits, approximate elevation gain (barometer when available), and a route map.
- Crash-safe: progress is saved every 10 seconds, and an interrupted session can be resumed, saved or discarded.

**Everywhere**
- Saves workouts and routes to Apple Health, if you allow it. The app works fully without it.
- Export everything as JSON (plus a CSV of all gym sets) and import it back.
- Full Polish translation with correct plural forms and a decimal comma ("5,2 km").
- Dark mode, haptics and animations that respect Reduce Motion.

## Requirements

- iPhone with iOS 26 or later
- Xcode 26

## Getting started

1. Open `Biegocz.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, choose your team and, if needed, change the bundle identifier (`com.gajtkowski.biegocz`).
3. Run on an iPhone or the simulator.

The simulator has no HealthKit and no real GPS, so simulator builds use fakes: Health is turned off, and runs and rides replay the sample routes in `Biegocz/Resources/GPX/` (a ~5 km run loop and a ~20 km ride).

## Development

Build and test from the command line:

```sh
scripts/build.sh          # build the app and tests
scripts/build.sh test     # build and run all tests, printing failures
python3 scripts/check_strings.py   # every string is in the catalog with Polish
```

Look at a screen in the simulator with demo data (debug builds only, in-memory store):

```sh
scripts/screenshot.sh gym pl dark
```

Other scripts:

| Script | Purpose |
| --- | --- |
| `scripts/add_strings.py` | Merge new translations into `Localizable.xcstrings` |
| `scripts/make_colors.py` | Generate the color palette asset sets |
| `scripts/make_icon.swift` | Render the app icon |
| `scripts/make_sample_gpx.py` | Generate the simulator GPX routes |

### Project layout

```
Biegocz/
  App/              entry point, tabs, session coordinator, design system
  Core/Models/      SwiftData models, versioned schema, migration plan
  Core/Persistence/ store, seed data, route encoding, JSON/CSV export and import
  Core/Metrics/     pure logic: GPS filtering, pace, splits, auto-pause, e1RM, prefill
  Core/Location/    location and altitude providers (real + simulator fakes)
  Core/Health/      HealthKit store (real + no-op) and saving workouts
  Features/         Start, Gym, Cardio, History, Exercises, Settings
BiegoczTests/       Swift Testing suite
```

Stack: Swift 6, SwiftUI, SwiftData, MapKit, Swift Charts, CoreLocation, CoreMotion and HealthKit. No third-party dependencies.

The full product spec and project rules live in [`CLAUDE.md`](CLAUDE.md).
