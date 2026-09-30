#!/usr/bin/env python3
"""Calendar provider for Quickshell clock module."""

import calendar
from datetime import datetime
import json
import sys

def get_calendar(offset=0):
    cal = calendar.Calendar(firstweekday=0) # Monday-first
    now = datetime.now()
    index = now.year * 12 + now.month - 1 + max(-1200, min(1200, offset))
    year, month = index // 12, index % 12 + 1
    today_day = now.day

    header = datetime(year, month, 1).strftime("%B %Y")
    weekdays = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    month_days = cal.monthdayscalendar(year, month)

    weeks = []
    for week in month_days:
        w = []
        for d in week:
            w.append({
                "day": str(d) if d > 0 else "",
                "today": (year == now.year and month == now.month and d == today_day),
                "iso": f"{year:04d}-{month:02d}-{d:02d}" if d else ""
            })
        weeks.append(w)

    return {
        "time": now.strftime("%H:%M"),
        "offset": offset,
        "header": header,
        "weekdays": weekdays,
        "weeks": weeks
    }

if __name__ == "__main__":
    print(json.dumps(get_calendar(int(sys.argv[1]) if len(sys.argv) > 1 else 0)), flush=True)
