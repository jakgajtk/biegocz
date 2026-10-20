# App Store listing: English (U.K. and U.S.)

Paste each field into App Store Connect → the app → the version → English. Limits are App Store Connect's.

## Name (30)

Biegocz: Gym, Run & Ride

## Subtitle (30)

Offline workout log & GPS

## Keywords (100, comma-separated, no spaces)

Words already in the name and subtitle count for search, so they aren't repeated here. No competitor names: Guideline 2.3.7 forbids them in keywords.

```
workout,lifting,tracker,strength,running,cycling,bike,gpx,1rm,sets,reps,weights,splits,pace,fitness
```

## Promotional text (170)

Log lifts with big buttons made for the gym floor, record runs and rides with GPS, and keep everything on your iPhone. No account, no ads, no tracking.

## Description (4000)

Biegocz is one simple log for everything you do in training: lifting at the gym, running and riding outdoors. Your data stays on your iPhone. There is no account, no subscription and no tracking.

GYM
• 44 common exercises grouped by muscle group, plus your own
• Big steppers for weight and reps, made for sweaty hands
• Every set is prefilled from your last session, with a "Last time: 3 × 8 @ 80 kg" hint
• Rest timer with +30 s and skip, and a notification when rest is over
• Repeat a past workout with one tap
• Best set, estimated 1RM and a progress chart for every exercise

RUN AND RIDE
• GPS tracking that keeps going with the screen locked
• Live map, current and average pace or speed, moving and elapsed time
• Filtering of noisy GPS points, and optional auto-pause
• Per-kilometre splits and approximate elevation gain
• Suggested routes: pick a distance and get three loops starting where you are
• Crash-safe: progress is saved every 10 seconds, so an interrupted run can be resumed

HISTORY
• Your week, month or year at a glance, compared with the previous period
• Weekly streak and personal bests: longest and fastest run and ride, biggest climb, biggest gym session
• Filter by gym, run or ride

YOUR DATA
• Saves workouts and routes to Apple Health if you allow it. The app works fully without it.
• Export everything as JSON and CSV, and restore it at any time
• Bring your history with you: import past runs and rides with their maps from GPX, TCX and FIT files, such as a Strava account export
• Fully translated into Polish

Metric units only (kg, km).

## What's New (version 1.0)

First release.

## URLs

- Support URL: https://jakgajtk.github.io/biegocz/support
- Privacy Policy URL: https://jakgajtk.github.io/biegocz/privacy
- Marketing URL: https://jakgajtk.github.io/biegocz/ (optional)

## Screenshots

Take them with `scripts/store_screenshots.sh` (6.9" iPhone 17 Pro Max), from `build/store/en/`. Order: start, gym, history, routes, activityDetail, exerciseDetail.

## App Review notes

```
Biegocz needs no account and has no server. All data stays on the device.

To test the gym log: Start → Gym, add an exercise, tap the circle next to a set to start the rest timer, then Finish.

Runs and rides need real outdoor movement for GPS. Start → Run → Start shows the live screen. To finish, hold the Finish button.

Location ("While Using") is used only during a recording that the user starts. The "location" background mode keeps tracking while the screen is locked during that recording, and it shows the blue location indicator.

HealthKit is optional. It saves the finished workout (and route) and reads back the samples recorded during it. Everything works if access is denied.

The only network use is Apple Maps directions (MKDirections) for the optional "Suggested routes" before a run or ride.

"Import from Strava or MapMyRun" reads route files (GPX/TCX/FIT) that the user has exported from those services. It does not connect to them. The names are only there to tell users which exports work.
```

## Other App Store Connect answers

- Primary category: Health & Fitness. Secondary: Sports.
- Age rating: answer "None" or "No" to everything → 4+.
- App Privacy: "Data Not Collected". The developer receives nothing. Apple Maps requests are Apple's own service and aren't collection by the developer.
- Price: free (or a tier of your choice). Availability: all territories, or Europe first because the app is metric only.
- Content rights: the app doesn't contain third-party content.
- Export compliance: no non-exempt encryption (also set in `Info.plist`, see `docs/RELEASE.md`).
