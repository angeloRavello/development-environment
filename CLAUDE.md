# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A dotfiles + machine-bootstrap repo. One command sets up a brand new Windows 11 or Ubuntu/Linux machine with a fixed set of dev tools, without ever requiring an administrator/root account.

There is no build, lint, or test suite — this is configuration, not application code. "Testing" a change means running the relevant bootstrap script (or a single tool's `install.ps1`) on a real or scratch machine/VM and confirming the tool installs and configs get deployed. When you can't run a real bootstrap, at minimum parse-check every touched `.ps1` (`[System.Management.Automation.Language.Parser]::ParseFile`) and, where feasible, exercise the changed function against an isolated fixture (temp dir standing in for `$HOME`/the repo) rather than the real environment — this repo's history includes several bugs (a bash `case` backslash-escaping bug, a broken `--force` re-download flag) that were only caught by actually running the code, not by reading it.

## No external orchestration tool — this repo used to use rotz, and no longer does

Every script here is PowerShell 7 (`pwsh`), including the orchestration itself: `bootstrap/bootstrap.ps1` calls each tool's `install.ps1` directly, in a fixed, explicit, hardcoded order — there is no dependency-manifest file (no `dot.yaml`, no `config.yaml`) and no generic dependency resolver.

This repo previously used [rotz](https://volllly.github.io/rotz) (a Rust dotfile manager) for both installing tools and linking their config files, with a `dot.yaml` per tool. It was removed for two reasons, in this order:
1. **`rotz link` couldn't reliably deploy config files on this repo's actual target machines.** Confirmed by reading rotz's own source (`src/config.rs`, `src/commands/link.rs`): only two `LinkType` variants exist, `Symbolic` and `Hard` — no copy mode. `Symbolic` needs Windows Developer Mode, which needs admin to enable (reproduced: `rotz link` failed with "A required privilege is not held by the client (os error 1314)"). `Hard` fails outright for **file** links the moment the dotfiles repo and `$HOME` are on different drives (confirmed: `New-Item -ItemType HardLink` across `D:\...` → `C:\Users\...` fails with "The system cannot move the file to a different disk drive") — an ordinary setup, not an edge case, since nothing in this repo can assume the dotfiles clone lives on the same drive as the user profile. This is why config deployment is copy-based now — see "Deploying dotfiles" below.
2. Once `link` needed replacing with custom code anyway, `install` was the only thing rotz still did, and that reduces to "run one command per tool, in dependency order" — which this repo now just does directly and explicitly in `bootstrap.ps1`, instead of paying for a generic `depends:`-driven resolver (plus its own bootstrap cost — installing rotz itself was a whole stage) to get the same fixed order every run anyway.

**If you're tempted to reintroduce rotz, `dot.yaml`, or `rotz link`/`link_type: Hard`: don't, without first re-solving the admin/cross-drive problem above.** That problem is the entire reason this architecture exists.

## Repo layout

```
bootstrap/
  prereq.ps1     - Windows entry point (stock PowerShell 5.1): installs pwsh7, hands off
  prereq.sh      - Linux entry point (bash): installs pwsh7, hands off
  bootstrap.ps1  - pwsh7 orchestrator: fixed stage order (see below), logging, summary
  common.ps1     - shared functions, see next section
  paths.env      - DOWNLOADS_DIR/INSTALL_DIR/BACKUP_DIR config (see below)
<tool>/          - git, mise, wezterm, python, rust, zig, java, yazi, neovim
  install.ps1    - installs the tool + deploys its own config via Sync-DotLink
  <config files> - whatever that tool's install.ps1 deploys (e.g. git/gitconfig)
```

`bootstrap/common.ps1` functions, all used by `bootstrap.ps1` and/or per-tool `install.ps1`:
- `Write-Log` — the standard log line (see below).
- `Invoke-Stage` — runs a named scriptblock, logs start/finish/elapsed via `Write-Log`, `-ContinueOnError` swallows a throw into a logged `ERROR` + `$false` return instead of propagating.
- `Get-BootstrapPaths` / `Resolve-ConfiguredPath` — resolve `paths.env` (see below).
- `Get-LatestGithubAsset`, `Install-PortableZip`, `Install-PortableTarGz` — GitHub release download helpers.
- `Add-UserPath`, `Set-UserEnvVar` — persist PATH/env vars, branching on `$IsWindows`/`$IsLinux` (registry vs. `~/.profile`/`~/.bashrc`).
- `Test-DotLinkUpToDate`, `Sync-DotLink` — config deployment (see "Deploying dotfiles" below).
- `Invoke-ExternalCommand` — runs a real external program (mise, git, apt-get, ...) with `STARTING`/`FINISHED` log boundaries around its untouched output.

## Bootstrap flow — fixed order, defined in `bootstrap.ps1`

1. `prereq.ps1`/`prereq.sh` install pwsh7, then hand off to `bootstrap.ps1`.
2. `bootstrap.ps1` (pwsh7, both OSes), via `Invoke-Stage` for every step:
   1. Environment variables (`$env:DOTFILES`; Windows-only `XDG_*`).
   2. **mise** — hard dependency (no `-ContinueOnError`): python/rust/zig/java/yazi/neovim all need it, so a failure here throws and aborts the whole script instead of cascading into confusing downstream failures.
   3. **git** — also hard: neovim's stage needs `git` on PATH.
   4. `$softStages` (ordered hashtable, `-ContinueOnError`): `wezterm`, `python`, `rust`, `zig`, `java`, `yazi`, `neovim` — in that literal order. `neovim` is last because it's the one stage needing both hard dependencies above. Add new tools to this hashtable, in dependency order relative to whatever they need.
   5. Summary: per-stage `OK`/`FAILED` plus total elapsed, from the `$results` collected by each `Invoke-Stage` call.

If you add a tool whose failure would make everything after it pointless (like mise/git), give it its own `Invoke-Stage` call with no `-ContinueOnError`, placed before `$softStages`, not inside the hashtable.

## Standard log format — every script, no exceptions

```
[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [tag] message
```
`Write-Log -Tag "<tag>" -Level "INFO|WARN|ERROR" -Message "..."` in every pwsh7 script (default `-Level INFO`, default `-Tag "common"` — always pass an explicit `-Tag` matching the tool/script, e.g. `"git"`, `"neovim"`, `"bootstrap"`). Millisecond timestamps are load-bearing: they're what let you compute the gap between two log lines after a hang to see exactly where the time went, which is the whole point of this format (there's no other progress/timing UI in this repo). `prereq.ps1` and `prereq.sh` each carry their own tiny duplicate `Write-Log`/`log()` (can't dot-source `common.ps1` — see "pwsh7 boundary" below) using the identical format string. **Any new script or `Write-Host` call added to this repo must go through `Write-Log`, not bare `Write-Host`** — the one exception is `Invoke-ExternalCommand`'s pass-through of a real external program's own stdout/stderr, which must stay completely untouched (no prefix, no timestamp) so its own progress bars/spinners still render.

## pwsh7 boundary: `prereq.ps1`/`prereq.sh` vs. everything else

`bootstrap/prereq.ps1` (Windows, stock PowerShell 5.1) and `bootstrap/prereq.sh` (Linux, bash) are the only scripts not written against pwsh7 — their entire job is installing pwsh7 itself, which can't be done by a pwsh7 script. They deliberately do **not** dot-source `common.ps1` (it uses `$IsWindows`/`$IsLinux`, which don't exist under Windows PowerShell 5.1) and carry their own small, intentionally duplicated copies of: the standard log function, `paths.env` parsing/resolution (`Resolve-ConfiguredPathWindows` in `prereq.ps1`, `resolve_configured_path` in `prereq.sh`), and portable-zip/tarball download+extract logic. This is the one deliberate piece of duplication in the repo — everything past the pwsh7 handoff lives in exactly one place. `bootstrap.ps1` itself starts with `#Requires -Version 7.0` plus an explicit version check that throws a clear error if invoked under 5.1 directly, so skipping `prereq.ps1`/`prereq.sh` fails fast instead of confusingly.

## `bootstrap/paths.env`: DOWNLOADS_DIR / INSTALL_DIR / BACKUP_DIR

Plain `KEY=value` text (not YAML/PSD1) — read by three different runtimes: `Get-BootstrapPaths` (`common.ps1`, pwsh7) and the two prereq scripts' own hand-rolled parsers (PowerShell 5.1 and bash, respectively, since they run before pwsh7/`common.ps1` exist). If you add a new key, update all three parsers.

Each key is either relative to `$HOME`/`%USERPROFILE%` (joined at runtime) or an **absolute path** (e.g. `DOWNLOADS_DIR=D:\tools\download`), resolved by `Resolve-ConfiguredPath` (`common.ps1`) / the prereq scripts' equivalents. Absolute paths are OS-specific — a bare key can be overridden per OS with a `_WINDOWS`/`_LINUX` suffixed key (checked first, falls back to the bare key). A value that's absolute but shaped for the *other* OS (Windows drive letter on Linux, or vice versa) throws a clear error naming the suffixed key to add, rather than silently mangling the path. **Bash gotcha found and fixed while building this**: an unquoted `\\` in a `case` glob pattern matches two literal backslashes, not one — matching a single-backslash Windows path requires a quoted `'\'` in the pattern (`[A-Za-z]:'\'*`), not `\\`.

`Install-PortableZip`/`Install-PortableTarGz` take `-DownloadsDir`/`-DestDir` derived from this — no script hardcodes `.local/opt/<tool>` or a temp path. Every install script resolves its executable dynamically from inside its own `INSTALL_DIR` subfolder (`Get-ChildItem -Recurse` for the binary name) rather than assuming an exact archive layout.

Two exceptions to `INSTALL_DIR`: mise on Linux is installed by mise's own official installer (`curl https://mise.run | sh`), which picks `~/.local/bin/mise` on its own; and mise's *internal* data (installed toolchains, shims) lives under `~/.local/share/mise/...`, mise's own convention. Because mise's own binary doesn't live at a fixed path (Windows: wherever it lands under `<INSTALL_DIR>/mise`), `bootstrap.ps1` resolves `$miseExe` via `Get-Command mise` after `mise/install.ps1` runs, instead of hardcoding a second guess that could drift out of sync.

## Deploying dotfiles: `Sync-DotLink`, copy-based, called per-tool

No central "link" pass. Each tool's `install.ps1` calls `Sync-DotLink -Source <path> -Target "~/..." -BackupDir $paths.BackupDir` directly for whatever config it owns (e.g. `git/install.ps1` → `git/gitconfig` → `~/.gitconfig`; `neovim/install.ps1` → two folders; `wezterm`/`yazi` → their own files). It **copies**, not symlinks — see "No external orchestration tool" above for the admin/cross-drive reasoning that ruled out real links.

For each call: **target missing** → copy, nothing to back up. **Target already matches source** (`Test-DotLinkUpToDate` — file hash, or full recursive per-file hash comparison for a directory link like neovim's `config/lua/config`) → skip entirely, so re-running the bootstrap on an unchanged repo doesn't churn out fresh backups/copies every time. **Target exists and differs** → `Move-Item` to `<BackupDir>/<timestamp>/<relative path under home>` first, then `Copy-Item -Recurse -Force` the source over the now-clear path — this also means editing a tracked file and re-running the bootstrap backs up the previously-deployed version before replacing it, so nothing is ever silently overwritten.

**Cost of copying vs. symlinking, worth remembering when debugging "why didn't my edit show up":** no live sync. A copy is a snapshot from whenever `Sync-DotLink` last ran for it — editing a tracked file in this repo needs another `install.ps1` run (or a manual `Sync-DotLink` call) to reach the deployed path.

## LazyVim: clone once, `git pull` on every re-run — keep `.git`

`neovim/install.ps1` clones [LazyVim/starter](https://github.com/LazyVim/starter) into `~/.config/nvim` and **keeps `.git`** (an earlier version of this repo deleted it right after cloning specifically to detach from upstream, which meant it could only ever be cloned once — the current version deliberately reverses that so it can be kept in sync). Logic: `.git` present → `git -C <path> pull --ff-only`; `.git` absent but the directory exists (leftover from the old delete-`.git` behavior) → remove and re-clone fresh (self-healing migration); neither → clone fresh. `Sync-DotLink` for this repo's own `config/lua/config`/`lua/plugins` overrides always runs *after* the clone/pull, never before, so they land on top of whatever LazyVim's starter currently looks like.

## WezTerm is pinned to nightly — the one tool-specific exception

Every other portable tool in this repo installs the latest stable release. `wezterm/install.ps1` deliberately always installs the **nightly** build instead, on both OSes — scoped to wezterm only.

Two `common.ps1` helpers have optional params for exactly this, unused by every other call site (`git`, `mise`):
- `Get-LatestGithubAsset -Tag "nightly"` fetches `/releases/tags/nightly` instead of `/releases/latest` — required because WezTerm's nightly is marked `"prerelease": true`, which `/releases/latest` always excludes.
- `Install-PortableZip -Force` always re-downloads even if a same-named file is cached — required because WezTerm's nightly assets keep the same filename forever while the contents change on every build.

`wezterm/install.ps1` also never short-circuits on "already installed" — it always re-checks/re-downloads/re-extracts. On Linux there's no apt-repo branch at all (even with sudo) — WezTerm's apt repo only ships stable builds — so it's always the nightly AppImage (pinned to `Ubuntu20.04` for broad forward-compatibility).

## Core invariant: no hardcoded paths, no admin/sudo

Every install path in this repo is derived from `$env:USERPROFILE`/`$HOME`, never a hardcoded drive letter or absolute path, so it behaves the same whether Windows puts user profiles on `C:` or `D:`:
- Portable tool downloads/installs: `DOWNLOADS_DIR`/`INSTALL_DIR` from `bootstrap/paths.env` — defaults to `~/.local/downloads` and `~/.local/opt/<tool>`
- mise's own data: `~/.local/share/mise`, `~/.local/bin` (Linux mise binary only) — mise's own convention, not ours
- Config files: `~/.config/<tool>/...` on both OSes

PATH changes on Windows go to the **user** registry hive (`HKCU\Environment`) only, never machine-wide PATH. Any new install script must preserve this — no admin/sudo dependency anywhere it's technically avoidable.

`git` and `wezterm` are fetched directly from GitHub Releases as portable zips/AppImage/self-extracting archives (verified against `github.com/jdx/mise/registry/*.toml` to confirm they aren't in mise's registry) rather than via mise, with `$IsWindows`/`$IsLinux` branches inside a single `install.ps1` (`git` has an apt branch on Linux; `wezterm` does not — see above). `python`/`rust`/`zig` install via a plain `Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "<tool>")` one-liner install.ps1 — genuinely OS-agnostic, nothing else to do. `neovim` and `yazi` both need more than the mise install itself: `neovim` clones/updates LazyVim (see above), `yazi` adds the `y` shell wrapper. `java` needs multiple JDK versions side-by-side (see below).

### Java: multiple JDKs side-by-side

`java/install.ps1` installs Eclipse Temurin 8, 11, 17, 21, and 25 via `mise install java@temurin-<N>` (each call is a no-op if that version is already present — this is what makes reruns idempotent, not a hand-rolled existence check), then runs `mise use --global java@temurin-25` last so 25 is what `java`/`javac` resolve to with no extra config. The other four stay installed on disk under mise's install dir. Temurin specifically, not mise's generic `openjdk-<N>` shorthand — confirmed via `mise ls-remote java`/`mise latest java@temurin-<N>` that all five short-form version strings resolve to a real patch release before switching to this. If the set of versions or the default ever changes, edit the `$versions`/`$default` variables at the top of the script.

## Every network call has a timeout — this is load-bearing

Every `Invoke-WebRequest`/`Invoke-RestMethod` call passes an explicit `-TimeoutSec`. The one place a native subprocess could hang forever — Git for Windows' self-extracting `.7z.exe` — is guarded with `Start-Process -PassThru` + `$proc.WaitForExit(<ms>)`, force-killed via `Stop-Process` if it doesn't finish in time. This exists because the bootstrap used to hang indefinitely on a stalled connection (offline, corporate proxy, firewall) with zero error output. **Any new download added to this repo must follow the same pattern.**

## Adding a new tool

1. Create `<tool>/install.ps1`: install the binary (mise one-liner if registered, otherwise a portable download with `$IsWindows`/`$IsLinux` branches only where the OSes genuinely differ), then `Sync-DotLink` any config files it owns.
2. Add it to `$softStages` in `bootstrap.ps1` (or as its own hard-dependency `Invoke-Stage` call, before `$softStages`, if something later genuinely can't work without it — like `mise`/`git`).
3. If cloning a config repo (LazyVim pattern): clone/update first, `Sync-DotLink` your own overrides after, same order every time.

## Gotchas

- **Never commit a tracked `mise/config.toml` at the repo root.** `mise` recognizes `mise/config.toml` (relative to cwd) as one of its own local-project config file names, so a repo-tracked one makes every `mise` invocation from inside this repo prompt to "trust" and load it as a project config. Tool versions are pinned instead by each tool's `install.ps1` running `mise use --global <tool>`, which writes straight to mise's real global config (`~/.config/mise/config.toml`).
- `git/gitconfig` ships without `user.name`/`user.email` — these must be set per-machine (`git config --global user.name "..."`) or by editing the tracked file directly (then re-run the bootstrap, or call `Sync-DotLink` by hand, to redeploy it — editing the file alone doesn't touch what's already deployed at `~/.gitconfig`).
- `mise/install.ps1` shells out to `bash -c "curl ... | sh"` on Linux for mise's own official installer — this is the one intentional exception to "everything is pwsh", since it's the vendor-documented install method, not custom logic worth reimplementing.
- There is no `dot.yaml`, no `config.yaml`, no `depends:` resolution — if you find yourself wanting to declare a dependency between tools, express it as ordering in `bootstrap.ps1`'s stage list instead (see "Bootstrap flow" above).
