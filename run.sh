#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ShootersPool Online — Launch (Wine 11 + Native Wayland)
#
# CRITICAL: The game must be launched from its bin/ directory.
#   It uses relative path "..\\data\\" to find assets.
#   Wrong CWD = VC++ Runtime Error (files not found).
#
# The DISPLAY env var is deliberately unset to force Wine to use
# winewayland.so (native Wayland) instead of XWayland.
#
# Usage: ./run.sh
# =============================================================================

# --- Constants ----------------------------------------------------------------
PREFIX="$HOME/.local/share/shooterspool"
WINE="/opt/wine-stable/bin/wine"
WINESERVER="/opt/wine-stable/bin/wineserver"
GAME_BIN="$PREFIX/drive_c/Program Files (x86)/ShootersPool/bin"
GAME_EXE="ShootersPool Online.exe"

# --- Validate -----------------------------------------------------------------
[[ -x "$WINE" ]]             || { echo "ERROR: Wine not found at $WINE — run install.sh first"; exit 1; }
[[ -d "$PREFIX" ]]            || { echo "ERROR: Prefix not found at $PREFIX — run install.sh first"; exit 1; }
[[ -f "$GAME_BIN/$GAME_EXE" ]] || {
    # Try alternate location
    ALT="$PREFIX/drive_c/Program Files/ShootersPool/bin"
    [[ -f "$ALT/$GAME_EXE" ]] && GAME_BIN="$ALT" || { echo "ERROR: Game exe not found — run install.sh first"; exit 1; }
}

# --- Cleanup previous instances -----------------------------------------------
WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true
sleep 1

# --- Launch from bin/ directory (CRITICAL for relative path resolution) --------
echo "Launching ShootersPool Online..."
echo "  CWD: $GAME_BIN"
echo "  Wayland: ${WAYLAND_DISPLAY:-wayland-0}"

cd "$GAME_BIN"
exec env -u DISPLAY \
    WINEPREFIX="$PREFIX" \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    WINEDEBUG=-all \
    "$WINE" "./$GAME_EXE"
