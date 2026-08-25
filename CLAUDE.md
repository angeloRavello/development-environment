# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A dotfiles + machine-bootstrap repo managed with [rotz](https://volllly.github.io/rotz/docs/getting-started). One command sets up a brand new Windows 11 or Ubuntu/Linux machine with a fixed set of dev tools, without ever requiring an administrator/root account.

There is no build, lint, or test suite — this is configuration, not application code. "Testing" a change means running the relevant bootstrap script (or a single dot's `install.ps1`) on a real or scratch machine/VM and confirming the tool installs and configs get linked.

## Single-language architecture: pwsh7 everywhere, except the prerequisite step

Every script in this repo past the very first step is PowerShell 7 (`pwsh`), and runs unmodified on both Windows and Linux — there is no more `install.ps1`/`install.sh` pair per tool. This repo used to duplicate every fix across two shell dialects (a real problem: a timeout fix landed in one and had to be manually ported to the other); pwsh7 was chosen over introducing a new language (e.g. Python) because it already runs natively on Linux and this repo was already installing it as a tool.

The one place this doesn't apply: `bootstrap/prereq.ps1` (Windows, runs under the stock PowerShell 5.1 that ships with the OS) and `bootstrap/prereq.sh` (Linux, plain bash). Their only job is installing pwsh7 itself (portable, no admin/sudo) before anything else can run — since nothing else is guaranteed to exist on a truly fresh machine. This is the one deliberately duplicated block in the repo; both files are self-contained (they do **not** dot-source `common.ps1`, since that file uses `$IsWindows`/`$IsLinux`, which only exist under pwsh7, not Windows PowerShell 5.1). Once pwsh7 is present, the prereq script hands off to `bootstrap/bootstrap.ps1` and never runs again.

`bootstrap.ps1` itself starts with `#Requires -Version 7.0` and an explicit version check that throws a clear error if somehow invoked under 5.1 directly — always go through `prereq.ps1`/`prereq.sh`.

## Repo layout: rotz "dots"

Each top-level folder (`git`, `mise`, `python`, `java`, `rust`, `zig`, `yazi`, `neovim`, `wezterm`) is a rotz "dot": a `dot.yaml` describing how to install the tool (`installs`) and where its config files get deployed (`links` - copied into place by `Sync-DotLinks`, not symlinked by rotz - see below), plus the actual config files for that tool. Full schema: rotz's [config reference](https://volllly.github.io/rotz/docs/configuration). `powershell7` is **not** a dot anymore — see above, it's handled by the prereq step before rotz exists.

`dot.yaml` schema rules learned by testing against the real `rotz` binary (not obvious from the docs):
- You can't mix a bare top-level `links`/`installs`/`depends` with the OS-scoped `global`/`windows`/`linux` keys in the same file — it's one schema or the other. This repo no longer needs the OS-scoped keys at all, since every `installs:` is now a single `pwsh -NoProfile -File "{{ env.DOTFILES }}/<tool>/install.ps1"` command that works unmodified on both OSes — every `dot.yaml` uses the flat top-level schema.
- `depends` entries are paths from the repo root (e.g. `/mise`), not tool names.
- `{{ env.DOTFILES }}` is how `installs` commands find their own helper scripts without depending on the current working directory.

## Bootstrap flow

1. **`bootstrap/prereq.ps1`/`prereq.sh`** — installs pwsh7 if missing, then hands off to `bootstrap.ps1` running under pwsh7.
2. **`bootstrap/bootstrap.ps1`** (pwsh7, both OSes):
   1. Resolves this repo's path and persists it as `$env:DOTFILES` (so plain `rotz install` keeps working in later sessions) via `Set-UserEnvVar`.
   2. On Windows only: sets `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_CACHE_HOME`/`XDG_STATE_HOME` under `%USERPROFILE%` so tools resolve config the same way Linux does by default.
   3. Installs `mise` (portable, user-scoped) via `mise/install.ps1`.
   4. Installs `rotz` itself through mise's generic GitHub backend (`mise use --global github:volllly/rotz`) — rotz has no mise registry entry but does publish standard target-triple release zips.
   5. Runs `rotz install --continue-on-error` (executes every dot's install command - this is also what clones LazyVim for the neovim dot).
   6. Deploys every dot.yaml's `links:` via `Sync-DotLinks` (see below) — always *after* `rotz install`, since dots like `neovim` depend on their clone step existing before this repo's own overrides get copied on top.

Every stage prints `==> [stage] ...` plus the key values involved (resolved paths, download URLs, versions) specifically so a hang or failure can be pinpointed from console output alone — this was added after the previous two-dialect scripts hung silently with no indication of where.

`bootstrap/common.ps1` holds shared helpers (`Get-BootstrapPaths`, `Get-LatestGithubAsset`, `Install-PortableZip`, `Install-PortableTarGz`, `Add-UserPath`, `Set-UserEnvVar`, `Invoke-ExternalCommand`, `Get-DotLinks`, `Test-DotLinkUpToDate`, `Sync-DotLinks`) used by `bootstrap.ps1` and every per-tool `install.ps1`. `Add-UserPath`/`Set-UserEnvVar` branch internally on `$IsWindows` (registry `HKCU\Environment`) vs. Linux (`~/.profile`/`~/.bashrc`, idempotent append).

## Where downloads and installs land: `bootstrap/paths.env`

Single source of truth for two paths, read by `Get-BootstrapPaths`, plain `KEY=value` text (not YAML/PSD1):
```
DOWNLOADS_DIR=.local/downloads   # raw downloaded archives - kept, not deleted, after extraction (cache by filename)
INSTALL_DIR=.local/opt           # extracted tools, one subfolder per tool: <INSTALL_DIR>/git, /wezterm, /mise, /pwsh7
```
Each key is either relative to `$HOME`/`%USERPROFILE%` (joined at runtime, as above) or an **absolute path** (e.g. `DOWNLOADS_DIR=D:\tools\download`), resolved by `Resolve-ConfiguredPath` in `common.ps1`. `Install-PortableZip`/`Install-PortableTarGz` take `-DownloadsDir` and `-DestDir` params derived from this — no script hardcodes `.local/opt/<tool>` or a temp path anymore. Every install script resolves its executable dynamically from inside its own `INSTALL_DIR` subfolder (via `Get-ChildItem -Recurse` for the binary name) rather than assuming an exact archive layout, since flattening/nesting varies per tool's zip.

**Absolute paths are OS-specific** — a Windows drive-letter path means nothing on Linux and vice versa, so a bare key can be overridden per OS with a `_WINDOWS`/`_LINUX` suffixed key (e.g. `DOWNLOADS_DIR_LINUX=/opt/tools/download`), checked first and falling back to the bare key. `Resolve-ConfiguredPath` (common.ps1), and the equivalent `Resolve-ConfiguredPathWindows` (prereq.ps1) / `resolve_configured_path` (prereq.sh) functions, detect whether a resolved value is absolute-for-the-current-OS, absolute-but-shaped-for-the-other-OS (throws a clear error naming the suffixed key to add instead of silently mangling the path), or relative (joined with home). **Bash gotcha found and fixed while building this**: an unquoted `\\` in a `case` glob pattern matches two literal backslashes, not one — matching a single-backslash Windows path like `D:\tools\download` requires a quoted `'\'` in the pattern (`[A-Za-z]:'\'*`), not `\\`.

This file has to be plain text, not a PowerShell data file, because `prereq.ps1` (Windows PowerShell 5.1) and `prereq.sh` (bash) both parse it by hand — they run *before* pwsh7/`common.ps1` exist, so they can't use `Get-BootstrapPaths`. If you add a new config key, update the parser in all three places: `Get-BootstrapPaths` in `common.ps1`, the regex loop in `prereq.ps1`, and the `grep`/`cut` lines in `prereq.sh`.

Two exceptions to `INSTALL_DIR`, both called out in comments at their call sites: mise on Linux is installed by mise's own official installer (`curl https://mise.run | sh`), which picks `~/.local/bin/mise` on its own; and mise's *internal* data (installed toolchains, shims) lives under `~/.local/share/mise/...` — mise's own convention, unrelated to this repo's `INSTALL_DIR`.

Because mise's own binary no longer lives at a fixed path (Windows: wherever it lands under `<INSTALL_DIR>/mise`, dynamically discovered), `bootstrap.ps1` resolves `$miseExe` via `Get-Command mise` after `mise/install.ps1` runs (which already added the right folder to the current session's PATH) instead of hardcoding a second guess that could drift out of sync.

## Dotfiles are deployed by copying, not by `rotz link` — do not reintroduce symlinking

`bootstrap.ps1` never calls `rotz link`. Stage 5/5 (last stage) calls `Sync-DotLinks -RepoRoot $RepoRoot -BackupDir $paths.BackupDir` instead (paths from `Get-BootstrapPaths`, `BACKUP_DIR` in `paths.env`, default `~/.local/backup`).

**Why, precisely — confirmed by reading rotz's own source (`src/config.rs`, `src/commands/link.rs`), not assumed:** rotz's `LinkType` enum has exactly two variants, `Symbolic` and `Hard` — no copy mode exists in rotz at all. Neither variant is safe to assume available on this repo's target machines:
- `Symbolic` needs `SeCreateSymbolicLinkPrivilege`, granted by Windows Developer Mode — which itself needs an admin session to enable. `New-Item -ItemType SymbolicLink` was confirmed failing with "Administrator privilege required for this operation" on a real machine without it.
- `Hard` uses real hard links for files and NTFS junctions for directories on Windows (per rotz's source). Junctions cross drives fine with no admin (confirmed: `New-Item -ItemType Junction` from `D:\...` to `C:\Users\...` succeeded). Hard links for **files** do not: confirmed failing with "The system cannot move the file to a different disk drive" the moment source and target are on different volumes — completely normal here, since the dotfiles repo living on a different drive than `%USERPROFILE%` is an ordinary setup this repo has to support, not an edge case.

Copying avoids both failure modes (no admin, works across drives) at a real cost: **no live sync**. A symlink means an edit to a tracked file in this repo is immediately visible at the deployed path; a copy is a snapshot from whenever `Sync-DotLinks` last ran, and needs a re-run to pick up further edits. **Do not "fix" this by switching back to `rotz link` or `link_type: Hard`** without re-solving the admin/cross-drive problem first — that's the whole reason this mechanism exists.

`Sync-DotLinks` (in `common.ps1`) drives itself off the repo's own `dot.yaml` files rather than a separately maintained list, via two other functions also in `common.ps1`:
- `Get-DotLinks` extracts every `links:` entry as a `{ Source, Target }` pair (Source resolved to an absolute path under the dot's own folder; Target left with `~` unexpanded) by tracking indentation relative to wherever `links:` itself appears. **This is a narrow parser scoped to the exact shape this repo's `links:` blocks use, not a general YAML parser** — no lists, no quoting, flat `key: value` lines only. If a `links:` block ever needs something fancier, this parser needs updating too.
- `Test-DotLinkUpToDate` compares Source and (resolved) Target by content hash — a single file hash for file links, a full recursive per-file hash comparison for directory links (e.g. neovim's `config/lua/config`) — to decide whether a link needs redeploying at all.

For each link, `Sync-DotLinks` has three outcomes: if Target **doesn't exist**, it copies with nothing to back up; if Target **already matches Source** (`Test-DotLinkUpToDate`), it skips entirely — this is what keeps re-running the bootstrap on an unchanged repo cheap and quiet instead of re-backing-up and re-copying everything on every single run; if Target **exists and differs**, it `Move-Item`s it to `<BackupDir>/<timestamp>/<same relative path under home>` first, then `Copy-Item -Recurse -Force`s Source over the now-clear path. Verified with an isolated fixture covering all of: new file (plain copy), differing pre-existing file (backup then copy, content of both verified), a nested directory tree (mirrors neovim's shape), unchanged re-run (zero new backups), and a changed repo source on a second run (the previously-deployed version gets backed up before the new one lands).

`config.yaml`'s `link_type: Symbolic` is no longer read by this repo's bootstrap flow at all — left in place only for documentation/anyone running `rotz link` by hand.

## yazi's `y` shell wrapper

`yazi/install.ps1` does `mise use --global yazi` *and* installs the official [`y` shell wrapper function](https://yazi-rs.github.io/docs/quick-start#shell-wrapper) into your shell profile — Windows: pwsh7's `$PROFILE` (not Windows PowerShell 5.1's, a different file — this repo assumes pwsh7 is the day-to-day shell); Linux: `~/.bashrc`. Plain `yazi` only affects its own process (quitting always returns you to wherever you started); `y` reads back the directory you navigated to (via `--cwd-file`) and `cd`s your actual shell there.

The write is idempotent via a local `Set-ManagedBlock` helper (defined inline in `yazi/install.ps1`, not `common.ps1` — this pattern is only used once so far): the function body is wrapped in `# >>> yazi shell wrapper ... >>>` / `# <<< ... <<<` marker comments, and if those markers are already present in the profile, everything between them is replaced in place rather than appended again — so editing the wrapper's definition in `yazi/install.ps1` and re-running the bootstrap updates it in the profile too, without duplicating it or touching anything else already in that profile.

## WezTerm is pinned to nightly — the one tool-specific exception

Every other portable tool in this repo installs the latest stable release. `wezterm/install.ps1` deliberately always installs the **nightly** build instead, on both OSes — this is scoped to wezterm only, not a general pattern.

Two `common.ps1` helpers gained optional params for exactly this, unused by every other call site (`git`, `mise`):
- `Get-LatestGithubAsset -Tag "nightly"` fetches `/releases/tags/nightly` instead of `/releases/latest` — required because WezTerm's nightly is marked `"prerelease": true`, which `/releases/latest` always excludes.
- `Install-PortableZip -Force` always re-downloads even if a same-named file is already cached in `DownloadsDir` — required because WezTerm's nightly assets (`WezTerm-windows-nightly.zip`) keep the same filename forever while the actual contents change on every build, which would otherwise make the filename-based download cache stick to whatever nightly build was fetched first.

Consequently `wezterm/install.ps1` also never short-circuits on "already installed" like every other install script does — it always re-checks/re-downloads/re-extracts on every bootstrap run. On Linux there's no apt-repo branch at all anymore (even with sudo): WezTerm's apt repo only ships stable builds, so it's dropped entirely in favor of always using the nightly AppImage (pinned to the `Ubuntu20.04` build for broad forward-compatibility — older-glibc AppImages generally still run on newer distros).

## Every network call has a timeout — this is load-bearing

Every `Invoke-WebRequest`/`Invoke-RestMethod` call passes an explicit `-TimeoutSec`. The one place a native subprocess could hang forever — Git for Windows' self-extracting `.7z.exe` — is guarded with `Start-Process -PassThru` + `$proc.WaitForExit(<ms>)`, force-killed via `Stop-Process` if it doesn't finish in time. This exists because the bootstrap used to hang indefinitely on a stalled connection (offline, corporate proxy, firewall) with zero error output. **Any new download added to this repo must follow the same pattern** — an un-timed-out `Invoke-WebRequest` or subprocess call is exactly the bug class this rewrite fixed.

## Core invariant: no hardcoded paths, no admin/sudo

Every install path in this repo is derived from `$env:USERPROFILE`/`$HOME`, never a hardcoded drive letter or absolute path, so it behaves the same whether Windows puts user profiles on `C:` or `D:`:
- Portable tool downloads/installs: `DOWNLOADS_DIR`/`INSTALL_DIR` from `bootstrap/paths.env` (see above) — defaults to `~/.local/downloads` and `~/.local/opt/<tool>`
- mise's own data: `~/.local/share/mise`, `~/.local/bin` (Linux mise binary only) — mise's own convention, not ours
- Config files: `~/.config/<tool>/...` on both OSes

PATH changes on Windows go to the **user** registry hive (`HKCU\Environment`) only, never machine-wide PATH. Any new install script must preserve this — no admin/sudo dependency anywhere it's technically avoidable.

`git` and `wezterm` are fetched directly from GitHub Releases as portable zips/AppImage/self-extracting archives (verified against `github.com/jdx/mise/registry/*.toml` to confirm they aren't in mise's registry) rather than via mise, with `$IsWindows`/`$IsLinux` branches inside a single `install.ps1` for the OS-specific download logic (`git` still has an apt branch on Linux; `wezterm` does not — see above). `python`/`rust`/`zig` install via a plain `mise use --global <tool>` one-liner directly in `dot.yaml` (no install script needed — genuinely OS-agnostic, nothing else to do). `neovim` and `yazi` both need a dedicated `install.ps1` despite being mise-installed tools, because each has one extra piece of setup beyond the mise install itself: `neovim` clones LazyVim on first run (see below), `yazi` adds the `y` shell wrapper to your profile (see below). `java` is the other exception: it needs multiple JDK versions side-by-side (see below), so it follows the dedicated-script pattern instead of a one-liner.

### Java: multiple JDKs side-by-side

`java/install.ps1` installs Eclipse Temurin 8, 11, 17, 21, and 25 via `mise install java@temurin-<N>` (each call is a no-op if that version is already present — this is what makes reruns idempotent, not a hand-rolled existence check), then runs `mise use --global java@temurin-25` last so 25 is what `java`/`javac` resolve to with no extra config. The other four stay installed on disk under mise's install dir and are available to any project that pins a different version in its own `mise.toml`/`.tool-versions`, without re-downloading. Temurin specifically, not mise's generic `openjdk-<N>` shorthand — confirmed via `mise ls-remote java`/`mise latest java@temurin-<N>` that all five short-form version strings (`temurin-8`, `temurin-11`, `temurin-17`, `temurin-21`, `temurin-25`) resolve to a real patch release before switching to this. If the set of versions or the default ever changes, edit the `$versions`/`$default` variables at the top of the script.

## Adding a new tool whose config comes from a git repo

Pattern already used by `neovim/install.ps1` for cloning LazyVim — generalize this for anything you'd rather clone than hand-author:

1. Create `<tool>/dot.yaml` with `installs: pwsh -NoProfile -File "{{ env.DOTFILES }}/<tool>/install.ps1"`.
2. In that script: install the binary (mise if registered, otherwise a portable download like `git`/`wezterm`, with `$IsWindows`/`$IsLinux` branches only where the OSes genuinely differ), then `git clone` the config repo into its real target location **only if it isn't already there** — idempotency, never clobber a working setup on re-runs.
3. To layer your own overrides on top of the cloned repo (as this repo does with `neovim/config/lua/config` and `lua/plugins`), add a `links` section in `dot.yaml` for just those subfolders/files — `Sync-DotLinks` always runs after `rotz install` for exactly this reason, so the clone exists before the overrides get copied on top.

## Gotchas

- **Never commit a tracked `mise/config.toml` at the repo root.** `mise` recognizes `mise/config.toml` (relative to cwd) as one of its own local-project config file names, so a repo-tracked one makes every `mise` invocation from inside this repo prompt to "trust" and load it as a project config. It was removed for this reason. Tool versions are pinned instead by each dot running `mise use --global <tool>`, which writes straight to mise's real global config (`~/.config/mise/config.toml`) — no repo-tracked mise config needed.
- `git/gitconfig` ships without `user.name`/`user.email` — these must be set per-machine (`git config --global user.name "..."`) or by editing the linked file directly, not baked into the repo.
- `config.yaml` at the repo root is rotz's own default config (`link_type: Symbolic`); it's mostly documentation — `bootstrap.ps1` always passes `--dotfiles` explicitly to rotz, and never calls `rotz link` at all (see "Dotfiles are deployed by copying" above), so `link_type` only matters if you run `rotz link` by hand.
- `mise/install.ps1` shells out to `bash -c "curl ... | sh"` on Linux for mise's own official installer — this is the one intentional exception to "everything is pwsh", since it's the vendor-documented install method, not custom logic worth reimplementing.
