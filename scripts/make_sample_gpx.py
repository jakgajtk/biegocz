#!/usr/bin/env python3
"""Generates the simulator sample routes in Biegocz/Resources/GPX/.

- SampleRun.gpx: ~5 km loop at about 5:30/km, one fix per second, with
  drifting GPS error, a 30 s stop (standing at a crossing) and one bad
  300 m jump.
- SampleRide.gpx: ~20 km loop at about 25 km/h, one fix per second.

Deterministic (fixed random seed), so re-running gives the same files.
"""
import math
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Biegocz" / "Resources" / "GPX"
M_PER_DEG_LAT = 111_320.0


def ellipse_point(center, a, b, angle):
    lat0, lon0 = center
    dx, dy = a * math.cos(angle), b * math.sin(angle)
    lat = lat0 + dy / M_PER_DEG_LAT
    lon = lon0 + dx / (M_PER_DEG_LAT * math.cos(math.radians(lat0)))
    return lat, lon


def ellipse_perimeter(a, b):
    h = ((a - b) / (a + b)) ** 2
    return math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h)))


def loop(center, a, b, speed, rng, jitter_m, stop_at=None, stop_seconds=0, jump_at=None):
    """Points along an ellipse at roughly `speed` m/s, one per second."""
    perimeter = ellipse_perimeter(a, b)
    points = []
    travelled = 0.0
    angle = 0.0
    second = 0
    stopped = 0
    # GPS error drifts slowly rather than jumping every second (CoreLocation
    # already filters fixes), so model it as an AR(1) process with standard
    # deviation `jitter_m`.
    phi = 0.95
    innovation = jitter_m * math.sqrt(1 - phi ** 2)
    noise_north = noise_east = 0.0
    while travelled < perimeter:
        if stop_at is not None and travelled >= stop_at and stopped < stop_seconds:
            stopped += 1
        else:
            step = speed * (1 + 0.08 * math.sin(second / 40)) + rng.uniform(-0.2, 0.2)
            travelled += step
            # Advance the angle by the arc length covered (small-step approximation).
            radius = math.hypot(a * math.sin(angle), b * math.cos(angle))
            angle += step / max(radius, 1)
        lat, lon = ellipse_point(center, a, b, angle)
        noise_north = phi * noise_north + rng.gauss(0, innovation)
        noise_east = phi * noise_east + rng.gauss(0, innovation)
        jitter_lat = noise_north / M_PER_DEG_LAT
        jitter_lon = noise_east / (M_PER_DEG_LAT * math.cos(math.radians(lat)))
        lat, lon = lat + jitter_lat, lon + jitter_lon
        if jump_at is not None and second == jump_at:
            lat += 300 / M_PER_DEG_LAT
        elevation = 100 + 6 * math.sin(angle * 2) + rng.uniform(-0.3, 0.3)
        points.append((lat, lon, elevation, second))
        second += 1
    return points


def write_gpx(path, name, points):
    start = datetime(2026, 1, 1, 8, 0, 0, tzinfo=timezone.utc)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="Biegocz make_sample_gpx.py" xmlns="http://www.topografix.com/GPX/1/1">',
        f"  <trk><name>{name}</name><trkseg>",
    ]
    for lat, lon, ele, second in points:
        time = (start + timedelta(seconds=second)).strftime("%Y-%m-%dT%H:%M:%SZ")
        lines.append(f'    <trkpt lat="{lat:.7f}" lon="{lon:.7f}"><ele>{ele:.1f}</ele><time>{time}</time></trkpt>')
    lines += ["  </trkseg></trk>", "</gpx>", ""]
    path.write_text("\n".join(lines))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(42)
    # Around Pole Mokotowskie, Warsaw. Perimeter ≈ 4.97 km.
    run = loop((52.2125, 20.9950), 1000, 500, 1000 / 330, rng, jitter_m=3.0,
               stop_at=2500, stop_seconds=30, jump_at=600)
    write_gpx(OUT / "SampleRun.gpx", "Sample run", run)
    # A wide loop around central Warsaw. Perimeter ≈ 20.7 km.
    ride = loop((52.2300, 21.0100), 4000, 2400, 25 / 3.6, rng, jitter_m=3.0)
    write_gpx(OUT / "SampleRide.gpx", "Sample ride", ride)
    print(f"run: {len(run)} points, ride: {len(ride)} points")


if __name__ == "__main__":
    main()
