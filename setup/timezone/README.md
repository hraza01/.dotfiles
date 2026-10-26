# Automatic time zone

Like macOS's "Set time zone automatically", but from the public IP address.
Date and time themselves come from NTP (`systemd-timesyncd`); setup only makes
sure it is on (`timedatectl set-ntp true`).

## What setup does

`./setup.sh gui` runs `install_auto_timezone` (`setup/packages.sh`), which publishes
root-owned copies through `setup/managed_desktop.py timezone` (staged, verified,
rolled back on failure):

| Source | Installed as | Mode |
|---|---|---|
| `dotfiles-auto-timezone` | `/usr/local/libexec/dotfiles-auto-timezone` | 0755 |
| `dotfiles-auto-timezone.service` | `/etc/systemd/system/` | 0644 |
| `90-dotfiles-auto-timezone` | `/etc/NetworkManager/dispatcher.d/` | 0755 |

It then enables `NetworkManager-dispatcher.service` if needed, reloads systemd,
turns on NTP and runs one check immediately.

## How it works

1. NetworkManager runs the dispatcher hook when a connection comes **up** or
   connectivity becomes **full** (after a captive portal, for example).
2. The hook starts the oneshot `dotfiles-auto-timezone.service`. Starts while a
   check is running merge into it.
3. The updater skips when internet traffic leaves through a tunnel (VPN,
   WireGuard, Tailscale exit node): only Ethernet/Wi-Fi routes are trusted.
4. It asks `ipinfo.io`, then `ipapi.co`, then `ipwho.is` for the IP's time zone,
   retrying for about half a minute while DNS settles.
5. A known zone (`timedatectl list-timezones`) that differs from the current one
   is applied with `timedatectl set-timezone`.

The service runs as root only so timedated accepts the change without a prompt;
it has no capabilities and a read-only, sandboxed view of the system.

Programs that read the zone per update (hyprlock, tuigreet, the Quickshell bar)
follow the change; long-running apps may keep their old zone until restarted.

## Privacy and accuracy

Each check sends the public IP address to the providers above. IP location is
city-level and follows the network's exit point: a hotspot, travel router or ISP
that routes through another region can report a different zone.

## Logs

```sh
journalctl -u dotfiles-auto-timezone        # each check and any change
sudo systemctl start dotfiles-auto-timezone # check now
```

## Turn off and on

```sh
sudo chmod -x /etc/NetworkManager/dispatcher.d/90-dotfiles-auto-timezone
sudo timedatectl set-timezone America/Toronto   # pick the fixed zone
```

`chmod +x` turns it back on. Rerunning setup keeps the off state: it only rewrites
files whose content changed.

## Removal

```sh
sudo rm /etc/NetworkManager/dispatcher.d/90-dotfiles-auto-timezone \
  /etc/systemd/system/dotfiles-auto-timezone.service \
  /usr/local/libexec/dotfiles-auto-timezone
sudo systemctl daemon-reload
```
