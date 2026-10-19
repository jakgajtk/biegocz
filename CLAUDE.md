# Biegocz: project spec

Biegocz is a personal iOS app for logging gym workouts (exercises, sets, reps, weight) and GPS-tracked runs and rides. Single user, data stays on device. Simple beats clever: if a feature is not in this file, don't build it. Propose it under "Later" instead.

## Platform and stack

- iPhone only, portrait, iOS 26.0 minimum.
- Swift 6, SwiftUI, `@Observable`, async/await. No Combine unless there is no alternative.
- SwiftData for persistence, MapKit for SwiftUI, Swift Charts, CoreLocation, HealthKit, UserNotifications.
- No third-party packages without asking me first.
- Metric units (kg, km, min/km for runs, km/h for rides), 24h time.
- Native iOS look, dark mode supported. During workouts: large, readable numbers and big tap targets (sweaty hands, phone on a bench).

## Languages: Polish and English

- The app follows the device language. English is the development language, and Polish must always be 100% translated. A phase isn't done while any string in the catalog is missing a Polish translation.
- Every user-facing string goes through `Localizable.xcstrings`: UI text, alerts, notifications, the share sheet export, and accessibility labels. No hardcoded user-facing strings.
- Use the String Catalog's plural variants. Polish has one/few/many forms ("1 seria", "2 serie", "5 serii"; "1 kilometr", "2 kilometry", "5 kilometrów"), so never build plurals by string concatenation.
- Format numbers, durations, distances, and dates with `FormatStyle` so the locale applies (Polish uses a decimal comma, e.g. "5,2 km"). Never use `String(format:)` for user-facing numbers.
- Built-in exercises have a stable key and localized display names in both languages. Custom exercises are stored exactly as I type them and are not translated. Exercise search must match the name in the current language.
- Permission prompt texts (location, Health) get Polish translations in `InfoPlist.xcstrings`.
- Polish UI text should sound natural, as in a Polish gym app, not like a literal translation. Use the established Polish exercise names ("wyciskanie sztangi leżąc", "martwy ciąg", "przysiad ze sztangą").
- Write unit tests that check Polish plural forms and number formatting in the `pl` locale.

## Hard rules

- The project uses Xcode synchronized folders. Create files inside the right folder; never edit `project.pbxproj`.
- If something needs a capability, entitlement, Info.plist key, or build setting change, stop and tell me exactly what to change. I do it in Xcode.
- Don't guess APIs. HealthKit workout sessions only arrived on iPhone in iOS 26, so behaviour may differ from watchOS. If you're unsure whether an API exists or how it behaves on iPhone, say so, check the documentation, and prefer the simplest documented approach.
- After every meaningful change: build with XcodeBuildMCP, fix all errors and warnings, run tests.
- Never ship a SwiftData schema change without a new `VersionedSchema` and a migration stage. Losing my training history is the worst possible bug.

## Architecture

```
App/                 entry point, tab view, dependency setup
Core/Models/         SwiftData models + VersionedSchema + SchemaMigrationPlan
Core/Persistence/    model container, seed data, JSON export/import
Core/Metrics/        PURE Swift logic, no SwiftUI/SwiftData/CoreLocation imports
Core/Location/       LocationProvider protocol, real (CoreLocation) + GPX replay fake
Core/Health/         HealthStore protocol, real (HealthKit) + no-op fake
Features/Gym/
Features/Cardio/
Features/History/
Features/Exercises/
Features/Settings/
Resources/GPX/       sample routes for the simulator
```

- All math lives in `Core/Metrics` as plain value types and functions: GPS filtering, distance, pace smoothing, splits, auto-pause state machine, e1RM, set prefill. Unit-test it with Swift Testing.
- HealthKit doesn't work in the Simulator. Location and Health sit behind protocols; simulator builds use the fakes. The GPX replay fake lets me test the live run screen in the simulator.
- Keep views thin. One `@Observable` model per live session (gym session, cardio session).

## Tabs

1. **Start**: buttons for Gym, Run, Ride, plus "repeat a previous gym workout". Small summary: this week's sessions and km.
2. **History**: all activities, newest first, filter by type. Tap for detail.
3. **Exercises**: exercise library, search, per-exercise history.
Settings live behind a gear icon on Start.

## Gym

Exercise library:
- Seeded with ~40 common exercises grouped by muscle group (chest, back, legs, shoulders, arms, core).
- Each exercise has a logging type: `weightReps`, `bodyweightReps` (optional added weight), or `duration`.
- I can add custom exercises, rename them, and archive them (never hard-delete an exercise that has history).

Logging a workout:
- Add exercises with a picker: search, recently used at the top, grouped by muscle group, "create new" inline.
- Each exercise shows a hint like "Last time: 3 × 8 @ 80 kg".
- Prefill: a new set copies the previous set in this session. The first set of an exercise copies the first set from the last session that included that exercise.
- Weight steps of 2.5 kg by default (setting), with free numeric entry also allowed.
- Mark a set done to start the rest timer (default 2:00, configurable, can be skipped or extended by 30 s). Send a local notification when it ends if the app is in the background.
- Reorder and delete exercises and sets. Optional note per workout.
- Finish shows a summary: duration, number of sets, total volume.
- "Repeat workout" copies the exercises and number of sets from a past workout with prefilled values, nothing marked done.

Exercise detail:
- List of past sessions with their sets.
- Best set and estimated 1RM using Epley, `w × (1 + reps / 30)`, only for `weightReps` sets with 1 to 12 reps.
- Swift Charts line of best e1RM per session over time.

## Run and ride (outdoor, GPS)

Pre-start: show GPS accuracy (poor / ok / good). Starting is allowed at any time, but warn if accuracy is poor.

Location:
- Use `CLLocationUpdate.liveUpdates` with a `CLBackgroundActivitySession` so tracking continues with the screen locked. Request When In Use authorization only, not Always.
- Filtering, with thresholds in one config struct per activity type: drop invalid or low-accuracy fixes (horizontal accuracy > 25 m), stale fixes, and jumps implying impossible speed (run > 12 m/s, ride > 25 m/s). Only add distance once the movement since the last accepted point exceeds a small minimum, to kill jitter while standing still.

Live screen:
- Run: elapsed time, distance, current pace (smoothed over roughly the last 20 to 30 s; show "--" when not moving), average pace.
- Ride: elapsed time, distance, current speed, average speed.
- Map with the route polyline that follows my position.
- Pause/resume. Finish needs a long press so it can't be triggered by accident.
- Track both moving time and elapsed time.

Crash safety:
- Persist in-progress session state and points every ~10 s.
- On launch, if an unfinished session exists, offer Resume / Save / Discard.

Storage:
- Route points (lat, lon, altitude, timestamp, accuracy) are stored as one compact encoded blob per activity (`@Attribute(.externalStorage)`), not one SwiftData row per point.
- Detail screen: map with route, summary stats, and per-km splits for runs.

## HealthKit

- Request authorization the first time it's needed, not at launch. Everything must still work if I deny it.
- Use `HKWorkoutSession` + `HKLiveWorkoutBuilder` on iPhone (iOS 26) for the cardio workout lifecycle. Check what the builder actually collects on iPhone; if it doesn't produce distance from GPS, write distance samples ourselves from the filtered locations.
- Save runs as running, rides as cycling (outdoor), gym as traditional strength training. Attach the route with `HKWorkoutRouteBuilder`.
- Store the HealthKit workout UUID on our activity so we never save duplicates.

## Data safety

- Export everything as JSON (plus a CSV of all gym sets) through the share sheet. This is in Phase 1, not later.
- Import JSON to restore (Phase 5).

## Phases

Stop at the end of each phase. Give me a short list of what to test on a real device, then commit with a clear message.

1. **Skeleton**: tabs, SwiftData schema v1 with migration plan, seeded exercise library in both languages, String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) with Polish, settings, protocols with real + fake implementations, JSON/CSV export.
2. **Gym**: full logging flow, prefill, rest timer + notification, repeat workout, exercise history, e1RM chart. Tests for prefill and e1RM.
3. **Run and ride**: location pipeline, metrics engine with tests, live screen, map, pause/resume, background tracking, crash recovery, save + detail screen, 2 GPX sample routes (a ~5 km run loop and a ~20 km ride).
4. **HealthKit**: authorization, workout session on iPhone, save all three activity types with routes, graceful handling when access is denied.
5. **Polish**: auto-pause (setting; default off for runs, on for rides), elevation gain (prefer `CMAltimeter`, label as approximate), JSON import, history filters.

## Out of scope for v1

Apple Watch app, heart rate, accounts, backend or iCloud sync, social features, training plans, AI anything, widgets and Live Activities, Strava or GPX import/export, indoor activities, Android.

## Later (ideas, do not build)

- Lock screen Live Activity for runs and rides
- GPX export
- Apple Watch companion
