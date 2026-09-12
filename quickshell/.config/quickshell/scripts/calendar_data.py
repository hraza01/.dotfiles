#!/usr/bin/env python3
"""Calendar provider for Quickshell clock module."""

import calendar
from datetime import datetime
import json
import sys

def get_calendar():
    cal = calendar.Calendar(firstweekday=0) # Monday-first
    now = datetime.now()
    year = now.year
    month = now.month
    today_day = now.day

    header = now.strftime("%B %Y")
    weekdays = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    month_days = cal.monthdayscalendar(year, month)

    weeks = []
    for week in month_days:
        w = []
        for d in week:
            w.append({
                "day": str(d) if d > 0 else "",
                "today": (d == today_day)
            })
        weeks.append(w)

    return {
        "time": now.strftime("%H:%M"),
        "header": header,
        "weekdays": weekdays,
        "weeks": weeks
    }

if __name__ == "__main__":
    print(json.dumps(get_calendar()), flush=True)
