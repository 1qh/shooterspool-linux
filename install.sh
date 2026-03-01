#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ShootersPool Online — Install (Wine 11 + Native Wayland)
#
# Usage: ./install.sh /path/to/ShootersPool-*_Setup.exe
#
# What this does:
#   1. Installs Wine 11 from WineHQ (if not present)
#   2. Creates a 64-bit Wine prefix with native Wayland support
#   3. Installs Windows core fonts (fixes CEF dwrite crash)
#   4. Runs the ShootersPool NSIS installer (GUI click-through)
#   5. Patches binary to disable Steam auth (steam=0)
#   6. Creates data→Data case-sensitivity symlink
#   7. Configures Wayland driver: no decorations
#   8. Writes gfx.ini for fullscreen at native resolution
#
# Key discoveries:
#   - Game MUST be launched from bin/ directory (uses relative ..\\data\\)
#   - Sound files (.wavx/.oggx) are encrypted, no symlinks needed
#   - Binary contains steam=1 in login URL, must be patched to steam=0
#   - Wine's Wayland driver avoids crashes that occur under X11
#   - NSIS installer /S flag works only if launched from correct path
# =============================================================================

INSTALLER="${1:?Usage: install.sh /path/to/ShootersPool_Setup.exe}"
INSTALLER="$(realpath "$INSTALLER")"

# --- Constants ----------------------------------------------------------------
PREFIX="$HOME/.local/share/shooterspool"
WINE="/opt/wine-stable/bin/wine"
WINESERVER="/opt/wine-stable/bin/wineserver"
GAME_REL="drive_c/Program Files (x86)/ShootersPool"
GAME_DIR="$PREFIX/$GAME_REL"
GAME_BIN="$GAME_DIR/bin"
GAME_EXE="$GAME_BIN/ShootersPool Online.exe"

# --- Helpers ------------------------------------------------------------------
cleanup_wine() {
    WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true
    sleep 2
}

# --- Validate -----------------------------------------------------------------
echo "=== ShootersPool Installer (Wine 11 + Wayland) ==="

[[ -f "$INSTALLER" ]] || { echo "ERROR: Installer not found: $INSTALLER"; exit 1; }

# --- 1. Install Wine 11 from WineHQ ------------------------------------------
echo "[1/8] Checking Wine 11..."
if [[ -x "$WINE" ]] && "$WINE" --version 2>/dev/null | grep -q "wine-11"; then
    echo "  Wine 11 already installed: $($WINE --version)"
else
    echo "  Adding WineHQ repository..."
    sudo dpkg --add-architecture i386
    sudo mkdir -pm755 /etc/apt/keyrings
    sudo wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
    CODENAME=$(lsb_release -cs)
    sudo wget -qNP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/${CODENAME}/winehq-${CODENAME}.sources"
    sudo apt update -qq
    echo "  Installing winehq-stable..."
    sudo apt install -y --install-recommends winehq-stable
    echo "  Wine installed: $($WINE --version)"
fi

# --- 2. Create 64-bit Wine prefix --------------------------------------------
echo "[2/8] Creating 64-bit Wine prefix..."
cleanup_wine
rm -rf "$PREFIX"
env -u DISPLAY WINEPREFIX="$PREFIX" WINEARCH=win64 "$WINE" wineboot --init 2>/dev/null
"$WINESERVER" -w 2>/dev/null || true
sleep 2
echo "  Prefix created: $PREFIX (win64)"

# --- 3. Configure Wine display drivers ----------------------------------------
echo "[3/8] Configuring Wine display..."
# X11 driver for NVIDIA GLX (primary — used by run.sh via XWayland)
env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" reg add \
    "HKCU\\Software\\Wine\\X11 Driver" /v Decorated /t REG_SZ /d N /f 2>/dev/null
env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" reg add \
    "HKCU\\Software\\Wine\\X11 Driver" /v Managed /t REG_SZ /d N /f 2>/dev/null
# Wayland driver as fallback (for Intel/AMD systems without NVIDIA)
env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" reg add \
    "HKCU\\Software\\Wine\\Wayland Driver" /v Decorated /t REG_SZ /d N /f 2>/dev/null
"$WINESERVER" -w 2>/dev/null || true
echo "  X11 + Wayland drivers configured, decorations disabled"

# --- 4. Install core fonts ---------------------------------------------------
echo "[4/8] Installing Windows core fonts..."
command -v winetricks >/dev/null || {
    echo "  Installing winetricks..."
    sudo wget -qO /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    sudo chmod +x /usr/local/bin/winetricks
}
env -u DISPLAY WINEPREFIX="$PREFIX" WINE="$WINE" winetricks -q corefonts 2>&1 | tail -3 || {
    echo "  WARN: winetricks corefonts had issues (may still work)"
}
"$WINESERVER" -w 2>/dev/null || true
echo "  Core fonts installed"

# --- 5. Run NSIS installer ----------------------------------------------------
echo "[5/8] Running game installer..."
echo "  NOTE: The NSIS installer may show a GUI. If it does, click through:"
echo "    Language → OK → Next → I Agree → Install → wait ~60s → Close"
echo "  Trying silent install first..."

env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" "$INSTALLER" /S 2>/dev/null &
INST_PID=$!

# Wait up to 120s for installer to finish
for i in $(seq 1 120); do
    if ! kill -0 "$INST_PID" 2>/dev/null; then
        break
    fi
    sleep 1
done
# If still running after 120s, it's probably waiting for GUI input
if kill -0 "$INST_PID" 2>/dev/null; then
    echo "  Silent install timed out — installer needs GUI interaction"
    echo "  Please complete the installer manually, then press Enter here"
    read -r
fi
"$WINESERVER" -w 2>/dev/null || true
sleep 3

# Verify game installed
if [[ ! -f "$GAME_EXE" ]]; then
    ALT_DIR="$PREFIX/drive_c/Program Files/ShootersPool"
    if [[ -d "$ALT_DIR" ]]; then
        GAME_DIR="$ALT_DIR"
        GAME_BIN="$GAME_DIR/bin"
        GAME_EXE="$GAME_BIN/ShootersPool Online.exe"
    fi
fi
[[ -f "$GAME_EXE" ]] || { echo "ERROR: Game exe not found after install."; exit 1; }
echo "  Installed to: $GAME_DIR"
sync  # Ensure binary is fully flushed to disk before patching

# --- 6. Patch binary: steam=1 → steam=0 --------------------------------------
echo "[6/8] Patching Steam auth bypass..."
if grep -aq 'steam=1' "$GAME_EXE"; then
    sed -i 's/steam=1/steam=0/g' "$GAME_EXE"
    echo "  Patched: steam=1 → steam=0"
elif grep -aq 'steam=0' "$GAME_EXE"; then
    echo "  Already patched"
else
    echo "  WARN: steam= string not found in binary"
fi

# --- 7. Create data→Data case-sensitivity symlink ----------------------------
echo "[7/8] Fixing case-sensitivity..."
if [[ -d "$GAME_DIR/Data" && ! -e "$GAME_DIR/data" ]]; then
    ln -s Data "$GAME_DIR/data"
    echo "  Created symlink: data → Data"
elif [[ -L "$GAME_DIR/data" ]]; then
    echo "  Symlink already exists"
else
    echo "  WARN: Data directory layout unexpected"
fi

# --- 8. Write gfx.ini --------------------------------------------------------
echo "[8/8] Configuring graphics..."
# Detect resolution
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

cleanup_wine

echo ""
echo "=== Installation complete ==="
echo "Game: $GAME_EXE"
echo "Prefix: $PREFIX"
echo "Mode: Wine 11 native Wayland, fullscreen, no decorations"
echo ""
echo "Launch with: ./run.sh"
