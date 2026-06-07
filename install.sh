#!/usr/bin/env bash
# install.sh — download basyn into /opt/basyn and symlink into /usr/local/sbin
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/stvorl/basyn/master/install.sh | sudo bash
#
# To update later:
#   sudo /opt/basyn/install.sh
#
# Files to install are listed in install.lst.  Add or remove entries there;
# this script stays untouched.

set -euo pipefail

# === Configuration ===
GH_USER="stvorl"
GH_REPO="basyn"
GH_BRANCH="master"
RAW="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/$GH_BRANCH"

DEST="/opt/basyn"
BIN_DIR="/usr/local/sbin"
SELF="install.sh"
LIST="install.lst"

# === Pre-flight checks (run regardless of phase) ===

if [[ "$(id -u)" != "0" ]]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is not installed."
    echo "Install it with your package manager, e.g.:"
    echo "  apt install python3       (Debian/Ubuntu)"
    echo "  yum install python3       (RHEL/CentOS)"
    echo "  pacman -S python          (Arch)"
    exit 1
fi

echo "python3 found: $(python3 --version)"

if ! command -v curl &>/dev/null; then
    echo "ERROR: curl is not installed."
    echo "Install it with your package manager, e.g.:"
    echo "  apt install curl          (Debian/Ubuntu)"
    echo "  yum install curl          (RHEL/CentOS)"
    echo "  pacman -S curl            (Arch)"
    exit 1
fi

if [[ ! -d "$BIN_DIR" ]]; then
    echo "Target directory $BIN_DIR does not exist, creating..."
    mkdir -p "$BIN_DIR"
fi

# === Determine phase: are we already inside DEST? ===
# When piped via curl|bash there is no source file → definitely Phase 1.
if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR=""
else
    SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
fi

if [[ "$SCRIPT_DIR" != "$DEST" ]]; then
    # ============================================================
    # PHASE 1: we are NOT in DEST (first run, piped from curl)
    # ============================================================
    echo "==> Phase 1: bootstrapping into $DEST..."

    mkdir -p "$DEST"

    echo "==> Downloading $SELF into $DEST..."
    curl -fsSL "$RAW/$SELF" -o "$DEST/$SELF"
    chmod +x "$DEST/$SELF"

    echo "==> Launching phase 2 from $DEST..."
    exec "$DEST/$SELF"
    # exec replaces the current process — code below never runs
fi

# ============================================================
# PHASE 2: we are already inside DEST
# ============================================================

echo "==> Phase 2: updating files in $DEST..."

# --- Download the file list ---
echo "==> Fetching $LIST..."
curl -fsSL "$RAW/$LIST" -o "$DEST/$LIST"

# --- Download / update every file from the list ---
while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue

    read -r mode filename <<< "$line"
    [[ -z "$mode" || -z "$filename" ]] && continue

    echo "==> Downloading $filename (mode $mode)..."
    curl -fsSL "$RAW/$filename" -o "$DEST/$filename"
    chmod "$mode" "$DEST/$filename"

    # If the file has any executable bit, ensure a symlink in BIN_DIR
    dst="$BIN_DIR/$filename"
    if (( mode & 0111 )); then
        if [[ ! -L "$dst" ]] || [[ "$(readlink "$dst")" != "$DEST/$filename" ]]; then
            echo "==> Symlink: $dst -> $DEST/$filename"
            rm -f "$dst"
            ln -s "$DEST/$filename" "$dst"
        else
            echo "    Symlink OK: $dst"
        fi
    fi
done < "$DEST/$LIST"

echo ""
echo "==> Installation complete."
echo "    Files in $DEST:"
ls -la "$DEST"
