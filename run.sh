#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Wine Game Launcher — Generic
#
# Usage: ./run.sh <prefix-name> "/path/to/game.exe"
#
# Features:
#   - Auto-detects GPU: NVIDIA (XWayland + GLX) or Intel/AMD (Wayland EGL)
#   - Launches from exe's parent directory (fixes games with relative paths)
#   - Kills previous instances before launching
#   - Fullscreen with no window decorations
#
# Examples:
#   ./run.sh shooterspool "$HOME/.local/share/wine-shooterspool/drive_c/..."
#   ./run.sh my-game "/path/to/Game.exe"
# =============================================================================

NAME="${1:?Usage: run.sh <prefix-name> \"/path/to/game.exe\"}"
EXE_PATH="${2:?Usage: run.sh <prefix-name> \"/path/to/game.exe\"}"
EXE_PATH="$(realpath "$EXE_PATH")"

# --- Constants ----------------------------------------------------------------
PREFIX="$HOME/.local/share/wine-$NAME"
WINE="/opt/wine-stable/bin/wine"
WINESERVER="/opt/wine-stable/bin/wineserver"
GAME_BIN="$(dirname "$EXE_PATH")"
GAME_EXE="$(basename "$EXE_PATH")"

# --- Validate -----------------------------------------------------------------
[[ -x "$WINE" ]]    || { echo "ERROR: Wine not found at $WINE — run setup.sh first"; exit 1; }
[[ -d "$PREFIX" ]]   || { echo "ERROR: Prefix not found: $PREFIX — run setup.sh $NAME first"; exit 1; }
[[ -f "$EXE_PATH" ]] || { echo "ERROR: Exe not found: $EXE_PATH"; exit 1; }

# --- Detect GPU and display ---------------------------------------------------
GPU_ENV=()
GPU_NAME="unknown"

if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    # NVIDIA detected — use XWayland + GLX for GPU acceleration
    GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'NVIDIA')"
    if [[ -z "${DISPLAY:-}" ]]; then
        DISPLAY="${GNOME_SETUP_DISPLAY:-:1}"
    fi
    GPU_ENV=(
        DISPLAY="$DISPLAY"
        __NV_PRIME_RENDER_OFFLOAD=1
        __GLX_VENDOR_LIBRARY_NAME=nvidia
    )
    DISPLAY_MODE="XWayland ($DISPLAY) → NVIDIA GLX"
else
    # Intel/AMD — use native Wayland
    unset DISPLAY 2>/dev/null || true
    DISPLAY_MODE="native Wayland (${WAYLAND_DISPLAY:-wayland-0})"
    GPU_ENV=(
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    )
fi

# --- Cleanup previous instances -----------------------------------------------
WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true
sleep 1

# --- Launch from exe's directory (fixes games with relative paths) ------------
echo "Launching $GAME_EXE..."
echo "  Prefix:  wine-$NAME"
echo "  CWD:     $GAME_BIN"
echo "  Display: $DISPLAY_MODE"
echo "  GPU:     $GPU_NAME"

cd "$GAME_BIN"
exec env \
    "${GPU_ENV[@]}" \
    WINEPREFIX="$PREFIX" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    WINEDEBUG=-all \
    "$WINE" "./$GAME_EXE"
