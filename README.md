# development-environment

Dotfiles + bootstrap repo managed with [rotz](https://volllly.github.io/rotz/docs/getting-started).
One command sets up a brand new Windows 11 or Ubuntu/Linux machine with the
tools below - no administrator/root account required anywhere it's
technically possible to avoid one.

Every install script in this repo (past the very first prerequisite step)
is written **once**, in PowerShell 7 (`pwsh`), and runs unmodified on both
Windows and Linux. There is no more `install.ps1` + `install.sh` pair per
tool - see "Why PowerShell 7 for everything" below for why.

## What gets installed

| Dot | How | Windows | Linux |
|---|---|---|---|
| `git` | portable download, no admin | `PortableGit-*-64-bit.7z.exe` from git-for-windows | `apt` (sudo) or manual if no sudo |
| `mise` | portable zip / official installer | `mise-*-windows-x64.zip` | `curl https://mise.run \| sh` |
| `python`, `rust`, `zig` | `mise use --global <tool>` | via mise | via mise |
| `java` | `mise install` OpenJDK 8, 11, 21 and 25 side-by-side; 25 set as `mise use --global` default | via mise | via mise |
| `yazi` | `mise use --global yazi` + config | via mise | via mise |
| `neovim` + `LazyVim` | `mise use --global neovim` + clone [LazyVim/starter](https://github.com/LazyVim/starter) | via mise | via mise |
| `wezterm` | portable download | `WezTerm-windows-*.zip` | apt repo (sudo) or portable `.AppImage` (no sudo) |

`git` and `wezterm` are **not** in mise's tool registry (verified against
`github.com/jdx/mise/registry/*.toml` before writing this), so those two are
fetched directly from their GitHub Releases as portable zips/AppImage/
self-extracting archives instead - no winget/scoop/apt dependency, no admin.

PowerShell 7 itself is **not** a dot anymore - it's installed by the
prerequisite step below, before rotz (or any dot) exists.

## Bootstrapping a new machine

```powershell
# Windows 11, from a normal (non-admin) PowerShell prompt
git clone <this-repo-url> $env:USERPROFILE\development-environment  # or copy the folder over
cd $env:USERPROFILE\development-environment
powershell -ExecutionPolicy Bypass -File .\bootstrap\prereq.ps1
```

```bash
# Ubuntu/Linux
git clone <this-repo-url> ~/development-environment  # or copy the folder over
cd ~/development-environment
bash bootstrap/prereq.sh
```

Since git itself might not exist yet on a fresh machine, you can also just
copy this folder onto the new machine (USB drive, `scp`, cloud sync, etc.)
and run the prerequisite script from there - it installs git for you as
part of `rotz install` later in the chain (see table above).

Every step prints `==> [stage] ...` as it runs, and the key values involved
(paths, URLs, resolved versions) - if the bootstrap ever hangs or fails, the
last line printed tells you exactly which stage to look at.

### What actually runs, in order

1. **`bootstrap/prereq.ps1`** (Windows, under the stock PowerShell 5.1 that
   ships with Windows - nothing else is guaranteed to exist yet) or
   **`bootstrap/prereq.sh`** (Linux, under plain bash). Its only job:
   install PowerShell 7 (`pwsh`) portably, no admin/sudo, if it isn't
   already on PATH. This is the *one* deliberately duplicated piece of
   logic in the repo - see below for why it can't be avoided.
2. Once `pwsh` exists, the prereq script hands off to
   **`bootstrap/bootstrap.ps1`**, which from this point on is the *only*
   script that runs, on both OSes:
   1. Sets `$env:DOTFILES` (persisted) and, on Windows only, the `XDG_*`
      env vars so tools like neovim/yazi/wezterm resolve config from
      `~/.config/<tool>` the same way they do by default on Linux.
   2. Installs `mise` (portable, user-scoped) via `mise/install.ps1`.
   3. Installs `rotz` itself through mise's generic GitHub backend
      (`mise use --global github:volllly/rotz` - rotz has no mise registry
      entry, but does publish standard target-triple release zips).
   4. Runs `rotz install --continue-on-error` (executes every dot's
      install command - now always `pwsh -NoProfile -File <tool>/install.ps1`)
      then `rotz link` (symlinks every dot's config files).

Open a **new terminal** afterwards so PATH/env var changes take effect.

## Why PowerShell 7 for everything

This repo used to carry an `install.ps1` **and** an `install.sh` for every
dot that needed custom logic (git, wezterm, neovim, java, mise, and
`powershell7` itself as a dot). That meant every fix had to be written
twice, in two different shell dialects with different error-handling and
quoting rules - easy for the two to quietly drift out of sync (which is
exactly what happened and is why this rewrite exists).

PowerShell 7 (`pwsh`) runs natively on Linux as well as Windows, and this
repo was already installing it as one of its own tools. So instead of
introducing a brand new language (e.g. Python) to unify things, every
`install.ps1` in this repo is now a single pwsh7 script with `$IsWindows`/
`$IsLinux` branches only where the underlying OS genuinely differs (the
Windows registry vs. `~/.profile` for persisting PATH/env vars, `apt`
vs. a portable zip for a given tool, etc.) - one file, one place to fix
things, instead of two.

The only place this doesn't fully apply is the prerequisite step
(`bootstrap/prereq.ps1` / `prereq.sh`): pwsh7 itself has to be installed by
*something*, and that something can't be a pwsh7 script, so it's a small,
intentionally duplicated, self-contained "download and extract pwsh7"
block in native PowerShell 5.1 (Windows) and bash (Linux). Everything past
that point lives in exactly one place.

## Why everything lands under the user profile

Every install path in this repo is derived from `$env:USERPROFILE` /
`$HOME` - never a hardcoded drive letter or absolute path - specifically so
it behaves the same whether Windows puts user profiles on `C:` or `D:`:

- Windows tools: `%USERPROFILE%\.local\bin`, `%USERPROFILE%\.local\opt\<tool>`
- Linux tools: `~/.local/bin`, `~/.local/share/mise`, `~/.local/opt/<tool>`
- Config files: `~/.config/<tool>/...` on both OSes (`XDG_CONFIG_HOME` /
  `XDG_DATA_HOME` / `XDG_CACHE_HOME` / `XDG_STATE_HOME` are set under
  `%USERPROFILE%` in `bootstrap.ps1` so Windows resolves the same
  `~/.config/...` paths Linux does by default)

PATH changes on Windows are written to the **user** registry hive
(`HKCU\Environment`) only, never the machine-wide PATH, so no admin session
is ever required. On Linux, the equivalent is appending to `~/.profile` /
`~/.bashrc` - both handled by the same `Add-UserPath`/`Set-UserEnvVar`
helpers in `bootstrap/common.ps1`, branching internally on `$IsWindows`.

## Every network call has a timeout

Every `Invoke-WebRequest`/`Invoke-RestMethod` call in this repo passes an
explicit `-TimeoutSec`, and the one place a native subprocess could hang
forever (Git for Windows' self-extracting `.7z.exe` installer) is guarded
with `Start-Process -PassThru` + `WaitForExit(<ms>)` and force-killed if it
doesn't finish in time. Without this, a stalled connection (offline, a
corporate proxy, a firewall) would hang the whole bootstrap indefinitely
with no error and no indication of where it got stuck - which is what this
repo used to do before these guards were added.

## Repo layout

Each top-level folder is a rotz "dot": a `dot.yaml` describing how to
install the tool (`installs`) and where its config files get symlinked
(`links`), plus the actual config files. See
[rotz's config reference](https://volllly.github.io/rotz/docs/configuration)
for the full schema. A couple of things learned by testing against the real
`rotz` binary while building this repo, that aren't obvious from the docs:

- You can't mix a bare top-level `links`/`installs`/`depends` with the
  OS-scoped `global`/`windows`/`linux` keys in the same file - it's one
  schema or the other. This repo no longer needs the OS-scoped keys at all
  (every `installs:` is now a single `pwsh -NoProfile -File ...` command
  that works unmodified on both OSes), so every `dot.yaml` uses the flat
  top-level schema now.
- `depends` entries are paths from the repo root (e.g. `/mise`), not tool
  names.
- `{{ env.DOTFILES }}` is how `installs` commands find their own helper
  scripts without depending on the current working directory.

## Adding a new tool whose config comes from a git repo

This is exactly what `neovim/install.ps1` already does for LazyVim, and the
pattern generalizes to anything else you'd rather clone than hand-author (a
starter template, someone else's config repo, a plugin manager bundle,
...):

1. Create `<tool>/dot.yaml` with `installs: pwsh -NoProfile -File "{{ env.DOTFILES }}/<tool>/install.ps1"`.
2. In that script: install the binary (mise if it's in the registry,
   otherwise a portable download like `git`/`wezterm`, branching on
   `$IsWindows`/`$IsLinux` only where the two OSes genuinely differ), then
   `git clone` the config repo into its real target location **only if it
   isn't already there** (idempotency - never clobber a working setup on
   re-runs).
3. If you also want to layer your *own* overrides on top of the cloned
   repo (like this repo does with `neovim/config/lua/config` and
   `lua/plugins`), add a `links` section in `dot.yaml` for just those
   subfolders/files, keyed after the install step so the clone exists
   first (`rotz install` runs before `rotz link` for exactly this reason).

## Gotchas

- Don't name a tracked file `mise/config.toml` inside this repo again if
  you extend it - `mise` itself recognizes `mise/config.toml` (relative to
  the current directory) as one of its own local-project config file
  names, so having one at the repo root makes every `mise` invocation from
  inside this repo prompt to "trust" and load it as if it were a project
  config. It was removed for this reason; `python`, `java`, `rust`, `zig`,
  `yazi` and `neovim` each pin their own version by running
  `mise use --global <tool>`, which writes straight to mise's real global
  config (`~/.config/mise/config.toml`) - no repo-tracked mise config
  needed.
- `git/gitconfig` ships without `user.name`/`user.email` - set those once
  per machine (`git config --global user.name "..."`) or edit the linked
  file directly.
- If `bootstrap.ps1` is run directly under Windows PowerShell 5.1 instead
  of through `prereq.ps1`, it fails immediately with a clear error (it
  requires pwsh7 - see `#Requires -Version 7.0` at the top of the file)
  rather than failing confusingly partway through.
