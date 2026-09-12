#!/usr/bin/env python3
"""System status monitor for CPU and Memory in Quickshell."""

import json
import sys
import time

def read_mem():
    mem = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    mem[parts[0].strip()] = int(parts[1].strip().split()[0])
        total_kb = mem.get("MemTotal", 1)
        avail_kb = mem.get("MemAvailable", 0)
        used_kb = total_kb - avail_kb
        pct = round((used_kb / total_kb) * 100)
        used_gib = round(used_kb / (1024 * 1024), 1)
        total_gib = round(total_kb / (1024 * 1024), 1)
        return {
            "percent": pct,
            "used": used_gib,
            "total": total_gib,
            "tooltip": f"Memory: {pct}%\n{used_gib}GiB / {total_gib}GiB"
        }
    except Exception:
        return {"percent": 0, "used": 0.0, "total": 0.0, "tooltip": "Memory: unknown"}

def read_cpu_times():
    times = {}
    try:
        with open("/proc/stat") as f:
            for line in f:
                if line.startswith("cpu"):
                    parts = line.strip().split()
                    name = parts[0]
                    vals = [int(x) for x in parts[1:]]
                    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
                    total = sum(vals)
                    times[name] = (idle, total)
    except Exception:
        pass
    return times

def calc_cpu_percent(prev, curr):
    idle_delta = curr[0] - prev[0]
    total_delta = curr[1] - prev[1]
    if total_delta <= 0:
        return 0
    return round((1.0 - (idle_delta / total_delta)) * 100)

def main():
    continuous = "-c" in sys.argv
    prev_times = read_cpu_times()
    time.sleep(0.5)

    while True:
        curr_times = read_cpu_times()
        mem_info = read_mem()

        overall_pct = 0
        core_lines = []
        if "cpu" in prev_times and "cpu" in curr_times:
            overall_pct = calc_cpu_percent(prev_times["cpu"], curr_times["cpu"])

        cores = [k for k in sorted(curr_times.keys()) if k != "cpu"]
        for c in cores:
            if c in prev_times:
                cpct = calc_cpu_percent(prev_times[c], curr_times[c])
                core_num = c.replace("cpu", "")
                core_lines.append(f"Core {core_num}: {cpct}%")

        cpu_tooltip = f"CPU: {overall_pct}%"
        if core_lines:
            cpu_tooltip += "\n" + "\n".join(core_lines)

        output = {
            "cpu_percent": overall_pct,
            "cpu_tooltip": cpu_tooltip,
            "mem_percent": mem_info["percent"],
            "mem_used": mem_info["used"],
            "mem_total": mem_info["total"],
            "mem_tooltip": mem_info["tooltip"]
        }
        print(json.dumps(output), flush=True)

        if not continuous:
            break

        prev_times = curr_times
        time.sleep(2.0)

if __name__ == "__main__":
    main()
