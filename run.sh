#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ShootersPool Online — Launch (Wine 11 + NVIDIA GPU via XWayland)
#
# CRITICAL: The game must be launched from its parent directory.
#   It uses relative path "..\\data\\" to find assets.
#   Wrong CWD = VC++ Runtime Error (files not found).
#
# Uses XWayland (DISPLAY) + NVIDIA GLX for maximum GPU acceleration.
# Wine's native Wayland driver only supports Mesa EGL (Intel/AMD).
# NVIDIA proprietary requires GLX which only works through XWayland.
# XWayland runs within your Wayland session — not a separate X server.
#
# Usage: ./run.sh "/path/to/ShootersPool Online.exe"
# =============================================================================

EXE_PATH="${1:?Usage: run.sh \"/path/to/ShootersPool Online.exe\"}"
EXE_PATH="$(realpath "$EXE_PATH")"

# --- Constants ----------------------------------------------------------------
PREFIX="$HOME/.local/share/shooterspool"
WINE="/opt/wine-stable/bin/wine"
WINESERVER="/opt/wine-stable/bin/wineserver"
GAME_BIN="$(dirname "$EXE_PATH")"
GAME_EXE="$(basename "$EXE_PATH")"

# --- Validate -----------------------------------------------------------------
[[ -x "$WINE" ]]    || { echo "ERROR: Wine not found at $WINE — run install.sh first"; exit 1; }
[[ -d "$PREFIX" ]]   || { echo "ERROR: Prefix not found at $PREFIX — run install.sh first"; exit 1; }
[[ -f "$EXE_PATH" ]] || { echo "ERROR: Exe not found: $EXE_PATH"; exit 1; }

# --- Detect XWayland display --------------------------------------------------
if [[ -z "${DISPLAY:-}" ]]; then
    DISPLAY="${GNOME_SETUP_DISPLAY:-:1}"
fi

# --- Cleanup previous instances -----------------------------------------------
WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true
sleep 1

# --- Launch from exe's directory (CRITICAL for relative path resolution) ------
echo "Launching $GAME_EXE..."
echo "  CWD:     $GAME_BIN"
echo "  Display: $DISPLAY (XWayland → NVIDIA GLX)"
echo "  GPU:     $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'unknown')"

cd "$GAME_BIN"
exec env \
    DISPLAY="$DISPLAY" \
    WINEPREFIX="$PREFIX" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    __NV_PRIME_RENDER_OFFLOAD=1 \
    __GLX_VENDOR_LIBRARY_NAME=nvidia \
    WINEDEBUG=-all \
    "$WINE" "./$GAME_EXE"
