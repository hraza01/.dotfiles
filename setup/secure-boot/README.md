# Staged Secure Boot artifacts

## Start here: owner and LLM handoff

**Read this entire document and the relevant scripts before proposing changes to
boot, kernels, initramfs, graphics drivers, encryption, signing, or recovery.**
Read [the repository setup contract](../../README.md#boot-and-login) too. This is
an operational safety contract, not permission to run privileged commands.

### Scope and portability status

The **architecture is reusable; the current bootstrap is not a general-purpose
installer**. `install.py`, `lockdown.py`, and `promote_recovery.py` contain reviewed
reference-machine pins, release checks, paths and state-transition assumptions.
They are historical, one-way migrations, not idempotent setup commands for a new
laptop or a way to refresh an already completed deployment.

| Layer | Reusable design | Review for each machine |
| --- | --- | --- |
| Firmware | Verify the signed loader and UKIs | Firmware version, Option ROM signers, factory PK/KEK/db/dbx, revocations, recovery controls |
| Boot selection | systemd-boot, hidden menu, regular/LTS/recovery choices | ESP location/size, EFI architecture, existing entries, key timing, fallback loader ownership |
| Early boot | Sign kernel, initramfs and embedded command line together | LUKS/LVM/filesystem layout, identifiers, drivers, microcode and initramfs hooks |
| Appearance | Plymouth/Ashborn inside the initramfs | KMS/GPU support, unlock prompt, boot and shutdown transitions |
| Running kernel | Explicit integrity lockdown | Module signatures and kernel trust, DKMS/proprietary drivers, debugging/hibernation requirements |
| Updates | Build privately, sign, verify, then replace | Package triggers, competing writers, pinned build policy and tool interfaces |
| Recovery | Frozen signed image and matching modules | Actual successful boot, independent backups, module restoration and refresh policy |

`boot_artifacts.py` discovers future installed kernel releases from package
ownership, but still enforces **x86-64, `/boot`, both Arch kernel packages, exact
output paths and a specific storage/Plymouth build policy**. It also requires the
frozen recovery release `6.18.54-2-lts` and exact backup/manifest paths. Changing JSON
alone cannot select a newer recovery release or remove those constraints. The
version-1 config below is a preservation manifest, **not a general hardware-profile
interface**.

For a future machine, the intended separation is:

1. **Public reusable tooling:** verification, staged publication, hook integration
   and recovery mechanisms, with tests for each supported policy.
2. **Private per-machine inputs:** inspected storage/ESP mappings, approved kernel
   arguments and build policy, certificate fingerprints, recovery metadata and
   receipts. Generate and review these locally; do not clone another machine's
   `/boot`, command line, firmware entry numbers, signing state or recovery files.
3. **Owner-controlled activation:** test boots, explicit firmware operations and
   acceptance evidence. Neither profile generation nor activation is currently
   automated by this repository.

A future profile-based refactor must implement that separation explicitly,
validate its schema, and add tests before claiming multi-machine support. Do not
merely replace release/hash constants to get past refusals. A fresh machine can
use systemd-boot directly; GRUB is not an architectural requirement, although the
current tooling preserves and validates the reference GRUB presets. Do not assume
a future ThinkPad model, GPU option or firmware behaves identically.

### Reference acceptance, not a substitute for inspection

The reference deployment boot-tested regular, LTS and frozen recovery UKIs with
Secure Boot enabled, Setup Mode disabled and `[integrity]` lockdown. Recovery
promotion closed the temporary non-lockdown menu-entry exception. Normal boot
hides the menu; repeatedly tapping **Space** during firmware handoff opened it,
while continuously holding Space was not reliable on that machine. Plymouth,
unlocking and login were preserved; the owner also confirmed LTS Wi-Fi, audio and
touchpad operation. A reported shutdown fade-out discrepancy was deferred; its
cause was not established.

The completed reference `/boot/loader/loader.conf` policy is:

```text
default arch-linux.efi
timeout 0
editor no
secure-boot-enroll off
```

These select the regular UKI, hide the normal menu, disable the boot-argument
editor, and disable automatic key enrollment. EFI variables can override the
default and timeout; inspect the effective state as well as the file. This is a
reference, not permission to overwrite another machine's configuration. The
historical installer requires these four directives in this order with an initial
`timeout 5`, then changes only that timeout after the initial updater succeeds.

Initial staged rebuilds and boot tests succeeded. The first subsequent real
package-upgrade invocation still needs observation; synthetic tests do not prove
future package transactions or firmware updates will behave correctly. Exact
acceptance evidence stays in private receipts. Always inspect live state again:
historical success does not prove another machine or a later state is safe.

### Mandatory rules for a future assistant

- **Inventory before acting.** Read source, installed configuration, versions and
  version-matched documentation. Explain dependencies, affected layers, failure
  modes, validation and rollback; obtain owner approval before implementation.
- **Separate authority.** Read-only inspection is not approval to install packages,
  rebuild boot files, change services, enroll/reset keys, alter boot order or
  reboot. The owner runs reviewed privileged operations. Never automate password
  entry or authentication challenges.
- **No destructive shortcuts.** Do not clear all firmware keys, force enrollment,
  experimentally trust TPM event-log hashes, recursively remove efivarfs protection,
  reset the TPM or replace working recovery just to silence an error. For immutable
  EFI variables, inspect the state before any owner-approved, narrowly targeted
  flag change, and restore protection. Never use a wildcard for this operation.
- **Preserve trust.** PK controls platform ownership, KEK authorizes database
  updates, db authorizes EFI software, and dbx revokes it. Inspect and back up all
  four. Reviewed sbctl 0.18's `export-enrolled-keys` does **not** export dbx. Raw
  efivarfs files have a four-byte attributes prefix; neither a raw backup nor a
  bare ESL is automatically an authenticated update. Do not improvise restoration
  by writing backup bytes directly to efivarfs.
- **Distinguish certificates.** Windows boot certificates are not Microsoft
  third-party/Option ROM CAs. OEM/Microsoft trust improves compatibility but
  broadens the trust boundary. Detecting an Option ROM does not identify its
  signer. Review actual certificates, current vendor guidance, certificate
  transitions and revocations, not just sbctl's vendor summary.
- **Verify firmware semantics.** On the reference firmware, “Reset to Setup Mode”
  removed only PK; “Clear All Secure Boot Keys” removed all four databases. Other
  firmware may differ. Read help/confirmation text and compare databases after
  each operation. Factory restoration can change toggles. Secure Boot being Off
  is not the same as Setup Mode being enabled. Obtain BitLocker/TPM-bound-unlock
  recovery credentials before changes on machines using those mechanisms.
- **Protect secrets.** Never publish private signing keys, LUKS/BitLocker recovery
  material, private command lines, hardware identifiers, raw logs or backup trees.
  Prefer sanitized counts, booleans and reviewed hashes. Use fresh per-device
  signing keys by default; explain the wider impact before reusing keys. Maintain
  encrypted off-device key and recovery backups. Local root possession of signing
  keys limits protection against an existing root compromise.
- **Investigate refusals.** Identify a changed environment versus an incorrect guard,
  add a regression test, and exercise real read-only inputs before retrying. Do
  not blindly rerun, refresh pins, weaken checks or claim “nothing changed” without
  checking destinations. Preserve partial state and private failure reports.
- **Verify in stages.** Independently check bytes before root execution; self-hashing
  is not a script's trust anchor. Keep other writers idle, preserve backups and
  free-space reserves. Signature validity, payload verification, successful
  publication and actual bootability are different acceptance checks.
- **Do not overclaim security.** Secure Boot is not a malware scan. Encryption does
  not protect documents from applications in an unlocked session. `[none]` means
  lockdown is inactive even with Secure Boot enabled. Check actual selected boot
  paths and active policy; do not rely solely on signatures or a firmware toggle.

### Per-change checklist

For **every setting**, record privately: source of truth, dependency chain,
intended value, writer/update mechanism, backup, validation, and rollback path.
Resolve the following before boot-changing commands:

- [ ] Owner requirements: appearance, recovery-menu behavior, dual boot,
  hibernation, virtualization/debugging and agreed trust/threat model.
- [ ] Boot path, EFI architecture, ESP device/mount/space, fallback files,
  firmware defaults/one-shot selections, SecureBoot and SetupMode flags.
- [ ] Verified storage layout and working unlock credentials. A Btrfs filesystem's
  virtual device number is not its underlying block-device number.
- [ ] Explicit kernel arguments, preserving order and duplicate semantics. A set
  comparison is insufficient; another machine's identifiers must not be reused.
- [ ] Initramfs hooks, presets, drivers, files and overrides. Preserve encryption,
  filesystems and Plymouth together; inspect early and main archives. Headers may
  be real `build/` directories; Btrfs may be built in rather than loadable. Test
  those cases instead of assuming one package layout.
- [ ] Graphics/storage/input/network drivers and module-signing enforcement.
  UKI signing does not sign DKMS/proprietary modules or establish kernel trust in
  their signer. Test hardware with lockdown active, especially a different GPU.
- [ ] Key backend, permissions and off-device backups. Root-owned searchable key
  directories with private `0400`/`0600` key files are not an exposed-key condition.
- [ ] Package/initramfs hooks, manual build tools and competing updater services.
  Establish one publication owner. `bootctl update --variables=no` may still write
  fallback EFI files. Saved signing mappings alone do not prove freshness or
  correct rebuild/copy/sign ordering of loaders and signed sidecar files.
- [ ] Recovery image, matching modules, rescue media, firmware access and data
  backups. A signed recovery with weaker policy is still a selectable exception;
  explicitly accept it temporarily or replace it after hardened boot tests.

### Activation gates and ongoing maintenance

1. Inventory/back up and preserve the working path and factory databases. On a
   new machine, do not clear all keys as the first action.
2. Stage builds, verify payloads/signatures against the intended certificate, and
   test rebuild/sign/publish integration before relying on package updates.
3. Add a test path without discarding the existing default. Owner-test regular/LTS,
   Plymouth/unlock/login and hardware before enforcement where practical. Use
   reviewed one-time selections, never copied firmware entry numbers.
4. Separately approve enrollment; use the verified least-destructive Setup Mode
   transition if needed. Preserve required OEM trust and dbx, then inspect the
   result before enabling enforcement. `--append` was appropriate only after
   verifying the reference machine's existing trust set.
5. Confirm Secure Boot and active lockdown on actual regular, LTS and recovery
   boots. If adding lockdown later, migrate the pinned command line deliberately,
   retest, and close any temporary weaker recovery exception.
6. Verify the permanent default and reliable hidden-menu access. A frozen UKI is
   not a userspace/filesystem rollback; validate the module-restoration plan.
   Retire GRUB or other fallbacks only with separate approval.
7. Observe the next real full package upgrade and generated artifacts, then boot.
   A failed post-transaction hook does not undo installed packages. Inspect failures
   before rebooting; never label an unobserved hook invocation “tested.”
8. Periodically review firmware/dbx updates, supported kernels, storage/report
   retention, signing-key backups and recovery freshness. Refresh recovery only
   after boot tests, not just a successful build. A newer frozen release requires
   reviewed code/policy changes today; the supplied promotion is not a general
   refresh command. Repeat the relevant checks when hardware, storage, packages
   or tool interfaces change.

Consult current sources, not remembered flags:
[Arch Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot),
[Arch UKIs](https://wiki.archlinux.org/title/Unified_kernel_image),
[sbctl FAQ](https://github.com/Foxboron/sbctl/wiki/FAQ),
[systemd-boot](https://www.freedesktop.org/software/systemd/man/latest/systemd-boot.html),
and the installed tools' version-matched man pages/help.

### Prompt to start a future LLM session

> Read `setup/secure-boot/README.md`, the repository README, and the scripts relevant
> to my requested change before acting. Start with read-only inspection; distinguish
> verified live state, historical pins, and proposed changes. For every configuration
> change, explain dependencies, update ownership, risks, validation and rollback.
> Do not blindly reuse another machine's identifiers, keys, firmware operations,
> hashes or profiles. Ask before privileged/destructive actions and activation.
> Preserve my working boot path, Plymouth, encryption and recovery. Report gaps
> honestly; never bypass a guard just to make setup pass.

A README is not automatically loaded by every LLM client. Explicitly attach or
reference this handoff at the start of a session; it is linked from the main README
but does not override the owner's consent or the client's safety rules.

## Preparation-only setup group

From the installing user's own login session, without `sudo ./setup.sh`:

```sh
./setup.sh secure-boot
```

This opt-in group is **excluded from `all`**. Requests combining it with `boot`
or `all` are rejected before any group work. It requires Arch Linux (`ID=arch`),
x86-64 UEFI, the existing Python/systemd/mkinitcpio/util-linux OS prerequisites,
and a real vfat EFI System Partition mounted at `/boot`. It does not partition,
format, remount or adapt unsupported layouts.

Before installation it reports sanitized platform, package/tool, space, firmware
flag and known-path presence checks. Private or unreadable migration state is
reported as unknown, not treated as absent or repaired. Presence of a helper,
config or EFI image is not proof that it is valid or that a migration completed.

Missing `systemd-ukify`, `sbctl`, `sbsigntools` and `efibootmgr` are resolved from
the existing package databases to exact `core/` or `extra/` candidates. Ambiguous
or custom-repository candidates are refused before sudo. Missing tools are
installed in one interactive `pacman -S --needed` transaction; there is no
`--noconfirm`, hook suppression, standalone database refresh or automatic upgrade.
If the databases are stale, stop and review a normal full system upgrade. When all
tools are already installed, the group performs checks without invoking sudo.

**Package installation is not read-only.** Package scripts and existing mkinitcpio,
sbctl or custom hooks can rebuild/re-sign boot files as root. Review the transaction
and any existing/partial migration before proceeding. Failure stops setup; it does
not undo a package transaction, repair the machine or establish boot readiness.

The group's own actions are queries and tool installation only. It does not run
`install.py`, `lockdown.py` or `promote_recovery.py`, publish the updater/hook,
configure kernel arguments, generate/enroll/reset keys, change firmware variables,
modify boot order, enable services or reboot. Successful preparation is **not**
installation of a portable profile or completion of Secure Boot setup. Follow the
handoff, activation gates and reviewed source above for those separate steps.

The inspector can also be run without installation:

```sh
python3 -I -B setup/secure-boot/prepare.py --preflight
python3 -I -B setup/secure-boot/prepare.py --report
```

`--preflight` permits missing installable tools; `--report` also requires their
packages and commands. Both are read-only and privacy-filtered, but neither is a
complete hardware/security audit or a substitute for a real boot test.

## Updater implementation details

`boot_artifacts.py` builds both installed Arch kernels and systemd-boot in private
storage, verifies their signatures and payloads, then publishes exactly:

* `/boot/EFI/Linux/arch-linux.efi`
* `/boot/EFI/Linux/arch-linux-lts.efi`
* `/boot/EFI/systemd/systemd-bootx64.efi`

The updater uses Python's standard library and installed `pacman`, `mkinitcpio`,
`lsinitcpio` (provided by mkinitcpio), `ukify`, `sbctl`, `sbverify`, and `systemctl` (including those programs' normal
runtime dependencies). It does not run `bootctl`, `efibootmgr`, key enrollment, or
firmware writes. GRUB images and mkinitcpio presets are preserved.

## Installation contract

The installer must provision the following before enabling the hook:

| Asset | Installed location | Ownership/mode |
| --- | --- | --- |
| `boot_artifacts.py` | `/usr/local/libexec/dotfiles-boot-artifacts.py` | root:root, 0755 or 0644 |
| `boot-artifacts.hook` | `/etc/pacman.d/hooks/zzz-dotfiles-boot-artifacts.hook` | root:root, 0644 |
| Preservation config | `/etc/dotfiles-secure-boot/config.json` | root:root, 0600 recommended |
| Private state and recovery backups | `/var/lib/dotfiles-secure-boot` | root:root, 0700 |

All parents must be root owned and not group/other writable. Script, config,
keys, output files, and their parents must not be symlinks. Command executables
may use root-owned links to trusted installed files. The db private key is the
default file-backed `/var/lib/sbctl/keys/db/db.key` (0400 or 0600); its certificate is
`/var/lib/sbctl/keys/db/db.pem`. The default PK/KEK hierarchy and GUID must also
exist and be trusted, since sbctl loads that hierarchy. No keys are copied into
reports. Keep private key contents root-only and key directories root-controlled,
not group/other writable; searchable 0755 directories are supported.

The installer journals integration mutations immediately so ordinary-error
rollback can identify even a partially completed write. If integration fails and
the installed pacman hook cannot be removed safely, **E28 means partial
integration**: retain the helper, preservation config and command-line file that
the surviving hook needs. Inspect the private installer report and repair the
integration explicitly; do not remove those dependencies beneath a live hook.

`/boot` must already be a writable, root-owned vfat ESP mounted from a block
device, without nested mounts. Its mount permissions must disallow non-root
writes (for example root ownership and `umask=0077`). The installer must create
`/boot/EFI/Linux` and `/boot/EFI/systemd`. The updater verifies the mount source's
block-device `stat().st_rdev` against mountinfo and the mounted filesystem; it
does not infer the ESP from a Btrfs root filesystem device number.

`systemd-boot-update.service` must already be **disabled (or masked) and inactive**.
The updater checks it, including again before publication, and changes no services.
Keep mkinitcpio configuration and build hooks root trusted: they execute as root.
Other tools and hooks must not concurrently write these three managed outputs.

### Version 1 preservation configuration

The JSON object must have exactly these keys; replace each placeholder with a
lowercase 64-digit SHA-256 of the corresponding **file bytes**. The concrete release
and paths below describe the reference version-1 layout, not a portable new-machine
profile. Review implementation constraints before adapting it:

```json
{
  "version": 1,
  "esp": "/boot",
  "cmdline_sha256": "<sha256 of /etc/kernel/cmdline>",
  "db_cert_sha256": "<sha256 of /var/lib/sbctl/keys/db/db.pem>",
  "recovery": {
    "image": "/boot/EFI/Linux/arch-linux-lts-recovery-6.18.54-2.efi",
    "sha256": "<sha256 of the frozen signed recovery UKI>",
    "kernel_release": "6.18.54-2-lts",
    "modules_backup": "/var/lib/dotfiles-secure-boot/recovery/modules/6.18.54-2-lts",
    "modules_manifest": "/var/lib/dotfiles-secure-boot/recovery/modules-manifest.json"
  }
}
```

`/etc/kernel/cmdline` is explicit, nonempty, single-line ASCII text, optionally
ending with **one** LF; a NUL is not allowed in this file. Its exact file bytes are
pinned, so owner edits require a deliberate config hash update. PE command-line
comparison tolerates only one terminal LF and one following encoding NUL. All
other bytes, argument ordering and duplicates remain significant: arguments are
never sorted or reduced to a set. During bootstrap, the installer compares the
boot-tested and running command lines as ordered token sequences, preserving
duplicates and excluding only the live bootloader-added `BOOT_IMAGE` token.
Certificates are pinned in the same manner. The updater does not infer either
value from `/proc/cmdline`. Duplicate JSON keys and unknown schema keys fail closed.

Shared installer interfaces (safe to import; import performs no updates):

* `file_sha256(path) -> str`: streaming lowercase SHA-256.
* `module_tree_manifest(path) -> dict`: path must be an absolute trusted module
  directory whose basename is the kernel release. Mapping from relative POSIX
  paths to `{"type":"file","sha256":str,"size":int,"mode":int}` or
  `{"type":"symlink","target":str}`. `mode` is `stat.S_IMODE`, not a string.
   Runtime directories are validated but not recorded. Top-level `build` and
   `source` **directories and symlinks** are excluded from both the manifest and
   recovery copy. These entries must be root owned; real directories must not be
   group/other writable. Other entry types at these names are rejected. Excluded
   directories are pruned without inspecting their header contents (including
   Arch's GDB and dt-bindings links). Nested names such as `kernel/build` remain
   runtime content and are validated and copied. All runtime links must stay inside the same runtime module
  tree; absolute `/usr/lib/modules/<same-release>/...` links are allowed and
  inventoried without following them. Symlinks into the excluded headers fail.
  Store this mapping directly as JSON, with no wrapper object.
* `verify_recovery(config) -> None`: validate the complete version-1 schema,
  frozen UKI hash and exact backup inventory; raise `UpdateError` on a mismatch.
  It does not restore modules or sign anything.

## Running and package integration

```sh
sudo /usr/bin/python3 -I /usr/local/libexec/dotfiles-boot-artifacts.py --check
sudo /usr/bin/python3 -I /usr/local/libexec/dotfiles-boot-artifacts.py
```

`--config /absolute/trusted/config.json` selects an explicit configuration; the
default is `/etc/dotfiles-secure-boot/config.json`. `--check` checks prerequisites,
recovery, kernel selection and space; it creates a private report but does not
build, sign, or publish. It is not a substitute for a successful full build.
**Do not proceed with package updates until this helper passes preflight and a
full initial update on the target machine.**

The hook's installed `zzz-` name orders it after `zz-sbctl`. It covers the stock
mkinitcpio path triggers, both kernels, systemd/stub/loader, mkinitcpio, ukify and
sbctl installation, upgrades and removals. A missing kernel aborts; no managed
artifact is deleted in response to kernel removal. Owner edits are not package
transactions: manually run the updater after initramfs configuration, hooks,
included files, or command-line changes. Preserve the usual image-only GRUB
presets, rather than adding live UKI output paths to them. Changes outside the
reviewed build policy below fail before publication and require an explicit owner
review and helper-policy update, not merely another invocation or hash refresh.

### Reviewed initramfs and preset policy

Every run, including `--check`, requires this effective global configuration:

```sh
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole plymouth block sd-encrypt lvm2 filesystems fsck)
```

The hook list and its order are exact. Additional modules, binaries, files,
compression settings or shell logic are not silently accepted. Configuration is
parsed as literal data, never sourced by Python or by a shell invoked just to
inspect it. Comments, ordinary quoting and multiline literal arrays are accepted;
expansions, append assignments and duplicate assignments fail. The global config,
drop-ins, selected build/runtime hooks and hook search directories must be trusted
root-owned paths. `*.conf` drop-ins may contain comments only; active drop-ins
require owner review. Inputs are fingerprinted and checked again before publish.

Exactly `linux.preset` and `linux-lts.preset` are supported. Each may contain only
the following active assignments (substitute `linux-lts` for `linux` as needed):

```sh
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_image="/boot/initramfs-linux.img"
```

Comments are allowed. Active `ALL_config`, `default_config`, `default_options`,
UKI paths, fallback definitions, alternate kernel paths or other overrides fail
rather than being ignored by the updater's explicit non-preset build. These
checks preserve the current GRUB image presets; they never rewrite them.

After **each** build, `lsinitcpio --config` must yield the same reviewed policy.
The updater does not use `lsinitcpio --analyze`, which sources embedded config.
Archive listings must contain systemd, cryptsetup and its generator, LVM,
Plymouth/script support, the ashborn descriptor/script/PNG assets, and module
metadata for only the exact selected kernel release. Btrfs must either be present
as `usr/lib/modules/<release>/kernel/fs/btrfs/btrfs.ko` (optionally compressed
with zst, xz, or gz), or built into that exact installed kernel. Built-in evidence
requires the exact line `kernel/fs/btrfs/btrfs.ko` in its trusted, kernel-package-owned
`modules.builtin`, with the release selected through package ownership and
`pkgbase`. Missing, malformed, unowned, or different-release evidence fails;
the running kernel's `/proc/config` is not consulted. Both
early and main archives are inspected because already-compressed modules may be
stored early. Early x86 microcode must be present separately. UKI `.uname` is
also checked against that exact release. These checks run before signing or
publishing that candidate; preflight alone cannot prove built archive contents.

Kernel selection uses each installed package's `pacman -Ql` inventory, its owned
`/usr/lib/modules/<release>/pkgbase`, and owned `vmlinuz`. Exactly one candidate
per package is required; an unowned restored old module tree is ignored. Package
version `linux 7.2.8.arch1-2` corresponds to release `7.2.8-arch1-2`; `linux-lts
6.18.54-2` corresponds to `6.18.54-2-lts`. Future releases are discovered from
package ownership, never `uname`, which may still describe the previous boot.

## Build, verification and publication

1. Acquire `/run/dotfiles-secure-boot.lock` using no-follow open, lstat/fstat
   ownership/type checks and nonblocking `flock`. No concurrent updater proceeds.
2. Check recovery, explicit hashes, service state, trusted paths and free space.
   Private staging requires at least 4 GiB, increasing with module and backup
   sizes. ESP preflight budgets at least 512 MiB for candidates plus 128 MiB reserve;
   publication checks actual candidate sizes plus that reserve again.
3. Build both releases with `mkinitcpio --nopost -k <exact-release> --kernelimage
   <package-kernel> --cmdline /etc/kernel/cmdline -g <private-initramfs> -U
   <private-UKI>`. Build scratch files also stay in private staging. An explicit
    private UKI config containing only the explicit, trusted
    `/usr/lib/systemd/boot/efi/linuxx64.efi.stub` prevents ambient ukify
    signing/config overrides. The stub's hash is rechecked before publication. Because
   mkinitcpio may normalize command-line whitespace, explicitly assemble the final
   unsigned UKI with ukify using the same initramfs, kernel and release, and the
   exact command-line file input.
4. Sign using `sbctl --config <private-config> sign --output <private-output>`.
   The config overrides `files_db` and `bundles_db` to private paths and explicitly
   uses the default file-backed keys; no `--save`, `sign-all`, or live database
   rewrite. Sign a private copy of the installed systemd-boot loader too.
5. Verify every signed image with `sbverify --cert <own-db.pem>`. A bounded stdlib
   PE parser checks x86-64 PE32+, section bounds and overlap. UKIs must contain the
    exact kernel, built initramfs, configured command-line bytes (apart from one
    terminal LF and encoding NUL), exact `.uname`, and nonempty `.osrel`. EFI
    subsystem, alignment, virtual section bounds/overlap and an entrypoint backed
    by executable section bytes are checked too. The signed loader must preserve
    the entire source executable structure and bytes, including all headers,
    section virtual addresses/permissions, raw padding and overlays. Only the
    checksum, security-directory entry, bounded trailing certificate table, and
    up to seven signing-alignment zero bytes may differ. `SizeOfHeaders` is not
    normalized or ignored.
6. Only after all pass, copy candidates to `/boot/.dotfiles-stage-*/` using `.tmp`
   filenames outside the selectable `EFI/Linux` directory. Hash-check and verify
   these copies too, fsync them, then rename each file into its fixed destination
    and fsync the destination directory. A private, fsynced `publication.jsonl`
    records originals, each replacement intent before rename, and each completed
    rename immediately. All three live hashes and the mount are rechecked before
    declaring the publication committed.

**This is three individual replacements, not a multi-file atomic transaction.**
A power loss, forced termination or filesystem failure may leave a mixed set.
Ordinary exceptions trigger reverse-order rollback from private originals, but
only where the live hash still equals the updater's newly written hash. An
independently changed output is never blindly overwritten. Rollback failure is
reported and private backups are retained. The frozen recovery UKI is never
replaced or deleted. A hook failure does **not** roll back the pacman transaction;
repair the problem and rerun the helper before rebooting.

Once all three files are durably published and final checks pass, publication is
**committed**. ESP temporary-directory cleanup, completion-journal, terminal or
final-report failures cannot trigger rollback or return a false update failure.
The helper returns success and emits a `PUBLISHED_COMPLETE` stderr warning for
cleanup/report issues when the terminal is available. Preserve the installed
helper/config integration and inspect the reported staging directory. Failures
before this commit point still fail the update and attempt hash-guarded rollback;
incomplete rollback remains an error requiring manual inspection.

## Reports and recovery

Every run retains `/var/lib/dotfiles-secure-boot/run-*/`: root-private command
logs, staged inputs/candidates, `previous-*.efi` backups when applicable,
`publication.jsonl`, and `result.txt` or `failure.txt` when reporting succeeds.
Completion is explicitly `PUBLISHED_COMPLETE`; failure reports use `NOT_COMMITTED`
and state whether rollback was incomplete. A missing completion record after a
crash or report failure requires inspection, not automatic rollback. Terminal output contains only status and the report
directory, not command arguments, command lines, UUIDs, certificates or tokens.
Logs and initramfs files may contain sensitive material: inspect only as root,
do not publish them, and manually prune reviewed old run directories to reclaim
space. The updater never prunes recovery or old reports automatically.

The frozen UKI is a kernel/initramfs recovery path, **not a full system rollback**.
It does not revert userspace, filesystem contents or package databases. After a
kernel upgrade, the old kernel may need its matching runtime modules after
switching to the real root. The backup is verified every run but never restored
automatically; unowned old module trees must not influence kernel selection.

For a deliberate recovery, from a trusted rescue environment with the installed
root mounted, verify `verify_recovery(config)` and the manifest first. If the
destination `/usr/lib/modules/6.18.54-2-lts` is absent, root may copy the verified
backup there preserving relative paths, modes and symlinks (for example `cp -a`
of the release directory). If the destination exists, inspect its package
ownership and inventory before any replacement; do not overlay it blindly. Do
not restore the excluded `build`/`source` header directories or links. Recheck the copied manifest
using `module_tree_manifest()` before using it. This manual restore is untracked
by pacman and may only provide limited post-root functionality; use a coherent
package/filesystem rollback or reinstall for broader recovery.

## Local tests

Non-root PE, inventory, build-policy, ownership-selection, end-to-end mocked
build/sign failure, and publication/cleanup-failure
tests live in the separate validation workspace, in `tests/test_boot_artifacts.py`.
That workspace is not bundled here; a fresh clone alone cannot run these tests.
Set `DOTFILES_VALIDATION` to its actual location:

```sh
python3 -B -m unittest discover \
  -s "${DOTFILES_VALIDATION:?Set the external validation workspace}/tests" \
  -p test_boot_artifacts.py -v
```

Set `BOOT_ARTIFACTS_FETCH_FIXTURES=1` on that command to additionally GET the real
public unsigned/signed PE fixtures from `Foxboron/go-uefi`. Both fixtures are
pinned by Git blob hashes in the test; they are parsed in temporary storage and
never executed. The default suite needs no network. No test executes signing,
package management, mounts or firmware tools. Target-machine preflight, actual
signing and boot validation remain necessary.

## Guarded lockdown-integrity migration

`lockdown.py` implements the owner-approved addition of `lockdown=integrity` to
the **regular and LTS signed UKIs** using the existing installed updater. The
reviewed updater SHA-256 is
`3a650618de234eb3541ac4a5e0954f34ce00c5398ded6cf13d8a9d3a941caadd`.
Historical provisioning reports are under
`/var/lib/dotfiles-secure-boot/install-*`; retain the accepted report path privately.
Previous success is not proof of current state. This migration validates live
state afresh and is not intended to be rerun after lockdown and recovery promotion
are complete.

### Temporary recovery security exception during this migration

When `lockdown.py` is first applied, the frozen recovery UKI and matching module
backup remain unchanged, retaining the original command line **without lockdown** as
the approved rollback boot path. Booting that recovery can allow weaker
post-boot hardening. This is **not a uniform lockdown policy across all boot
paths**, nor proof of full Secure Boot policy enforcement. GRUB and any other
boot paths are outside this migration's coverage. After successful regular and
LTS boot tests, the owner can separately approve a hardened replacement recovery;
this migration does not make that replacement.

### Guarded promotion of the tested LTS recovery

`promote_recovery.py` implements that separate, owner-approved promotion for
`6.18.54-2-lts`. After the owner confirms the LTS boot and normal Wi-Fi, audio,
touchpad, unlock and login, independently hash the current
`/boot/EFI/Linux/arch-linux-lts.efi`. Review and stage the promotion script using
the root-private staging procedure below, independently verifying its bytes.
Keep package transactions and privileged boot/config writers idle. Run the
staged copy with these explicit pins (placeholders require reviewed values):

```sh
sudo /usr/bin/python3 -I /root/recovery-reviewed/promote_recovery.py \
  --script-sha256 <reviewed-staged-script-sha256> \
  --expected-installed-helper-sha256 3a650618de234eb3541ac4a5e0954f34ce00c5398ded6cf13d8a9d3a941caadd \
  --expected-recovery-sha256 929c94b5c65e3dfa1a4144bc3e66cb49f9bed2cbd7e449629306d10deee62ae1 \
  --expected-lts-sha256 <owner-reviewed-current-LTS-EFI-sha256>
```

The script requires the exact running/package-owned frozen LTS release,
SecureBoot=1, SetupMode=0, active `[integrity]` lockdown, the approved current UKI
path from `bootctl --print-stub-path`, and ordered running command-line agreement.
It verifies the pinned certificate, both image signatures, embedded kernel and
policy, and equality of live and backed-up runtime modules using the existing
header-exclusion policy. All meaningful old/new PE sections except command line
and regenerated initramfs must agree. Trusted 0755 parent directories and normal
non-writable ESP mount masks are accepted; config must be 0600 and staging private.

Under the updater lock throughout, it archives the old image and exact config in
`/var/lib/dotfiles-secure-boot/recovery-promotion-*/`, off the ESP. It copies the
already signed LTS bytes without rebuilding or re-signing, stages a non-`.efi`
temporary directly under `/boot`, and replaces the **same recovery filename**.
Only the exact `recovery.sha256` JSON value changes; all other config bytes and
the matching module backup/manifest are preserved and checked again. Space guards
reserve 128 MiB on the ESP and 500 MiB in private storage. The helper is called
directly for verification, never launched as a locking subprocess.

Publication is image then config: between the two atomic renames, recovery's hash
does not match config, so the updater refuses. Ordinary failures attempt image
then config rollback only when the written hash and file identity still match;
independent changes are retained. Private journals contain identities, hashes,
module counts and failure tracebacks. Power loss/forced termination can leave a
hash mismatch requiring inspection of those archives; this is not a multi-file
atomic transaction. No reboot, key, firmware, boot-order or service change occurs.

**The recovery lockdown exception is resolved only after actual successful
execution and `PROMOTED_COMPLETE` verification, not by adding this script.**
The archived weaker image is root-private and not boot-listed. Historical private
backups and unrelated EFI entries are not removed. A subsequent owner-controlled
recovery boot test remains distinct from file verification.

Non-root synthetic-PE and fault-injection tests (no signing or host commands):

```sh
python3 -B -m unittest discover \
  -s "${DOTFILES_VALIDATION:?Set the external validation workspace}/tests" \
  -p test_secure_boot_recovery.py -v
```

### Owner-staged execution and guards

Review the script, compute its SHA-256 independently, and copy those exact bytes
into a fresh root:root **0700 directory**, with the staged script root:root
**0600**. All ancestors must be root-owned, without non-root writers or symlinks.
Do not execute a root process directly from a user-writable checkout. Independently
verify the staged bytes against the reviewed hash before execution: the script's
self-check cannot establish trust in code that has already started executing.
The installed helper is root:root, non-writable by other users (0644 is supported);
the state directory, config directory, config and command-line files must be
root-private. Obtain the old command-line SHA-256 from the reviewed live file and
confirm it agrees with the preservation config. Do not expose its contents.

Illustrative command after that manual staging (replace placeholders with the
reviewed lowercase SHA-256 values):

```sh
sudo /usr/bin/python3 -I /root/lockdown-reviewed/lockdown.py \
  --script-sha256 <reviewed-staged-script-sha256> \
  --expected-installed-helper-sha256 3a650618de234eb3541ac4a5e0954f34ce00c5398ded6cf13d8a9d3a941caadd \
  --old-cmdline-sha256 <reviewed-old-cmdline-file-sha256>
```

The helper version pin is mandatory and must also equal the script's reviewed
version constant. Imports compile only the hash-verified helper bytes, bypassing
`sys.path` and bytecode caches. Unknown or duplicate config keys fail closed.
The only config-byte edit is the `cmdline_sha256` value; unusual escaped spelling
of that JSON key/value is refused rather than reserialized.

Before configuration writes, the migration requires:

* root with isolated Python, trusted paths and private files; SecureBoot=1 and
  SetupMode=0 from EFI variables; running release exactly `7.2.8-arch1-2`;
* the pinned old command line, matching ordered running tokens after removing at
  most one `BOOT_IMAGE` token, plus matching regular/LTS/recovery UKI command lines;
* no existing `lockdown` argument, quoting, escaping, or `--` separator. Exactly
  one existing `lockdown=integrity` yields a **read-only refusal**, exit 1, with
  nothing applied or rebuilt. Runtime-only integrity is not silently ignored;
* the original recovery hash and module inventory, trusted signing hierarchy,
  pinned db certificate, verified original signatures and loader executable;
* a successful installed updater `--check`, including build policy, service,
  kernel selection, signing prerequisites and remaining staging/ESP space.

The old command line's exact bytes, whitespace, duplicates and token order are
preserved, removing only an optional terminal LF before appending
` lockdown=integrity` and exactly one LF. Root-device arguments cannot be changed
by this operation. The migration acquires a separate advisory migration lock and
checks for pacman's database lock. It holds the updater's advisory lock while
checking/backing up/changing state, releases it for each helper subprocess, and
reacquires it for verification or restoration. **Keep package updates and all
other privileged boot/config writers idle throughout.** These locks are not a
pacman transaction lock, and subprocess handoffs cannot exclude another writer.
An occupied updater lock causes refusal, never lock stealing or waiting deadlock.

### Backups, publication and failure handling

Every attempted migration after initial read-only validation creates a fresh
root-private `/var/lib/dotfiles-secure-boot/lockdown-*` report directory. It retains
fsynced exact backups: `original-0` config, `original-1` command line,
`original-2` regular UKI, `original-3` LTS UKI, `original-4` signed loader,
`original-5` loader.conf, and `original-6` recovery module manifest. The journal
records original hashes. Command output and exception details stay in this
private directory; terminal messages contain no command lines, UUIDs, command
arguments or key contents. No signing keys are backed up here.

The command line and config are each replaced atomically and fsynced. Between
those two renames the old checksum rejects the new command line; the migration
does not invoke the updater until both files and their checksum agree. It then
runs `/usr/bin/python3 -I /usr/local/libexec/dotfiles-boot-artifacts.py` with private
output capture. The updater rebuilds, signs and verifies both UKIs and the loader.
Success additionally requires both published `.cmdline` payloads to match the
exact new policy, signatures to verify, the live config/checksum and recovery to
remain valid, and loader.conf plus the recovery manifest to remain unchanged.
The signed loader's executable must match its original; signature bytes may
legitimately change when the helper signs it again.

On ordinary exceptions, restoration attempts affect **only config and command
line**, and only files still matching this migration's written bytes, inode and
ownership/mode. Other writers' changes are not overwritten. The updater handles
its own publication rollback, but a late failure can leave newly published or
mixed boot artifacts even if configuration restoration succeeds. The migration
compares live boot-file hashes to its backups and records
`configuration_restored` and `artifacts_match_original` separately in the private
failure journal. Unknown state is not reported as restored. **Owner inspection
is required on failure**: inspect both migration and updater `run-*` reports and
publication journals before repair or reboot. The migration never automatically
overwrites boot artifacts from backups or claims full rollback.

Forced termination, power loss, storage errors and concurrent privileged writers
remain outside ordinary-exception restoration guarantees. Separate file renames
are not a multi-file atomic transaction; reporting itself can fail. Successful
artifact verification is not a boot test or a security guarantee. After an
owner-controlled reboot, validate the regular kernel's actual lockdown state,
then separately test LTS and recovery availability. This script does not reboot,
write firmware variables, toggle the running kernel's lockdown sysfs state,
change services or enroll keys.

Non-root fault-injection tests (no signing/package/firmware commands execute):

```sh
python3 -B -m unittest discover \
  -s "${DOTFILES_VALIDATION:?Set the external validation workspace}/tests" \
  -p test_secure_boot_lockdown.py -v
```
