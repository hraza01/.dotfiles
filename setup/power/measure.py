#!/usr/bin/env python3
"""Read-only battery measurement. Keep workload and brightness steady for comparisons."""

import argparse
import json
from pathlib import Path
import statistics
import sys
import time


def positive_seconds(value):
    value = int(value)
    if value < 1:
        raise argparse.ArgumentTypeError("must be at least 1 second")
    return value


def snapshot(battery):
    if (battery / "type").read_text().strip() != "Battery":
        raise ValueError("Selected power supply is not a battery")
    if (battery / "status").read_text().strip() != "Discharging":
        raise ValueError("Battery must remain discharging throughout the measurement")
    energy = int((battery / "energy_now").read_text()) / 1_000_000
    full = int((battery / "energy_full").read_text()) / 1_000_000
    power = int((battery / "power_now").read_text()) / 1_000_000
    if not 0 <= energy <= full or full <= 0 or power < 0:
        raise ValueError("Invalid battery energy/power readings")
    return {"energy_wh": energy, "full_wh": full, "power_w": power}


def summarize(first, last, powers, elapsed):
    used = first["energy_wh"] - last["energy_wh"]
    if used < 0:
        raise ValueError("Battery energy increased; repeat with uninterrupted discharge")
    average = used * 3600 / elapsed
    return {
        "elapsed_seconds": round(elapsed, 2),
        "samples": len(powers),
        "energy_used_wh": round(used, 4),
        "average_w_from_energy": round(average, 3),
        "sample_mean_w": round(statistics.mean(powers), 3),
        "sample_min_w": min(powers),
        "sample_max_w": max(powers),
        "estimated_full_runtime_hours": round(last["full_wh"] / average, 2) if average > 0 else None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=positive_seconds, default=300)
    parser.add_argument("--interval", type=positive_seconds, default=5)
    parser.add_argument("--battery", type=Path, default=Path("/sys/class/power_supply/BAT0"))
    args = parser.parse_args()
    # CLOCK_BOOTTIME includes suspend, unlike Linux's monotonic clock. The
    # energy-delta result remains meaningful if a sleep interval is included;
    # sampled instantaneous watts only describe the awake sampling periods.
    clock = lambda: time.clock_gettime(time.CLOCK_BOOTTIME)
    try:
        first = last = snapshot(args.battery)
        start = clock()
        powers = [first["power_w"]]
        print(f"Measuring for {args.seconds}s; no power settings are changed. Ctrl+C cancels.", file=sys.stderr)
        while (remaining := args.seconds - (clock() - start)) > 0:
            time.sleep(min(args.interval, remaining))
            last = snapshot(args.battery)
            powers.append(last["power_w"])
        print(json.dumps(summarize(first, last, powers, clock() - start), indent=2))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Measurement stopped: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
