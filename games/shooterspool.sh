#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ShootersPool Online — Game-Specific Installer
#
# Usage: ./games/shooterspool.sh /path/to/ShootersPool-*_Setup.exe
#
# This calls setup.sh for the generic Wine environment, then applies
# ShootersPool-specific fixes:
#   1. Runs the NSIS installer (silent, falls back to GUI)
#   2. Patches binary: steam=1 → steam=0 (bypass Steam auth)
#   3. Creates data→Data symlink (Linux case-sensitivity fix)
#   4. Writes gfx.ini for fullscreen at native resolution
#
# Key discoveries:
#   - Game MUST be launched from bin/ directory (uses relative ..\data\)
#   - Sound files (.wavx/.oggx) are encrypted — no symlinks needed
#   - Wine-GE and Proton-GE BREAK this game ("pixel format" error)
#     because their WGL patches conflict with CEGUIOpenGLRenderer
#   - Vanilla Wine 11 is the only working option for this OpenGL game
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="${1:?Usage: games/shooterspool.sh /path/to/ShootersPool_Setup.exe}"
INSTALLER="$(realpath "$INSTALLER")"

# --- Constants ----------------------------------------------------------------
NAME="shooterspool"
PREFIX="$HOME/.local/share/wine-$NAME"
WINE="/opt/wine-stable/bin/wine"
WINESERVER="/opt/wine-stable/bin/wineserver"
GAME_REL="drive_c/Program Files (x86)/ShootersPool"

# --- 1. Generic Wine setup ----------------------------------------------------
echo "=== ShootersPool Online Installer ==="
"$SCRIPT_DIR/setup.sh" "$NAME" --clean

# --- 2. Run NSIS installer ----------------------------------------------------
echo ""
echo "[Game 1/4] Running installer..."
echo "  Trying silent install first (/S flag)..."
echo "  If a GUI appears, click through: Language → OK → Next → I Agree → Install → Close"

env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" "$INSTALLER" /S 2>/dev/null &
INST_PID=$!

for i in $(seq 1 120); do
    kill -0 "$INST_PID" 2>/dev/null || break
    sleep 1
done
if kill -0 "$INST_PID" 2>/dev/null; then
    echo "  Silent install timed out — complete the installer manually, then press Enter"
    read -r
fi
"$WINESERVER" -w 2>/dev/null || true
sleep 3

# Find installed game
GAME_DIR="$PREFIX/$GAME_REL"
GAME_EXE="$GAME_DIR/bin/ShootersPool Online.exe"
if [[ ! -f "$GAME_EXE" ]]; then
    GAME_DIR="$PREFIX/drive_c/Program Files/ShootersPool"
    GAME_EXE="$GAME_DIR/bin/ShootersPool Online.exe"
fi
[[ -f "$GAME_EXE" ]] || { echo "ERROR: Game exe not found after install"; exit 1; }
echo "  Installed to: $GAME_DIR"
sync

# --- 3. Patch binary: steam=1 → steam=0 --------------------------------------
echo "[Game 2/4] Patching Steam auth bypass..."
if grep -aq 'steam=1' "$GAME_EXE"; then
    sed -i 's/steam=1/steam=0/g' "$GAME_EXE"
    echo "  Patched: steam=1 → steam=0"
elif grep -aq 'steam=0' "$GAME_EXE"; then
    echo "  Already patched"
else
    echo "  WARN: steam= string not found in binary"
fi

# --- 4. Create data→Data case-sensitivity symlink ----------------------------
echo "[Game 3/4] Fixing case-sensitivity..."
if [[ -d "$GAME_DIR/Data" && ! -e "$GAME_DIR/data" ]]; then
    ln -s Data "$GAME_DIR/data"
    echo "  Created symlink: data → Data"
elif [[ -L "$GAME_DIR/data" ]]; then
    echo "  Symlink already exists"
else
    echo "  WARN: Data directory layout unexpected"
fi

# --- 5. Write gfx.ini --------------------------------------------------------
echo "[Game 4/4] Configuring graphics..."
# Detect resolution via XWayland
RES_X=$(DISPLAY=:1 xrandr 2>/dev/null | grep '\*' | head -1 | awk '{print $1}' | cut -dx -f1 || echo "")
RES_Y=$(DISPLAY=:1 xrandr 2>/dev/null | grep '\*' | head -1 | awk '{print $1}' | cut -dx -f2 || echo "")
REFRESH=$(DISPLAY=:1 xrandr 2>/dev/null | grep '\*' | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /\*/) print $i}' | tr -d '*+' | cut -d. -f1 || echo "")
RES_X="${RES_X:-2560}"
RES_Y="${RES_Y:-1440}"
REFRESH="${REFRESH:-165}"

GFX_DIR="$PREFIX/drive_c/users/$(whoami)/AppData/Roaming/ShootersPool/settings"
mkdir -p "$GFX_DIR"
cat > "$GFX_DIR/gfx.ini" << EOF
{
    "screen_res_x_full": "$RES_X",
    "screen_res_y_full": "$RES_Y",
    "screen_res_x_win": "1280",
    "screen_res_y_win": "720",
    "colordepth": "32",
    "antialiasing": "4",
    "frequency": "$REFRESH",
    "screenMode": "1",
    "vsync": "1",
    "bloom": "0",
    "ssao": "0",
    "smaa": "0",
    "blur": "0",
    "fixedDOF": "0",
    "blurQuality": "3",
    "shadows": "1",
    "disableBackground": "0",
    "HUDscale": "1.25",
    "browserScale": "0",
    "lights": "1",
    "language": "en",
    "texTable": "4",
    "texLocation": "4",
    "texBalls": "4",
    "texCues": "4",
    "crowd": "4",
    "shTable": "4",
    "shLocation": "4",
    "shBalls": "3",
    "shCues": "4",
    "gmtTable": "4",
    "gmtLocation": "4",
    "gmtBalls": "3",
    "gmtCues": "4",
    "maxLights": "10",
    "maxLightsPerObject": "4",
    "texShadows": "4",
    "texReflections": "4",
    "texAnisotropy": "4",
    "limitFPS": "10000",
    "sndBalls": "45",
    "sndTable": "100",
    "sndCue": "42",
    "sndAmbiance": "100",
    "sndCrowd": "100",
    "sndMusicInGame": "50",
    "sndMusicMenu": "50",
    "sndReferee": "100",
    "sndMenuFx": "12"
}
EOF
echo "  gfx.ini: ${RES_X}x${RES_Y}@${REFRESH}Hz fullscreen"

WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true

echo ""
echo "=== Installation complete ==="
echo "  Game: $GAME_EXE"
echo "  Prefix: $PREFIX"
echo ""
echo "Launch with:"
echo "  ./run.sh $NAME \"$GAME_EXE\""
