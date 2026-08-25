#!/usr/bin/env bash
# PREREQUISITE step for Linux. Runs under plain bash - nothing else is
# guaranteed to exist yet on a brand new machine.
#
# Its ONLY job is to get PowerShell 7 (pwsh) installed (no sudo/root), then
# hand off to bootstrap.ps1, which from that point on assumes pwsh7 and is
# the single script (shared with Windows) that installs every tool, in a
# fixed order, with no external orchestration tool involved.
#
# This script is intentionally self-contained (no shared common.sh) for the
# same reason prereq.ps1 doesn't dot-source common.ps1: it has to run before
# pwsh7 exists, so it can't reuse the pwsh7-only helpers. Duplicating this
# one small "download+extract pwsh7" block (and a matching small log
# function) is the one deliberate piece of duplication in this repo;
# everything past this point lives in exactly one place (bootstrap.ps1 +
# every tool's install.ps1, all pwsh7).
set -euo pipefail

# Same "[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [tag] message" format every other
# script in this repo uses (bootstrap/common.ps1's Write-Log) - duplicated
# here in its own tiny form since this script can't dot-source common.ps1
# (see the header comment above for why). Requires GNU date (%3N for
# milliseconds), which ships by default on Ubuntu.
log() {
  local level="INFO" message
  if [ "$#" -ge 2 ]; then level="$1"; message="$2"; else message="$1"; fi
  printf '[%s] [%-5s] [prereq] %s\n' "$(date '+%Y-%m-%d %H:%M:%S.%3N')" "$level" "$message"
}

log "Running under bash $BASH_VERSION (pwsh7 is not installed yet)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
log "Dotfiles repo: $REPO_ROOT"

# --- Step 0: read bootstrap/paths.env (same file bootstrap.ps1 reads later
# via Get-BootstrapPaths - parsed here with grep/cut since pwsh7 doesn't
# exist yet to use the PowerShell-side parser) -----------------------------
#
# Each key can be an absolute Linux path (e.g. "/opt/tools/download"), a
# "_LINUX"-suffixed override (e.g. DOWNLOADS_DIR_LINUX=...), or a relative
# fragment joined with $HOME - see bootstrap/paths.env for the full
# explanation. A value shaped like a Windows absolute path (a drive letter)
# is a configuration mistake on Linux, so this fails fast with a clear
# message instead of silently mangling it.
CONFIG_FILE="$SCRIPT_DIR/paths.env"
if [ ! -f "$CONFIG_FILE" ]; then
  log "ERROR" "Missing config file: $CONFIG_FILE"
  exit 1
fi

get_config_value() {
  # $1 = bare key name, e.g. DOWNLOADS_DIR - prefers <key>_LINUX if set
  local key="$1" suffixed
  suffixed="$(grep -E "^${key}_LINUX=" "$CONFIG_FILE" | head -n1 | cut -d= -f2-)"
  if [ -n "$suffixed" ]; then
    printf '%s' "$suffixed"
  else
    grep -E "^${key}=" "$CONFIG_FILE" | head -n1 | cut -d= -f2-
  fi
}

resolve_configured_path() {
  # $1 = key name (for error messages), $2 = raw value from paths.env
  local key="$1" value="$2"
  case "$value" in
    /*) printf '%s' "$value" ;;
    [A-Za-z]:'\'*|[A-Za-z]:/*)
      # The '\' above is quoted deliberately - an unquoted \\ in a case
      # pattern matches two literal backslashes, not one, and would fail
      # to match a real single-backslash Windows path like "D:\tools\...".
      log "ERROR" "$key is set to '$value', which looks like a Windows absolute path, but this is Linux. Set ${key}_LINUX in bootstrap/paths.env to a Linux path instead."
      exit 1
      ;;
    *) printf '%s/%s' "$HOME" "$value" ;;
  esac
}

DOWNLOADS_DIR_RAW="$(get_config_value DOWNLOADS_DIR)"
INSTALL_DIR_RAW="$(get_config_value INSTALL_DIR)"
if [ -z "$DOWNLOADS_DIR_RAW" ] || [ -z "$INSTALL_DIR_RAW" ]; then
  log "ERROR" "$CONFIG_FILE is missing DOWNLOADS_DIR or INSTALL_DIR"
  exit 1
fi
DOWNLOADS_DIR="$(resolve_configured_path DOWNLOADS_DIR "$DOWNLOADS_DIR_RAW")"
INSTALL_DIR="$(resolve_configured_path INSTALL_DIR "$INSTALL_DIR_RAW")"
mkdir -p "$DOWNLOADS_DIR" "$INSTALL_DIR"
log "DownloadsDir: $DOWNLOADS_DIR"
log "InstallDir:   $INSTALL_DIR"

DEST_DIR="$INSTALL_DIR/pwsh7"
PWSH_BIN="$DEST_DIR/pwsh"

# --- Step 1: is pwsh7 already available anywhere on PATH? -----------------
if command -v pwsh >/dev/null 2>&1; then
  PWSH_BIN="$(command -v pwsh)"
  log "pwsh already on PATH at $PWSH_BIN - skipping download"
elif [ -x "$PWSH_BIN" ]; then
  log "pwsh7 already installed at $PWSH_BIN - skipping download"
else
  log "pwsh7 not found - downloading PowerShell 7 (portable tarball, no sudo)"

  # --- Step 2: resolve the latest release asset URL -----------------------
  REPO="PowerShell/PowerShell"
  PATTERN='powershell-[0-9.]+-linux-x64\.tar\.gz$'
  log "Querying GitHub API for latest release of $REPO"
  URL="$(curl -fsSL --max-time 30 -H "User-Agent: dotfiles-bootstrap" \
      "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed -E 's/.*"(https[^"]+)"/\1/' \
    | grep -E "$PATTERN" \
    | head -n1)"

  if [ -z "$URL" ]; then
    log "ERROR" "Could not find a linux-x64 tar.gz asset in the latest release of $REPO (offline? GitHub API rate-limited?)"
    exit 1
  fi
  log "Resolved download URL: $URL"

  # --- Step 3: download the tarball into DOWNLOADS_DIR (guarded with a
  # timeout, kept afterwards - not deleted - so a re-run skips the download) -
  TAR_FILE_NAME="$(basename "$URL")"
  TAR_PATH="$DOWNLOADS_DIR/$TAR_FILE_NAME"
  if [ -f "$TAR_PATH" ]; then
    log "Already downloaded at $TAR_PATH - skipping download"
  else
    log "Downloading to $TAR_PATH (timeout 300s)"
    curl -fsSL --max-time 300 "$URL" -o "$TAR_PATH"
  fi
  log "$(du -h "$TAR_PATH" | cut -f1) - extracting to $DEST_DIR"

  # --- Step 4: extract ------------------------------------------------------
  mkdir -p "$DEST_DIR"
  tar -xzf "$TAR_PATH" -C "$DEST_DIR"
  chmod +x "$PWSH_BIN"

  if [ ! -x "$PWSH_BIN" ]; then
    log "ERROR" "pwsh binary not found at $PWSH_BIN after extracting - archive layout may have changed"
    exit 1
  fi
  log "pwsh7 extracted successfully to $PWSH_BIN"
fi

# --- Step 5: put pwsh7 on PATH (current session + persisted) --------------
log "Adding $DEST_DIR to PATH"
case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *) export PATH="$PATH:$DEST_DIR" ;;
esac
for rc in "$HOME/.profile" "$HOME/.bashrc"; do
  [ -f "$rc" ] || touch "$rc"
  grep -qF "PATH=\"\$PATH:$DEST_DIR\"" "$rc" 2>/dev/null || printf '\nexport PATH="$PATH:%s"\n' "$DEST_DIR" >> "$rc"
done

log "pwsh7 executable: $PWSH_BIN"
if ! PWSH_VERSION="$("$PWSH_BIN" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1)"; then
  log "ERROR" "pwsh7 downloaded but failed to run. Output was: $PWSH_VERSION"
  cat >&2 <<EOF

This is usually a missing shared library on minimal distros (commonly
libicu). Try: sudo apt-get install -y libicu-dev  (or the libicuXX package
matching your distro), then re-run this script.
EOF
  exit 1
fi
log "pwsh7 version: $PWSH_VERSION"

# --- Step 6: hand off to the unified bootstrap script, running under pwsh7 -
MAIN_SCRIPT="$REPO_ROOT/bootstrap/bootstrap.ps1"
log "Handing off to $MAIN_SCRIPT (now running under pwsh7)"
exec "$PWSH_BIN" -NoProfile -File "$MAIN_SCRIPT"
