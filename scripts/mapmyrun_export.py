#!/usr/bin/env python3
"""Downloads your whole MapMyRun history as TCX files (one per workout, with
the GPS route), ready for Settings > Import from Strava or MapMyRun.

MapMyRun has no bulk route export, so this uses your logged-in browser
session: the workout list CSV gives the workout IDs, then each workout is
fetched from its TCX export link.

    python3 scripts/mapmyrun_export.py COOKIE_FILE OUT_FOLDER

COOKIE_FILE holds the value of the `Cookie` request header from your browser:
log in at mapmyrun.com, open the developer tools' Network tab, reload, click
the first request to www.mapmyrun.com and copy the whole `Cookie:` value
(not the `Cookie:` label) into the file. Treat it like a password and delete
it afterwards.

Already downloaded workouts are skipped, so the script can be re-run after an
interruption. Then copy OUT_FOLDER to the iPhone (AirDrop or iCloud Drive)
and import the folder in the app.
"""
import csv
import io
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://www.mapmyrun.com"
CSV_URL = BASE + "/workout/export/csv"
TCX_URL = BASE + "/workout/export/{id}/tcx"
WORKOUT_LINK = re.compile(r"/workouts?/(\d+)")
DELAY_SECONDS = 1.0


def fetch(url, cookie):
    request = urllib.request.Request(url, headers={
        "Cookie": cookie,
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)",
    })
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def workout_ids(csv_text):
    """IDs from the workout links in the CSV, oldest first, without duplicates."""
    ids = []
    for row in csv.reader(io.StringIO(csv_text)):
        for cell in row:
            match = WORKOUT_LINK.search(cell)
            if match and match.group(1) not in ids:
                ids.append(match.group(1))
    return list(reversed(ids))


def is_tcx(data):
    return b"TrainingCenterDatabase" in data[:2000]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    cookie = Path(sys.argv[1]).read_text().strip()
    if cookie.lower().startswith("cookie:"):
        cookie = cookie[len("cookie:"):].strip()
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    print("Downloading the workout list...")
    try:
        csv_data = fetch(CSV_URL, cookie)
    except urllib.error.HTTPError as error:
        sys.exit(f"Could not download the workout list (HTTP {error.code}). Is the cookie current?")
    csv_text = csv_data.decode("utf-8-sig", errors="replace")
    (out / "workouts.csv").write_text(csv_text)
    ids = workout_ids(csv_text)
    if not ids:
        sys.exit("No workout links found in the workout list. Check workouts.csv: you may be logged out.")
    print(f"{len(ids)} workouts.")

    downloaded = skipped = failed = 0
    consecutive_failures = 0
    for index, workout_id in enumerate(ids, start=1):
        path = out / f"{workout_id}.tcx"
        if path.exists() and path.stat().st_size > 0:
            skipped += 1
            continue
        try:
            data = fetch(TCX_URL.format(id=workout_id), cookie)
        except (urllib.error.URLError, TimeoutError) as error:
            data = None
            print(f"[{index}/{len(ids)}] {workout_id}: {error}")
        if data is not None and is_tcx(data):
            path.write_bytes(data)
            downloaded += 1
            consecutive_failures = 0
            print(f"[{index}/{len(ids)}] {workout_id}.tcx")
        else:
            failed += 1
            consecutive_failures += 1
            if data is not None:
                print(f"[{index}/{len(ids)}] {workout_id}: not a TCX file")
            if consecutive_failures >= 5:
                sys.exit("5 failures in a row: stopping. The cookie may have expired; re-run to continue.")
        time.sleep(DELAY_SECONDS)

    print(f"Done: {downloaded} downloaded, {skipped} already there, {failed} failed.")


if __name__ == "__main__":
    main()
