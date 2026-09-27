# Optional three-finger drag

Fresh-install tooling for Linux/systemd, using Arch's packaged Python 3.11+,
Git, Rust/Cargo, base-devel and systemd/udev. Build on the
target architecture (x86_64 or aarch64 GNU Linux). Initial source/dependency
downloads require network access. Install dependencies separately as usual.
This feature is outside `setup.sh`, including `all`. Publication changes files
only: no package installation, service enable/start, udev reload, module loading
or device-group changes.

## Private input profile

Copy `profile.example.json` to a mode-0600 file in a private directory **outside
the checkout**. Replace every placeholder there, never in the public template.
Use exactly one `/dev/input/by-path/…-event-mouse` symlink. Set `expected.id_path`
to its udev `ID_PATH` and `expected.name`, `vendor`, `product` to the corresponding
sysfs `device/name`, `device/id/vendor`, `device/id/product` values (four lowercase
hex digits for the IDs). The symlink basename must be `ID_PATH-event-mouse`.
Obtain properties using `udevadm info -q property -n "$device"` and metadata under
`/sys/class/input/$(basename "$(readlink -f "$device")")/device/`; no event stream
needs to be read. Do not capture the results in Git or public issue reports.

The schema rejects unknown/duplicate fields, placeholders, mismatched paths,
udev glob/shell/specifier injection and out-of-range timings. It requires a
touchpad without the keyboard classification. Validate without opening devices:

```sh
profile=/absolute/path/to/private/input-profile.json
python3 -I setup/three-finger-drag/install.py validate --profile "$profile"
```

This profile is the single source for the installed gesture config, exact udev
match, escaped device unit, explicit `--device`, device allowlist and startup
metadata verification. Missing/mismatched metadata fails closed; no broad input
discovery occurs. Generated files and build receipts are private deployment data.

## Build from a fresh clone

Run from the checkout as an ordinary user. Use distro `/usr/bin/{python3,cargo,
rustc,git,cc}`, not rustup shims. The destination must not exist and must be outside
the checkout. A generic temporary build parent is fine; no particular retained
temporary artifact is required:

```sh
work=$(mktemp -d)
bash setup/three-finger-drag/build.sh --output "$work/build" --jobs 2
build="$work/build"
sha256sum "$build/receipt.json" "$profile"
sha256sum setup/three-finger-drag/{install.py,gesture_profile.py,pins.json}
sha256sum setup/three-finger-drag/build.py  # compare with receipt.builder_sha256
```

`pins.json` pins the upstream commit, Git archive and Cargo.lock. A fresh bare Git
fetch produces a checksum-verified archive; extraction rejects links/traversal.
The builder uses private HOME/CARGO_HOME/target/temp directories, a minimal
environment and the extracted source as cwd. It refuses ancestor `.cargo/config`
or `config.toml` files (choose another build parent if present). Cargo fetches
locked dependencies, then builds and runs **library tests only**, frozen/offline.
It never compiles as root or launches upstream input-proxy integration tests.

Success produces `linux-3-finger-drag` and `receipt.json`. The receipt records the
source pins, native target, toolchain, builder checksum and binary checksum.
Review these and record the receipt/profile/code digests independently. This is
a local build receipt, not a signed upstream attestation or a promise of identical
binaries across toolchains. Failed builds remain private for inspection.

To update `pins.json`, review the new upstream commit, then hash its exact
`git archive --format=tar` output and `Cargo.lock`. Update the commit and both
digests together; a GitHub-generated download archive is not interchangeable.
Run a fresh build and tests, and record new review digests before installation.

## Reviewed root staging and publication

The commands below are **future owner actions**, not part of setup. First review
the three publisher files and private inputs. Never sudo code from the checkout.
Copy into a fresh root-controlled stage (source arguments are quoted/positional):

```sh
set -eu
# Fill these from the independent review above, not from the copied stage.
installer_sha=REVIEWED_INSTALLER_SHA256
model_sha=REVIEWED_GESTURE_PROFILE_CODE_SHA256
pins_sha=REVIEWED_PINS_SHA256
profile_sha=REVIEWED_PROFILE_SHA256
receipt_sha=REVIEWED_RECEIPT_SHA256
stage=$(sudo /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash --noprofile --norc -c '
  set -euo pipefail
  umask 077
  stage=$(mktemp -d /run/three-finger-review.XXXXXXXX)
  install -o root -g root -m 0400 -- "$1/install.py" "$1/gesture_profile.py" "$1/pins.json" "$stage/"
  install -o root -g root -m 0400 -- "$2" "$stage/input-profile.json"
  install -o root -g root -m 0400 -- "$3/receipt.json" "$stage/receipt.json"
  install -o root -g root -m 0400 -- "$3/linux-3-finger-drag" "$stage/linux-3-finger-drag"
  printf "%s\n" "$stage"
' sh "$PWD/setup/three-finger-drag" "$profile" "$build")

# Verify all copied code before running any of it as root; failure stops here.
printf '%s  %s\n' "$installer_sha" "$stage/install.py" \
  "$model_sha" "$stage/gesture_profile.py" "$pins_sha" "$stage/pins.json" |
  sudo sha256sum --check --strict -
sudo /usr/bin/python3 -I "$stage/install.py" install \
  --profile "$stage/input-profile.json" --profile-sha256 "$profile_sha" \
  --artifact "$stage/linux-3-finger-drag" \
  --receipt "$stage/receipt.json" --receipt-sha256 "$receipt_sha"
```

The publisher validates root-owned nonsymlink paths, independently supplied review
digests, the receipt's source/target and the **actual in-memory artifact bytes**.
It never executes the submitted binary during publication. Device metadata must
match and `/dev/uinput` must already be root:root 0600; if absent, separately review
loading `uinput`, then retry. No input-group or world-writable-device workaround.

It publishes a binary/checker/receipt under `/usr/local/lib/dotfiles-three-finger-drag`,
the private profile and generated application config under `/etc/dotfiles-three-finger-drag`,
and the service, scoped udev tag and future-boot module-load entry under `/etc`.
Private directories are 0700, private data/code 0400, the binary 0500; system
unit/rule/module files are 0644. Every existing destination, loaded unit, mask or
inherited drop-in is a conflict. **Existing installations require a separate
coordinated migration; this installer does not update them.**

Files are fully written/fsynced before atomic no-clobber publication. Ordinary
failures roll back only new files/directories; a crash/power loss can leave a
partial install. Inspect it before retrying. There is no overwrite/uninstall mode.

## Separate activation and recovery

Keep an independent keyboard terminal available. First inspect the installed
unit/rule/config; these contain local identifiers and must remain out of Git.

```sh
set -eu
sudo python3 -I /usr/local/lib/dotfiles-three-finger-drag/install.py verify
sudo systemd-analyze verify /etc/systemd/system/dotfiles-three-finger-drag.service
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
device=$(sudo python3 -I -c 'import json; print(json.load(open("/etc/dotfiles-three-finger-drag/input-profile.json"))["device"])')
# Trigger only the device selected by the installed private profile.
sudo udevadm trigger --action=change "/sys/class/input/$(basename "$(readlink -f "$device")")"
sudo udevadm settle --timeout=10
systemctl is-active "$(systemd-escape --path --suffix=device "$device")"
# Continue only after all checks succeed, with fingers off the touchpad.
sudo systemctl enable --now dotfiles-three-finger-drag.service
```

Recovery removes both boot and device activation links:

```sh
sudo systemctl disable --now dotfiles-three-finger-drag.service
```

The exact udev rule only adds a systemd tag. `BindsTo`/`After` bind lifetime to the
physical device; enablement adds boot/device wants. `Restart=no` avoids repeated
grabs after a crash. A new device activation may start an enabled service, subject
to rate limiting. SIGTERM gets three seconds before SIGKILL; closing descriptors
releases grabs, but forced termination cannot guarantee application button release.
If needed, use `sudo systemctl kill --kill-whom=all --signal=SIGKILL dotfiles-three-finger-drag.service`,
then confirm normal touchpad behavior.

## Access and input limitations

The root service has `DevicePolicy=closed`, **one physical touchpad read-only**
plus `/dev/uinput` read/write (and systemd's standard pseudo-devices), empty
capabilities, no-new-privileges, read-only filesystem, hidden homes and private
network/temp namespaces. No broad input access is granted. Root is retained for
the required device ownership; this is not a claim of an unprivileged proxy.
uinput can synthesize other event classes: the cgroup is not a pointer-only output
filter. Metadata verification and upstream open still have a replacement race;
eliminating that requires an upstream descriptor/broker change.

The upstream proxy grabs the physical touchpad for its lifetime and creates a
clone plus drag mouse. Two-finger tapping can regress while the proxy is active;
persistence and portable packaging do not fix gesture behavior.
The pinned `src/runtime/gesture.rs` recovery reasserts a tracking ID without first
closing its slot; upstream [PR 30](https://github.com/lmr97/linux-3-finger-drag/pull/30)
and [PR 31](https://github.com/lmr97/linux-3-finger-drag/pull/31) discuss resync,
buffering and scrolling issues, without establishing the tap regression's cause.
This tooling carries no gesture-engine patch. Live sandbox, suspend/hotplug and
input behavior still need deliberate target-machine validation before adoption.
