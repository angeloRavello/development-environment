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
| `java` | `mise install` Eclipse Temurin 8, 11, 17, 21 and 25 side-by-side; 25 set as `mise use --global` default | via mise | via mise |
| `yazi` | `mise use --global yazi` + config + `y` shell wrapper (see below) | via mise | via mise |
| `neovim` + `LazyVim` | `mise use --global neovim` + clone [LazyVim/starter](https://github.com/LazyVim/starter) | via mise | via mise |
| `wezterm` | portable download, **always nightly** (see below) | `WezTerm-windows-nightly.zip` | portable `.AppImage`, nightly (no apt, no sudo) |

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
   4. Backs up any pre-existing real dotfile a `dot.yaml` is about to
      symlink over (see "Backing up pre-existing dotfiles" below).
   5. Runs `rotz install --continue-on-error` (executes every dot's
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

- Config files: `~/.config/<tool>/...` on both OSes (`XDG_CONFIG_HOME` /
  `XDG_DATA_HOME` / `XDG_CACHE_HOME` / `XDG_STATE_HOME` are set under
  `%USERPROFILE%` in `bootstrap.ps1` so Windows resolves the same
  `~/.config/...` paths Linux does by default)
- Everything else a portable tool needs (downloads, extracted binaries) -
  see the next section.

PATH changes on Windows are written to the **user** registry hive
(`HKCU\Environment`) only, never the machine-wide PATH, so no admin session
is ever required. On Linux, the equivalent is appending to `~/.profile` /
`~/.bashrc` - both handled by the same `Add-UserPath`/`Set-UserEnvVar`
helpers in `bootstrap/common.ps1`, branching internally on `$IsWindows`.

## Where downloads and installs land (`bootstrap/paths.env`)

Two locations, both configured in one place - `bootstrap/paths.env` -
instead of hardcoded per tool:

```
DOWNLOADS_DIR=.local/downloads   # where downloaded archives are saved
INSTALL_DIR=.local/opt           # where they get extracted to, one folder per tool
```

Each value can be **relative** (joined with `$HOME`/`%USERPROFILE%`, as
above) or an **absolute path**, e.g.:

```
DOWNLOADS_DIR=D:\tools\download
INSTALL_DIR=D:\tools\apps
```

Windows and Linux paths are never interchangeable, so an absolute path is
inherently OS-specific - add a `_WINDOWS` or `_LINUX` suffixed key to give
each OS its own value; it takes priority over the bare key on that OS:

```
DOWNLOADS_DIR_WINDOWS=D:\tools\download
DOWNLOADS_DIR_LINUX=/opt/tools/download
```

If the bare key is absolute and shaped for the *other* OS (a Windows drive
letter while running on Linux, or the reverse) and no suffixed override
exists for the OS actually running, every script that resolves these
(`Get-BootstrapPaths` in `common.ps1`, and `prereq.ps1`/`prereq.sh` by
hand) fails immediately with a clear message telling you which suffixed
key to add, instead of silently mangling the path (e.g. joining
`%USERPROFILE%` with a Windows drive letter path, or trying to `mkdir` a
literal `D:\tools\download` directory name on Linux).

In practice:

- **`DOWNLOADS_DIR`** ends up holding the raw `.zip`/`.tar.gz`/self-extracting
  `.exe` for every portable tool (mise, git, wezterm, pwsh7 itself) exactly
  as downloaded from GitHub Releases. Files here are **kept, not deleted**
  after extraction - a re-run that finds the same filename already there
  skips the download entirely (GitHub release asset names virtually always
  embed the version, e.g. `mise-v2026.8.11-windows-x64.zip`, so this is a
  meaningful cache, not just a debugging convenience).
- **`INSTALL_DIR`** ends up holding one subfolder per tool -
  `<INSTALL_DIR>/git`, `<INSTALL_DIR>/wezterm`, `<INSTALL_DIR>/mise`,
  `<INSTALL_DIR>/pwsh7` - each the full extracted contents of that tool's
  archive. Every install script resolves its executable from inside its
  own subfolder here (searching for it if the archive nests things, rather
  than assuming an exact layout) and adds that subfolder to PATH - nothing
  gets copied out into a separate `bin` directory.

`bootstrap/common.ps1`'s `Get-BootstrapPaths` reads this file and resolves
both values for every pwsh7 script in the repo (`bootstrap.ps1` and every
`install.ps1`). The prereq scripts (`prereq.ps1`/`prereq.sh`), which run
*before* pwsh7 exists, parse the same file by hand with a plain regex
(PowerShell 5.1) or `grep`/`cut` (bash) - which is exactly why this file is
plain `KEY=value` text and not YAML or a PowerShell data file: it has to be
readable by three different runtimes, one of which isn't PowerShell at all.

Two exceptions, both intentional and called out in the scripts themselves:
- `mise` on Linux is installed by mise's own official installer script
  (`curl https://mise.run | sh`), which picks its own location
  (`~/.local/bin/mise`) - not something this repo controls.
- mise's *own* internal data (installed toolchains, shims) lives under
  `~/.local/share/mise/...`, mise's own convention, unrelated to
  `INSTALL_DIR` - only the `mise` binary itself follows this repo's
  `INSTALL_DIR`/`DOWNLOADS_DIR` convention.

## WezTerm is pinned to nightly (the one exception)

Every other portable tool in this repo installs the latest **stable**
release. WezTerm is the deliberate exception: `wezterm/install.ps1` always
fetches the **nightly** build instead, on both Windows and Linux.

This needs different machinery than every other tool here, because
WezTerm's nightly release isn't a normal versioned release:

- It's tagged `nightly` on GitHub, and marked as a **prerelease** - which
  means the usual `/releases/latest` API endpoint would never return it
  (that endpoint explicitly skips prereleases). `Get-LatestGithubAsset`
  takes an optional `-Tag` parameter for exactly this - only `wezterm`'s
  install script passes `-Tag "nightly"`; every other call site (`git`,
  `mise`) is unaffected and still hits `/releases/latest` as before.
- The same tag gets **overwritten** with a new build continuously, and the
  asset filenames (`WezTerm-windows-nightly.zip`,
  `WezTerm-nightly-Ubuntu20.04.AppImage`) never change even though the
  contents do. That breaks this repo's normal download cache (which skips
  re-downloading a file it already has by that name, since GitHub release
  filenames virtually always embed a version) - so `Install-PortableZip`
  takes an optional `-Force` switch, and only `wezterm/install.ps1` passes
  it, to always re-download over whatever's cached.
- Because of the above, `wezterm/install.ps1` also never short-circuits on
  "already installed" the way every other install script does - it always
  re-checks and re-installs on every bootstrap run, since staying current
  is the entire point.
- On Linux this also means no apt-repo install path, even with sudo
  available: WezTerm's apt repo only carries stable builds, which would
  silently defeat "always nightly" for anyone with sudo. The AppImage path
  is pinned to the Ubuntu 20.04 build specifically for broad
  forward-compatibility (older-glibc builds generally still run fine on
  newer distros; the reverse isn't guaranteed) - bump it in
  `wezterm/install.ps1` if it ever stops working on whatever you're running.

## yazi's `y` shell wrapper (quick `cd` on quit)

`yazi/install.ps1` installs yazi via mise *and* adds the
[official `y` shell wrapper function](https://yazi-rs.github.io/docs/quick-start#shell-wrapper)
to your shell profile - Windows: pwsh7's `$PROFILE`; Linux: `~/.bashrc`.

Running `yazi` directly only ever affects yazi's own process: whatever
directory you end up browsing to, quitting always drops your shell back
exactly where you started. The `y` function works around that by passing
`--cwd-file` to yazi, reading back whatever directory you were in when you
quit, and `cd`-ing your actual shell there - so `y` (instead of `yazi`) is
the "browse around, then actually land there" version. Use `y` day to day;
`yazi` still works normally if you specifically don't want the `cd` behavior.

This is written to your profile idempotently: `yazi/install.ps1` wraps the
function in `# >>> yazi shell wrapper ... >>>` / `# <<< ... <<<` marker
comments, and a re-run replaces everything between those markers instead
of appending a duplicate definition - so updating the wrapper's own code
in `yazi/install.ps1` and re-running the bootstrap correctly updates it in
your profile too, and anything else already in your profile is left alone.

As with any profile change, open a **new terminal** (or `. $PROFILE` /
`source ~/.bashrc`) before `y` is available.

## Backing up pre-existing dotfiles

If you already had a real `~/.gitconfig`, `~/.config/nvim`, `~/.config/wezterm/wezterm.lua`,
or `~/.config/yazi/*` before ever pointing this repo at the machine, `rotz link`
is about to replace each of those with a symlink into this repo. Before that
happens, `bootstrap.ps1` (Stage 4/5) moves whatever is *actually there* into
`BACKUP_DIR` (also configured in `bootstrap/paths.env`, default `~/.local/backup`),
under a timestamped folder that mirrors the original path:

```
~/.local/backup/20260824-153000/.gitconfig
~/.local/backup/20260824-153000/.config/nvim/lua/config
```

This is driven by `bootstrap/common.ps1`'s `Backup-ExistingLinkTargets`, which:

- Reads every `dot.yaml`'s `links:` block itself (via `Get-DotLinkTargets`,
  a small parser scoped to the exact shape this repo's `links:` blocks use -
  not a general YAML parser), so it stays in sync with the repo automatically
  and there's no separate list of "things to back up" to maintain.
- Only backs something up if it's a **real** file or folder. If a target is
  already a symlink/junction (a reparse point) - meaning a previous run of
  this same repo already linked it - it's left completely alone. This makes
  the whole thing idempotent: the backup step only ever does something the
  *first* time a given dotfile gets linked, never on every re-run.
- Moves (not copies) the original out of the way, which is also what
  actually frees up the path for `rotz link` to place a symlink there.

**Windows note:** creating real symlinks requires either an admin session or
Developer Mode enabled (`Settings > Update & Security > For developers`) -
confirmed while testing this feature, `New-Item -ItemType SymbolicLink`
fails with "Administrator privilege required" otherwise. Since `config.yaml`
sets `link_type: Symbolic`, `rotz link` needs one of those two on Windows;
if it doesn't have either, `rotz link` itself will fail even after the
backup step succeeds. Enable Developer Mode once per machine if you hit this.

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
