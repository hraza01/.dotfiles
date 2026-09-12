#!/usr/bin/env bash
# waybar-clock.sh
# Outputs JSON for the waybar custom clock module:
#   text    -> time shown in the bar
#   tooltip -> calendar with aligned columns (JetBrains Mono) + today highlight
# Pango markup is used for the tooltip; the time text is plain.

set -euo pipefail

today_unpad=$(date +%-d)

# Monday-first week (ISO 8601, macOS-like). cal -m on util-linux.
cal_output=$(LC_ALL=C cal -m 2>/dev/null || LC_ALL=C cal 2>/dev/null)

# Colors
TODAY_BG="#26A65B"
TODAY_FG="#000000"
WEEKDAY_FG="#888888"
DAY_FG="#ffffff"
HEADER_FG="#ffffff"

# --- Build the calendar tooltip as Pango markup ---

# Header (month year) in Titillium Web, bold
header=$(printf '%s' "$cal_output" | sed -n '1p')
header_span=$(printf '<span font_family="Titillium Web" size="16000" weight="bold" foreground="%s">%s</span>' "$HEADER_FG" "$header")

# Weekday row in JetBrains Mono, gray
weekdays=$(printf '%s' "$cal_output" | sed -n '2p')
weekday_span=$(printf '<span font_family="JetBrains Mono" size="11000" weight="normal" foreground="%s">%s</span>' "$WEEKDAY_FG" "$weekdays")

# Day rows — collect into a single string (avoid subshell var loss from pipes)
# Restore the newline stripped by command substitution so read sees the final week.
day_rows=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    line=$(printf '%-21s' "$line")
    row=""
    i=0
    while [ $i -lt 21 ]; do
        cell="${line:$i:3}"
        num="${cell// /}"
        if [ "$num" = "$today_unpad" ]; then
            row+=$(printf '<span font_family="JetBrains Mono" size="11000" weight="bold" foreground="%s" background="%s">%s</span>' \
                "$TODAY_FG" "$TODAY_BG" "$cell")
        else
            row+=$(printf '<span font_family="JetBrains Mono" size="11000" weight="normal" foreground="%s">%s</span>' \
                "$DAY_FG" "$cell")
        fi
        i=$((i+3))
    done
    day_rows+="${day_rows:+$'\n'}${row}"
done < <(printf '%s\n' "$cal_output" | sed -n '3,$p')

# Assemble tooltip with newlines between sections
tooltip="${header_span}"$'\n'"${weekday_span}"
[ -n "$day_rows" ] && tooltip="${tooltip}"$'\n'"${day_rows}"

# Time text for the bar — clean, Titillium Web via waybar's font-family.
time_text=$(date '+%H:%M')

# Emit JSON with proper escaping via python
python3 -c '
import json, sys
print(json.dumps({
    "text": sys.argv[1],
    "tooltip": sys.argv[2],
    "class": "clock"
}))
' "$time_text" "$tooltip"
