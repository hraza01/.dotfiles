# Battery and energy tuning

Keep power-profiles-daemon as the CPU/platform policy owner. The battery module
already switches its supported profiles; do not layer a competing CPU policy
daemon over it. Hardware policy changes should follow comparable measurements.

## Desktop changes and activation

- **Lid close:** the handler uses `systemctl --check-inhibitors=yes sleep`.
  Systemd 256+ selects a supported operation according to `SleepOperation=`;
  it can use suspend when hibernation is unavailable (including kernel lockdown).
  Lock/readiness and docked-display behavior are retained. This script is read
  on each lid event, so the fix applies on the next lid close without a reload.
- **Panel:** brightness reconciliation is every 30 seconds while content is
  allowed, with immediate refresh on keys, scrolling and hover. Network changes
  trigger snapshots through `nmcli monitor`; a 30-second fallback updates signal
  strength/Tailscale state and handles a failed monitor. CPU/memory updates are
  every five seconds. Privacy checks retain their one-second cadence and closed
  failure behavior, using `/proc` instead of starting `pgrep` each time.
  Load these changes later with the existing shell's `shell reload` IPC or a new
  login. File watching is disabled; editing QML does not reload the running panel.

## Optional battery idle policy

Uncomment `export DOTFILES_BATTERY_IDLE=1` in
`sway/.config/sway/environment` before a future normal login. The idle launcher
then supplies these timeouts to one `swayidle` process:

| Action | Battery | AC / unknown power |
| --- | --- | --- |
| Lock | 5 minutes | 5 minutes |
| Display power off | 5 minutes | 10 minutes |
| Automatic sleep | 20 minutes | Disabled |

The default remains lock at 5 minutes, screen off at 10, no automatic sleep.
Battery actions require a discharging system battery and no online external
power source. Power is checked at each timeout; an AC/battery transition after
a timeout has already fired takes effect on the next idle cycle. Display power
returns on activity. The existing Hyprlock/swaylock pre-sleep hook handles locking.
Wayland idle inhibitors stop the idle countdown; automatic sleep also explicitly
honors logind sleep blockers. Background jobs that must keep running can use
`systemd-inhibit --what=sleep --mode=block --why="Long-running job" command ...`.

Sway reload does not replace an existing swayidle process. Activate or revert the
idle policy at a normal logout/login after saving work, rather than starting a
second idle owner. Comment the export again to return to the default policy.

## Measure before deeper tuning

Run from the checkout on battery:

```sh
python3 -B setup/power/measure.py --seconds 600
```

The helper only reads sysfs and prints JSON. It reports energy used, average watts
from the energy delta, and instantaneous power samples. Short runs can show zero
energy change because the battery gauge updates in steps; use 5–15 minutes for
comparisons. Runtime is an extrapolation at that workload, not a prediction.
Keep brightness, workload, network and peripherals comparable, and repeat a
baseline if other activity changes. No calibration, stress test or power setting
change is performed. Abort a run if AC was connected between samples, even if
charging stopped before the next reading.

For closed-lid drain, record `energy_now` and elapsed wall time before/after a
normal sleep and confirm a successful suspend/resume in the journal. Compute
`(before - after) / 1,000,000 / elapsed_hours` for watts. Verify the actual
sleep/resume cycle after saving work; a supported-operation query alone cannot
prove that every device resumes correctly.

## Follow-up hardware policies

- **Charge limit:** an optional 75% start / 80% stop policy suits mostly-plugged-in
  use. The ThinkPad exposes `charge_control_start_threshold` and
  `charge_control_end_threshold` under `/sys/class/power_supply/BAT0`. Record their
  existing values before changing them and restore those values to revert. A
  limit protects long-term capacity but reduces available unplugged runtime;
  persistence is firmware-dependent. Choose this separately from runtime tuning.
- **AC/battery profiles:** balanced on AC and power-saver on battery can be
  automated later, with an explicit manual override so clicking the bar is not
  immediately undone. The existing manual profile control remains the owner.
- **CPU/PCIe:** compare a battery-only performance cap or selective runtime PM
  one change at a time. Measure completed-work energy as well as watts. Do not
  assume an active NVMe PCI device means its internal low-power states are off.
- **Applications/video:** compare normal browsing and video separately, including
  verification of actual browser hardware decoding. Idle measurements cannot
  establish video-playback efficiency.

Firmware updates, sleep tests, profile switching, charging limits and device power
experiments belong in a later maintenance window. The source changes above do not
require installing packages or restarting system services.
