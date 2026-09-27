# Hyprlock on Sway

The Stow package provides `.config/hypr/hyprlock.conf`, a readiness adapter and
presentation-data helper. It uses Sway's standard session-lock protocol;
Hyprland is not required. Setup and the adapter require Hyprlock **0.9.6**.
Kernel/account metadata is obtained at runtime and escaped for Pango;
the footer uses the current local timezone and English date names.

Password PAM and native fingerprint authentication are enabled independently.
An unavailable or unenrolled reader leaves password authentication available.
No fingerprint templates are installed by this package; enrollment is local.
The 0.9.6 implementation can retain an old native prompt
after verification ends, so `lock.py` derives presentation state from the native
verification lifecycle instead of displaying that stale prompt.

## Configuration

- The background is opaque pure black, with JetBrainsMono Nerd Font Mono.
- Header/status/footer use secondary gray; the native input displays `*` masks.
- Cursor hiding is requested with `general:hide_cursor = true`; verify it on the
  actual compositor/outputs, including pointer motion. Hyprlock 0.9.6 can retain
  Sway's previous cursor image until the first pointer event, so the adapter asks
  Sway to use its minimum 100ms cursor-idle timeout only while the native locker
  runs, then restores Sway's default disabled timeout. Failure of this visual
  workaround does not claim or prevent lock readiness. Animations are disabled.
  There is no grace-period bypass.
- Native Escape and Ctrl+U both clear the password.
  The visible hint is `Esc clears · Enter submits`; Ctrl+U is not advertised.
  The account stays fixed and neither key promises a backend conversation reset.
  The plain header starts `Arch Linux`; the literal `host login:` label appends
  the current account. Hyprlock itself is unpatched.
- Every output receives a lock surface and the same simple layout. Positions are
  output-local logical pixels and can be adjusted in the config.

`screen-data.py` supplies runtime labels. Fingerprint readiness is shown only after
Hyprlock reports a successful verification start; claiming the reader is insufficient.
Stop, failure, suspension and disconnection remove the ready state. A stale
observer heartbeat expires to unavailable. It does not authenticate, enroll
fingerprints, claim the reader or unlock the session.

## Activation

After the [setup prerequisites](../README.md#setup), package/PAM review and
`./setup.sh shell`, prepare with `./setup.sh auth`. The repository candidate is
checked before package changes. Launch through the adapter:

```sh
python3 "$HOME/.config/hypr/lock.py"
```

The adapter is reviewed for Hyprlock 0.9.6, whose `onLockLocked called` INFO event
comes from the compositor's session-lock acknowledgement. It consumes that event
without storing native logs, keeps the output pipe drained, and coordinates
concurrent requests using a private guard/lifetime flock. Success is never based
on a PID alone. This transient supervisor is unprivileged and makes no
authentication decisions. The native locker handles passwords and fingerprints.

Fingerprint-state updates use the documented **SIGUSR2 label-refresh signal**
only after checking that its handler is installed; SIGUSR1 is never used. Unknown
Hyprlock versions fail the readiness handoff so Sway can use its reviewed safety
fallback instead of trusting an unverified log contract.

Test Hyprlock manually from the real Sway session with recovery access retained.
Fingerprint permission checks must originate in that graphical session, not
merely an SSH process with copied environment variables.

The Sway manual shortcut and 300-second idle timeout use this adapter. If Hyprlock
cannot acknowledge the compositor lock within its single bounded two-second
handoff, fails startup or has an unreviewed version, they invoke an installed
plain-black swaylock fallback. Because Hyprlock 0.9.6 has no native ready-fd and an
unacknowledged process cannot be safely replaced, the finite pre-sleep inhibitor
path uses `swaylock -f` directly and does not background it. Legacy GTKlock source
is retained only as inactive recovery material.

See [greetd migration](../greetd/README.md) for boot-owner activation, validation
and rollback. Tests, screenshots and deployment records belong outside this repo.
