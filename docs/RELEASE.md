# Releasing to the App Store

What's already in the repo:

- `Biegocz/PrivacyInfo.xcprivacy`: no tracking, no collected data, and `UserDefaults` declared with reason `CA92.1` (the app's own settings).
- `docs/privacy.md`, `docs/support.md`, `docs/index.md`: the privacy policy and support pages (EN + PL), served by GitHub Pages.
- `docs/app-store/en.md`, `docs/app-store/pl.md`: every App Store Connect field, plus App Review notes.
- `scripts/store_screenshots.sh`: 6.9" screenshots in both languages.

## 1. One-time setup

1. **Apple Developer Program**: enrol as an individual at developer.apple.com ($99 a year). Your legal name is shown as the seller.
2. **GitHub Pages**: repo Settings → Pages → Deploy from a branch → `main`, `/docs`. The repo must be public, or on a paid GitHub plan. Check that https://jakgajtk.github.io/biegocz/privacy opens.
3. **Xcode, Biegocz target → Signing & Capabilities**: choose your team. Keep "Automatically manage signing" on. Xcode registers `com.gajtkowski.biegocz` with the HealthKit capability.
4. **Xcode, Biegocz target → Info**: add `App Uses Non-Exempt Encryption` (`ITSAppUsesNonExemptEncryption`), Boolean, `NO`. The app only uses Apple's HTTPS for Apple Maps, which is exempt. Without this key, App Store Connect asks on every build.
5. **App Store Connect → Apps → +**: New App, iOS, name from `docs/app-store/en.md`, primary language English (U.K.), bundle ID `com.gajtkowski.biegocz`, SKU `biegocz`. Add Polish under App Information → Localizable Information.
6. **Business** (only if the app is paid or will have in-app purchases): accept the Paid Apps agreement and add bank and tax details. Join the App Store Small Business Program (15% commission).
7. **EU Digital Services Act**: App Store Connect → Business → declare trader status. A free app without monetisation can be "not a trader". A trader's address, phone and email are shown on the EU App Store.

## 2. Every release

1. Bump the version in Xcode, Biegocz target → General: **Version** (`1.0`, `1.1`, …) for each release and **Build** (`1`, `2`, …) for each upload. Every upload needs a new build number.
2. Run the checks:
   ```sh
   scripts/build.sh test
   python3 scripts/check_strings.py
   ```
3. Screenshots, if the UI changed:
   ```sh
   scripts/build.sh
   scripts/store_screenshots.sh
   ```
   Upload `build/store/en/*` and `build/store/pl/*` to the 6.9" slot. App Store Connect scales them down for smaller iPhones.
4. In Xcode, pick **Any iOS Device (arm64)**, then Product → Archive. In the Organizer, choose Distribute App → App Store Connect → Upload.
5. **TestFlight**: install the build on your iPhone and go through the device checklist below. Friends can test through an external group (that needs a short beta review).
6. In App Store Connect, fill in the version from `docs/app-store/*.md`, select the build and submit for review. Review usually takes 1–2 days.

## 3. Device checklist (things the simulator can't test)

- [ ] First run: location and Health prompts appear only when first needed, in the device language.
- [ ] Run with the screen locked for 10+ minutes: the route has no gaps and the distance is right.
- [ ] Ride: speed and distance look right. Auto-pause (on by default for rides) pauses and resumes.
- [ ] Force-quit the app during a run, then reopen it: Resume / Save / Discard is offered and nothing is lost.
- [ ] The rest timer notification arrives with the app in the background.
- [ ] Health: a run, a ride and a gym session appear in the Health app, with routes. Deny Health access: everything still works.
- [ ] Suggested routes load outdoors on mobile data.
- [ ] Export, delete the app, reinstall, import: the full history is back.
- [ ] Strava export import: maps appear, and a second import adds nothing.
- [ ] Polish and English, light and dark: no truncated text on the workout screens.

## 4. Things App Review commonly asks about

- **Background location**: the review notes explain that it's only on during a recording the user starts.
- **HealthKit**: the app must not store Health data in iCloud or use it for ads. It does neither, and the privacy policy says so.
- **Strava / MapMyRun names**: the review notes explain that they only describe which exported files are supported. Keep them out of the keywords and screenshots.
