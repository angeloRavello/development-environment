# development-environment

Dotfiles + bootstrap repo. One command sets up a brand new Windows 11 or
Ubuntu/Linux machine with the tools below - no administrator/root account
required anywhere it's technically possible to avoid one.

**Pure PowerShell, no external orchestration tool.** Every script in this
repo (past the very first prerequisite step) is PowerShell 7 (`pwsh`), and
runs unmodified on both Windows and Linux. `bootstrap/bootstrap.ps1` *is*
the orchestrator - it calls each tool's own `install.ps1` directly, in a
fixed, explicit order, with no external dependency-resolution tool
involved. (This repo used to use [rotz](https://volllly.github.io/rotz)
for that; it was removed - see "Why no external tool" below.)

## What gets installed

| Tool | How | Windows | Linux |
|---|---|---|---|
| `git` | portable download, no admin | `PortableGit-*-64-bit.7z.exe` from git-for-windows | `apt` (sudo) or manual if no sudo |
| `mise` | portable zip / official installer | `mise-*-windows-x64.zip` | `curl https://mise.run \| sh` |
| `wezterm` | portable download, **always nightly** (see below) | `WezTerm-windows-nightly.zip` | portable `.AppImage`, nightly (no apt, no sudo) |
| `python`, `rust`, `zig` | `mise use --global <tool>` | via mise | via mise |
| `java` | `mise install` Eclipse Temurin 8, 11, 17, 21 and 25 side-by-side; 25 set as `mise use --global` default | via mise | via mise |
| `yazi` | `mise use --global yazi` + config + `y` shell wrapper (see below) | via mise | via mise |
| `neovim` + `LazyVim` | `mise use --global neovim` + clone/update [LazyVim/starter](https://github.com/LazyVim/starter) (see below) | via mise | via mise |

`git` and `wezterm` are **not** in mise's tool registry (verified against
`github.com/jdx/mise/registry/*.toml`), so those two are fetched directly
from their GitHub Releases as portable zips/AppImage/self-extracting
archives instead - no winget/scoop/apt dependency, no admin.

PowerShell 7 itself is installed by the prerequisite step below, before
anything else in this table.

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
one of the very first stages (see "What actually runs" below).

Every line printed follows the same format:
```
[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [tag] message
```
The millisecond timestamp is the point: if the bootstrap ever hangs or
fails, look at the last line printed and the gap since the one before it -
that tells you exactly which stage was running and how long it had
already been running for. See "Standard log format" below for the full
story, including `Invoke-Stage`, which is what actually produces the
per-stage start/finish/elapsed lines.

### What actually runs, in order

1. **`bootstrap/prereq.ps1`** (Windows, under the stock PowerShell 5.1 that
   ships with Windows - nothing else is guaranteed to exist yet) or
   **`bootstrap/prereq.sh`** (Linux, under plain bash). Its only job:
   install PowerShell 7 (`pwsh`) portably, no admin/sudo, if it isn't
   already on PATH. This is the *one* deliberately duplicated piece of
   logic in the repo - see "Why PowerShell 7 for everything" below for why.
2. Once `pwsh` exists, the prereq script hands off to
   **`bootstrap/bootstrap.ps1`**, which from this point on is the *only*
   script that runs, on both OSes, in this fixed order:
   1. Environment variables: `$env:DOTFILES` (persisted) and, on Windows
      only, `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_CACHE_HOME`/`XDG_STATE_HOME`
      so tools resolve config from `~/.config/<tool>` the same way they do
      by default on Linux.
   2. **mise** - a *hard* dependency: python/rust/zig/java/yazi/neovim all
      need it. If this stage fails, the whole bootstrap aborts immediately
      instead of limping through six more stages that can't possibly work
      without it.
   3. **git** - also hard: neovim's stage needs `git` on PATH to
      clone/update LazyVim.
   4. **wezterm, python, rust, zig, java, yazi, neovim**, in that order -
      *soft* stages: a failure here is logged and the bootstrap keeps
      going (same spirit as rotz's old `--continue-on-error`), since none
      of these block each other. `neovim` is last because it's the one
      stage that depends on both of the hard ones above.
   5. A final summary: every stage name with `OK`/`FAILED`, and the total
      elapsed time.

Open a **new terminal** afterwards so PATH/env var changes take effect.

## Why no external orchestration tool

This repo used to run every tool's install command through
[rotz](https://volllly.github.io/rotz), a dotfile manager, with each tool
folder carrying a `dot.yaml` describing its `installs:`/`links:`/`depends:`.
It was removed:

- **`rotz link` couldn't reliably deploy config files here.** Confirmed by
  reading rotz's own source (`src/config.rs`, `src/commands/link.rs`):
  its only two link modes are `Symbolic` (needs Windows Developer Mode,
  which itself needs an admin session to turn on - reproduced the actual
  failure: `rotz link` erroring "A required privilege is not held by the
  client (os error 1314)") and `Hard` (hard links for files fail outright
  the moment the dotfiles repo and `$HOME` are on different drives, e.g.
  `D:\...\development-environment` vs `C:\Users\...` - an ordinary setup,
  not an edge case). Neither is guaranteed available, so dotfiles are now
  deployed by **copying** instead - see "Deploying dotfiles" below.
- Once `link` needed replacing, `install` was the only thing left rotz was
  doing, and that's just "run a command per tool, in dependency order" -
  easy enough to do directly in `bootstrap.ps1` with an explicit, hardcoded
  order (see "What actually runs" above) instead of a generic
  `depends:`-driven resolver. One less moving part, one less thing to
  install before the actual tools can start installing.

## Why PowerShell 7 for everything

This repo used to carry an `install.ps1` **and** an `install.sh` per tool.
That meant every fix had to be written twice, in two different shell
dialects with different error-handling and quoting rules - easy for the
two to quietly drift out of sync (which is exactly what happened and part
of why this repo keeps getting simplified).

PowerShell 7 (`pwsh`) runs natively on Linux as well as Windows, and this
repo already installs it as one of its own tools. So instead of
introducing a brand new language (e.g. Python) to unify things, every
`install.ps1` in this repo is a single pwsh7 script with `$IsWindows`/
`$IsLinux` branches only where the underlying OS genuinely differs (the
Windows registry vs. `~/.profile` for persisting PATH/env vars, `apt` vs.
a portable zip for a given tool, etc.) - one file, one place to fix
things, instead of two.

The only place this doesn't fully apply is the prerequisite step
(`bootstrap/prereq.ps1` / `prereq.sh`): pwsh7 itself has to be installed by
*something*, and that something can't be a pwsh7 script, so it's a small,
intentionally duplicated, self-contained "download and extract pwsh7"
block (with its own tiny copy of the standard log function) in native
PowerShell 5.1 (Windows) and bash (Linux). Everything past that point
lives in exactly one place.

## Standard log format

Every script in this repo logs the same way:
```
[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [tag] message
```
- **Timestamp**, millisecond resolution - lets you compute exactly how
  long any gap between two lines took, which is the main tool for finding
  a hang or a slow step after the fact.
- **LEVEL** - `INFO`/`WARN`/`ERROR`, padded to a fixed width so lines stay
  aligned.
- **tag** - which script/stage produced the line (`bootstrap`, `mise`,
  `git`, `external`, ...).

`Write-Log` (`bootstrap/common.ps1`) is the function behind this for every
pwsh7 script. `bootstrap.ps1` additionally wraps every stage in
`Invoke-Stage`, which logs a start line, an end line with elapsed time,
and - on failure - an `ERROR` line with elapsed time too, so you always
know both which stage was running and how long it had been running for.
`Invoke-ExternalCommand` (also `common.ps1`) does the same for a call to a
real external program (mise, git, apt-get, ...), bracketing its raw
output with `STARTING`/`FINISHED` log lines so it's unambiguous which
console output is this repo's own and which belongs to the program itself.

`prereq.ps1` and `prereq.sh` each carry their own tiny copy of this same
log function (see "Why PowerShell 7 for everything" above for why they
can't share `common.ps1`), so the format is consistent from the very first
line the bootstrap ever prints.

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
key to add, instead of silently mangling the path.

In practice:

- **`DOWNLOADS_DIR`** ends up holding the raw `.zip`/`.tar.gz`/self-extracting
  `.exe` for every portable tool (mise, git, wezterm, pwsh7 itself) exactly
  as downloaded from GitHub Releases. Files here are **kept, not deleted**
  after extraction - a re-run that finds the same filename already there
  skips the download entirely (GitHub release asset names virtually always
  embed the version, so this is a meaningful cache, not just a debugging
  convenience).
- **`INSTALL_DIR`** ends up holding one subfolder per tool -
  `<INSTALL_DIR>/git`, `<INSTALL_DIR>/wezterm`, `<INSTALL_DIR>/mise`,
  `<INSTALL_DIR>/pwsh7` - each the full extracted contents of that tool's
  archive. Every install script resolves its executable from inside its
  own subfolder here (searching for it if the archive nests things) and
  adds that subfolder to PATH - nothing gets copied out into a separate
  `bin` directory.

Two exceptions, both called out in the scripts themselves: mise on Linux
is installed by mise's own official installer script, which picks its own
location (`~/.local/bin/mise`); and mise's *own* internal data (installed
toolchains, shims) lives under `~/.local/share/mise/...`, mise's own
convention, unrelated to `INSTALL_DIR`.

## WezTerm is pinned to nightly (the one exception)

Every other portable tool in this repo installs the latest **stable**
release. WezTerm is the deliberate exception: `wezterm/install.ps1` always
fetches the **nightly** build instead, on both Windows and Linux.

- WezTerm's nightly is tagged `nightly` on GitHub and marked as a
  **prerelease** - the usual `/releases/latest` API endpoint would never
  return it. `Get-LatestGithubAsset` takes an optional `-Tag` parameter
  for exactly this; only `wezterm/install.ps1` passes `-Tag "nightly"`.
- The same tag gets **overwritten** continuously, and the asset filenames
  never change even though the contents do - so `Install-PortableZip`
  takes an optional `-Force` switch (only `wezterm/install.ps1` passes it)
  to always re-download over whatever's cached, instead of assuming a
  same-named file means "already have the latest" like every other tool
  here does.
- `wezterm/install.ps1` also never short-circuits on "already installed" -
  it always re-checks and re-installs on every bootstrap run.
- On Linux there's no apt-repo path at all, even with sudo: WezTerm's apt
  repo only carries stable builds. The AppImage path is pinned to the
  Ubuntu 20.04 build for broad forward-compatibility (older-glibc builds
  generally still run fine on newer distros).

## yazi's `y` shell wrapper (quick `cd` on quit)

`yazi/install.ps1` installs yazi via mise *and* adds the
[official `y` shell wrapper function](https://yazi-rs.github.io/docs/quick-start#shell-wrapper)
to your shell profile - Windows: pwsh7's `$PROFILE`; Linux: `~/.bashrc`.

Running `yazi` directly only ever affects yazi's own process: whatever
directory you end up browsing to, quitting always drops your shell back
exactly where you started. The `y` function works around that by passing
`--cwd-file` to yazi, reading back whatever directory you were in when you
quit, and `cd`-ing your actual shell there - so `y` (instead of `yazi`) is
the "browse around, then actually land there" version.

This is written to your profile idempotently, via the same marker-comment
pattern `Sync-DotLink` uses for backups: the function body is wrapped in
`# >>> yazi shell wrapper ... >>>` / `# <<< ... <<<` markers, and a re-run
replaces everything between them instead of appending a duplicate. Open a
**new terminal** (or `. $PROFILE` / `source ~/.bashrc`) before `y` is
available.

## LazyVim: cloned once, updated on every re-run

`neovim/install.ps1` clones [LazyVim/starter](https://github.com/LazyVim/starter)
into `~/.config/nvim` the first time, and **keeps its `.git` folder** (an
earlier version of this repo deleted it right after cloning, which meant
it could only ever be installed once and never updated). On every
subsequent run:

- If `~/.config/nvim/.git` exists, it runs `git -C <path> pull --ff-only`
  to bring it up to date with upstream.
- If `~/.config/nvim` exists but has no `.git` (a leftover from an older
  version of this repo), it removes that folder and re-clones fresh -
  self-healing, so a machine that ran the old behavior once
  automatically gets update capability on its next run.

This repo's own overrides (`neovim/config/lua/config`, `neovim/config/lua/plugins`)
are deployed with `Sync-DotLink` *after* the clone/update step, so they
always land on top of whatever LazyVim's current starter looks like, not
before it exists.

## Deploying dotfiles: copied, not symlinked

There's no central "link" pass anymore - each tool's `install.ps1` calls
`Sync-DotLink` (`bootstrap/common.ps1`) directly for whatever config it
owns (e.g. `git/install.ps1` deploys `git/gitconfig` -> `~/.gitconfig`).
It **copies** the source onto the target - see "Why no external
orchestration tool" above for why not a symlink.

Copying has one real cost: **no live sync**. A symlink means editing a
tracked file in this repo immediately shows up at the deployed path; a
copy is a snapshot from whenever `Sync-DotLink` last ran for it. Edit
something in this repo and you need another bootstrap run for the change
to reach `~/.gitconfig` etc.

`Sync-DotLink` still protects whatever was already at a target before
deploying over it:

- **Target doesn't exist** - just copy, nothing to lose.
- **Target already matches the source** (compared by file hash - a whole
  directory tree if the link is a folder, like neovim's `config/lua/config`)
  - skip entirely. This is what keeps re-running the bootstrap on an
  unchanged repo cheap and quiet instead of re-backing-up and re-copying
  everything every single time.
- **Target exists and differs** - move it to
  `BACKUP_DIR/<timestamp>/<same relative path under home>` (`BACKUP_DIR`
  is configured in `bootstrap/paths.env`, default `~/.local/backup`) first,
  *then* copy the current source over it. This also means: if you edit a
  tracked file in this repo and re-run the bootstrap, the previously
  deployed version gets backed up before being replaced by the new one -
  nothing is ever silently overwritten without a copy of what was there
  before.

```
~/.local/backup/20260824-153000/.gitconfig
~/.local/backup/20260824-153000/.config/nvim/lua/config
```

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

Each top-level folder is one tool: an `install.ps1` that installs the tool
(via mise, or a portable download) and, if it has any, deploys its own
config files via `Sync-DotLink`. There is no manifest file describing
tools or dependencies - `bootstrap/bootstrap.ps1` is the single place that
lists every tool and the order they install in.

```
bootstrap/
  prereq.ps1     - Windows: installs pwsh7 (stock PS 5.1), then hands off
  prereq.sh      - Linux: installs pwsh7 (bash), then hands off
  bootstrap.ps1  - the orchestrator: fixed stage order, logging, summary
  common.ps1     - shared functions (Write-Log, Invoke-Stage, Sync-DotLink,
                   Get-BootstrapPaths, Get-LatestGithubAsset,
                   Install-PortableZip/TarGz, Add-UserPath, Set-UserEnvVar,
                   Invoke-ExternalCommand)
  paths.env      - DOWNLOADS_DIR/INSTALL_DIR/BACKUP_DIR config
<tool>/
  install.ps1    - installs the tool, deploys its config via Sync-DotLink
  <config files> - whatever that tool's install.ps1 deploys
```

## Adding a new tool

1. Create `<tool>/install.ps1`. Install the binary (mise if it's in the
   registry - `Invoke-ExternalCommand -Exe "mise" -Arguments @("use", "--global", "<tool>")`
   - otherwise a portable download like `git`/`wezterm`, with
   `$IsWindows`/`$IsLinux` branches only where the two OSes genuinely
   differ). Deploy any config files with `Sync-DotLink -Source ... -Target ... -BackupDir $paths.BackupDir`.
2. Add it to `$softStages` in `bootstrap.ps1` (or, if something later
   genuinely can't work without it, add it as its own hard-dependency
   stage like `mise`/`git`, before whatever needs it).
3. If you want to layer your *own* overrides on top of a cloned repo (like
   this repo does for neovim/LazyVim), clone/update it first, then call
   `Sync-DotLink` for just the subfolders/files you're overriding -
   always in that order, so the clone exists before your overrides land
   on top of it.

## Gotchas

- Don't name a tracked file `mise/config.toml` inside this repo again if
  you extend it - `mise` itself recognizes `mise/config.toml` (relative to
  the current directory) as one of its own local-project config file
  names, so having one at the repo root makes every `mise` invocation from
  inside this repo prompt to "trust" and load it as if it were a project
  config. Tool versions are pinned instead by each tool's `install.ps1`
  running `mise use --global <tool>`, which writes straight to mise's real
  global config (`~/.config/mise/config.toml`) - no repo-tracked mise
  config needed.
- `git/gitconfig` ships without `user.name`/`user.email` - set those once
  per machine (`git config --global user.name "..."`) or edit the tracked
  file directly (then re-run the bootstrap, or `Sync-DotLink` by hand, to
  redeploy it).
- If `bootstrap.ps1` is run directly under Windows PowerShell 5.1 instead
  of through `prereq.ps1`, it fails immediately with a clear error (it
  requires pwsh7 - see `#Requires -Version 7.0` at the top of the file)
  rather than failing confusingly partway through.
