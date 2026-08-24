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

Each top-level folder (`git`, `mise`, `python`, `java`, `rust`, `zig`, `yazi`, `neovim`, `wezterm`) is a rotz "dot": a `dot.yaml` describing how to install the tool (`installs`) and where its config files get symlinked (`links`), plus the actual config files for that tool. Full schema: rotz's [config reference](https://volllly.github.io/rotz/docs/configuration). `powershell7` is **not** a dot anymore — see above, it's handled by the prereq step before rotz exists.

`dot.yaml` schema rules learned by testing against the real `rotz` binary (not obvious from the docs):
- You can't mix a bare top-level `links`/`installs`/`depends` with the OS-scoped `global`/`windows`/`linux` keys in the same file — it's one schema or the other. This repo no longer needs the OS-scoped keys at all, since every `installs:` is now a single `pwsh -NoProfile -File "{{ env.DOTFILES }}/<tool>/install.ps1"` command that works unmodified on both OSes — every `dot.yaml` uses the flat top-level schema.
- `depends` entries are paths from the repo root (e.g. `/mise`), not tool names.
- `{{ env.DOTFILES }}` is how `installs` commands find their own helper scripts without depending on the current working directory.

## Bootstrap flow

1. **`bootstrap/prereq.ps1`/`prereq.sh`** — installs pwsh7 if missing, then hands off to `bootstrap.ps1` running under pwsh7.
2. **`bootstrap/bootstrap.ps1`** (pwsh7, both OSes):
   1. Resolves this repo's path and persists it as `$env:DOTFILES` (so plain `rotz install`/`rotz link` keep working in later sessions) via `Set-UserEnvVar`.
   2. On Windows only: sets `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_CACHE_HOME`/`XDG_STATE_HOME` under `%USERPROFILE%` so tools resolve config the same way Linux does by default.
   3. Installs `mise` (portable, user-scoped) via `mise/install.ps1`.
   4. Installs `rotz` itself through mise's generic GitHub backend (`mise use --global github:volllly/rotz`) — rotz has no mise registry entry but does publish standard target-triple release zips.
   5. Runs `rotz install --continue-on-error` (executes every dot's install command), then `rotz link` (symlinks every dot's config files). Install always runs before link — dots like `neovim` depend on their clone step existing before overrides get linked on top.

Every stage prints `==> [stage] ...` plus the key values involved (resolved paths, download URLs, versions) specifically so a hang or failure can be pinpointed from console output alone — this was added after the previous two-dialect scripts hung silently with no indication of where.

`bootstrap/common.ps1` holds shared helpers (`Get-LatestGithubAsset`, `Install-PortableZip`, `Install-PortableTarGz`, `Add-UserPath`, `Set-UserEnvVar`) used by `bootstrap.ps1` and every per-tool `install.ps1`. `Add-UserPath`/`Set-UserEnvVar` branch internally on `$IsWindows` (registry `HKCU\Environment`) vs. Linux (`~/.profile`/`~/.bashrc`, idempotent append).

## Every network call has a timeout — this is load-bearing

Every `Invoke-WebRequest`/`Invoke-RestMethod` call passes an explicit `-TimeoutSec`. The one place a native subprocess could hang forever — Git for Windows' self-extracting `.7z.exe` — is guarded with `Start-Process -PassThru` + `$proc.WaitForExit(<ms>)`, force-killed via `Stop-Process` if it doesn't finish in time. This exists because the bootstrap used to hang indefinitely on a stalled connection (offline, corporate proxy, firewall) with zero error output. **Any new download added to this repo must follow the same pattern** — an un-timed-out `Invoke-WebRequest` or subprocess call is exactly the bug class this rewrite fixed.

## Core invariant: no hardcoded paths, no admin/sudo

Every install path in this repo is derived from `$env:USERPROFILE`/`$HOME`, never a hardcoded drive letter or absolute path, so it behaves the same whether Windows puts user profiles on `C:` or `D:`:
- Windows tools: `%USERPROFILE%\.local\bin`, `%USERPROFILE%\.local\opt\<tool>`
- Linux tools: `~/.local/bin`, `~/.local/share/mise`, `~/.local/opt/<tool>`
- Config files: `~/.config/<tool>/...` on both OSes

PATH changes on Windows go to the **user** registry hive (`HKCU\Environment`) only, never machine-wide PATH. Any new install script must preserve this — no admin/sudo dependency anywhere it's technically avoidable.

`git` and `wezterm` are fetched directly from GitHub Releases as portable zips/AppImage/self-extracting archives (verified against `github.com/jdx/mise/registry/*.toml` to confirm they aren't in mise's registry) rather than via mise, with `$IsWindows`/`$IsLinux` branches inside a single `install.ps1` for the OS-specific download/apt logic. `python`, `rust`, `zig`, `yazi`, `neovim` install via a plain `mise use --global <tool>` one-liner in `dot.yaml` (no install script needed — these were already OS-agnostic before this rewrite). `java` is the exception: it needs multiple JDK versions side-by-side (see below), so it follows the dedicated-script pattern instead of a one-liner.

### Java: multiple JDKs side-by-side

`java/install.ps1` installs OpenJDK 8, 11, 21, and 25 via `mise install java@openjdk-<N>` (each call is a no-op if that version is already present — this is what makes reruns idempotent, not a hand-rolled existence check), then runs `mise use --global java@openjdk-25` last so 25 is what `java`/`javac` resolve to with no extra config. The other three stay installed on disk under mise's install dir and are available to any project that pins a different version in its own `mise.toml`/`.tool-versions`, without re-downloading. If the set of versions or the default ever changes, edit the `$versions`/`$default` variables at the top of the script.

## Adding a new tool whose config comes from a git repo

Pattern already used by `neovim/install.ps1` for cloning LazyVim — generalize this for anything you'd rather clone than hand-author:

1. Create `<tool>/dot.yaml` with `installs: pwsh -NoProfile -File "{{ env.DOTFILES }}/<tool>/install.ps1"`.
2. In that script: install the binary (mise if registered, otherwise a portable download like `git`/`wezterm`, with `$IsWindows`/`$IsLinux` branches only where the OSes genuinely differ), then `git clone` the config repo into its real target location **only if it isn't already there** — idempotency, never clobber a working setup on re-runs.
3. To layer your own overrides on top of the cloned repo (as this repo does with `neovim/config/lua/config` and `lua/plugins`), add a `links` section in `dot.yaml` for just those subfolders/files, keyed after the install step so the clone exists first.

## Gotchas

- **Never commit a tracked `mise/config.toml` at the repo root.** `mise` recognizes `mise/config.toml` (relative to cwd) as one of its own local-project config file names, so a repo-tracked one makes every `mise` invocation from inside this repo prompt to "trust" and load it as a project config. It was removed for this reason. Tool versions are pinned instead by each dot running `mise use --global <tool>`, which writes straight to mise's real global config (`~/.config/mise/config.toml`) — no repo-tracked mise config needed.
- `git/gitconfig` ships without `user.name`/`user.email` — these must be set per-machine (`git config --global user.name "..."`) or by editing the linked file directly, not baked into the repo.
- `config.yaml` at the repo root is rotz's own default config (`link_type: Symbolic`); it's mostly documentation since `bootstrap.ps1` always passes `--dotfiles` explicitly to rotz.
- `mise/install.ps1` shells out to `bash -c "curl ... | sh"` on Linux for mise's own official installer — this is the one intentional exception to "everything is pwsh", since it's the vendor-documented install method, not custom logic worth reimplementing.
