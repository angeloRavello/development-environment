#!/usr/bin/env bash
# PREREQUISITE step for Linux. Runs under plain bash - nothing else is
# guaranteed to exist yet on a brand new machine.
#
# Its ONLY job is to get PowerShell 7 (pwsh) installed (no sudo/root), then
# hand off to bootstrap.ps1, which from that point on assumes pwsh7 and is
# the single script (shared with Windows) that does everything else: mise,
# rotz, installing/linking every dot.
#
# This script is intentionally self-contained (no shared common.sh) for the
# same reason prereq.ps1 doesn't dot-source common.ps1: it has to run before
# pwsh7 exists, so it can't reuse the pwsh7-only helpers. Duplicating this
# one small "download+extract pwsh7" block is the one deliberate piece of
# duplication in this repo; everything past this point lives in exactly one
# place (bootstrap.ps1 + the per-dot install.ps1 scripts, all pwsh7).
set -euo pipefail

echo "==> [prereq] Running under bash $BASH_VERSION (pwsh7 is not installed yet)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "==> [prereq] Dotfiles repo: $REPO_ROOT"

# --- Step 0: read bootstrap/paths.env (same file bootstrap.ps1 reads later
# via Get-BootstrapPaths - parsed here with grep/cut since pwsh7 doesn't
# exist yet to use the PowerShell-side parser) -----------------------------
CONFIG_FILE="$SCRIPT_DIR/paths.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[prereq] Missing config file: $CONFIG_FILE" >&2
  exit 1
fi
DOWNLOADS_DIR_REL="$(grep -E '^DOWNLOADS_DIR=' "$CONFIG_FILE" | head -n1 | cut -d= -f2-)"
INSTALL_DIR_REL="$(grep -E '^INSTALL_DIR=' "$CONFIG_FILE" | head -n1 | cut -d= -f2-)"
if [ -z "$DOWNLOADS_DIR_REL" ] || [ -z "$INSTALL_DIR_REL" ]; then
  echo "[prereq] $CONFIG_FILE is missing DOWNLOADS_DIR or INSTALL_DIR" >&2
  exit 1
fi
DOWNLOADS_DIR="$HOME/$DOWNLOADS_DIR_REL"
INSTALL_DIR="$HOME/$INSTALL_DIR_REL"
mkdir -p "$DOWNLOADS_DIR" "$INSTALL_DIR"
echo "==> [prereq] DownloadsDir: $DOWNLOADS_DIR"
echo "==> [prereq] InstallDir:   $INSTALL_DIR"

DEST_DIR="$INSTALL_DIR/pwsh7"
PWSH_BIN="$DEST_DIR/pwsh"

# --- Step 1: is pwsh7 already available anywhere on PATH? -----------------
if command -v pwsh >/dev/null 2>&1; then
  PWSH_BIN="$(command -v pwsh)"
  echo "==> [prereq] pwsh already on PATH at $PWSH_BIN - skipping download"
elif [ -x "$PWSH_BIN" ]; then
  echo "==> [prereq] pwsh7 already installed at $PWSH_BIN - skipping download"
else
  echo "==> [prereq] pwsh7 not found - downloading PowerShell 7 (portable tarball, no sudo)"

  # --- Step 2: resolve the latest release asset URL -----------------------
  REPO="PowerShell/PowerShell"
  PATTERN='powershell-[0-9.]+-linux-x64\.tar\.gz$'
  echo "==> [prereq] Querying GitHub API for latest release of $REPO"
  URL="$(curl -fsSL --max-time 30 -H "User-Agent: rotz-dotfiles-bootstrap" \
      "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed -E 's/.*"(https[^"]+)"/\1/' \
    | grep -E "$PATTERN" \
    | head -n1)"

  if [ -z "$URL" ]; then
    echo "[prereq] Could not find a linux-x64 tar.gz asset in the latest release of $REPO (offline? GitHub API rate-limited?)" >&2
    exit 1
  fi
  echo "==> [prereq] Resolved download URL: $URL"

  # --- Step 3: download the tarball into DOWNLOADS_DIR (guarded with a
  # timeout, kept afterwards - not deleted - so a re-run skips the download) -
  TAR_FILE_NAME="$(basename "$URL")"
  TAR_PATH="$DOWNLOADS_DIR/$TAR_FILE_NAME"
  if [ -f "$TAR_PATH" ]; then
    echo "==> [prereq] Already downloaded at $TAR_PATH - skipping download"
  else
    echo "==> [prereq] Downloading to $TAR_PATH (timeout 300s)"
    curl -fsSL --max-time 300 "$URL" -o "$TAR_PATH"
  fi
  echo "==> [prereq] $(du -h "$TAR_PATH" | cut -f1) - extracting to $DEST_DIR"

  # --- Step 4: extract ------------------------------------------------------
  mkdir -p "$DEST_DIR"
  tar -xzf "$TAR_PATH" -C "$DEST_DIR"
  chmod +x "$PWSH_BIN"

  if [ ! -x "$PWSH_BIN" ]; then
    echo "[prereq] pwsh binary not found at $PWSH_BIN after extracting - archive layout may have changed" >&2
    exit 1
  fi
  echo "==> [prereq] pwsh7 extracted successfully to $PWSH_BIN"
fi

# --- Step 5: put pwsh7 on PATH (current session + persisted) --------------
echo "==> [prereq] Adding $DEST_DIR to PATH"
case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *) export PATH="$PATH:$DEST_DIR" ;;
esac
for rc in "$HOME/.profile" "$HOME/.bashrc"; do
  [ -f "$rc" ] || touch "$rc"
  grep -qF "PATH=\"\$PATH:$DEST_DIR\"" "$rc" 2>/dev/null || printf '\nexport PATH="$PATH:%s"\n' "$DEST_DIR" >> "$rc"
done

echo "==> [prereq] pwsh7 executable: $PWSH_BIN"
if ! PWSH_VERSION="$("$PWSH_BIN" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>&1)"; then
  cat >&2 <<EOF
[prereq] pwsh7 downloaded but failed to run. Output was:
$PWSH_VERSION

This is usually a missing shared library on minimal distros (commonly
libicu). Try: sudo apt-get install -y libicu-dev  (or the libicuXX package
matching your distro), then re-run this script.
EOF
  exit 1
fi
echo "==> [prereq] pwsh7 version: $PWSH_VERSION"

# --- Step 6: hand off to the unified bootstrap script, running under pwsh7 -
MAIN_SCRIPT="$REPO_ROOT/bootstrap/bootstrap.ps1"
echo "==> [prereq] Handing off to $MAIN_SCRIPT (now running under pwsh7)"
exec "$PWSH_BIN" -NoProfile -File "$MAIN_SCRIPT"
