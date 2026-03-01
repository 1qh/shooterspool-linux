#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Wine 11 Environment Setup — Generic
#
# Usage: ./setup.sh <prefix-name>
#
# Creates a ready-to-use 64-bit Wine prefix with:
#   - Wine 11 stable from WineHQ (installed if missing)
#   - Winetricks + Windows core fonts
#   - X11 + Wayland display drivers configured (no decorations)
#
# Prefix location: ~/.local/share/wine-<prefix-name>
#
# This script is idempotent — safe to run multiple times.
# To start fresh, pass --clean to wipe the prefix first.
# =============================================================================

NAME="${1:?Usage: setup.sh <prefix-name> [--clean]}"
CLEAN=false
for arg in "$@"; do [[ "$arg" == "--clean" ]] && CLEAN=true; done

# --- Constants ----------------------------------------------------------------
PREFIX="$HOME/.local/share/wine-$NAME"
WINE="/opt/wine-stable/bin/wine"
WINESERVER="/opt/wine-stable/bin/wineserver"

# --- Helpers ------------------------------------------------------------------
cleanup_wine() {
    WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true
    sleep 2
}

step=0
total=4
step() { step=$((step + 1)); echo "[$step/$total] $1"; }

# --- Validate -----------------------------------------------------------------
echo "=== Wine Environment Setup: $NAME ==="
echo "  Prefix: $PREFIX"

if $CLEAN; then
    echo "  --clean: wiping existing prefix"
    cleanup_wine
    rm -rf "$PREFIX"
fi

# --- 1. Install Wine 11 from WineHQ ------------------------------------------
step "Checking Wine 11..."
if [[ -x "$WINE" ]] && "$WINE" --version 2>/dev/null | grep -q "wine-11"; then
    echo "  Wine 11 already installed: $("$WINE" --version)"
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
    echo "  Wine installed: $("$WINE" --version)"
fi

# --- 2. Create 64-bit Wine prefix --------------------------------------------
step "Creating 64-bit Wine prefix..."
if [[ -d "$PREFIX" && -f "$PREFIX/system.reg" ]]; then
    echo "  Prefix already exists, skipping (use --clean to recreate)"
else
    rm -rf "$PREFIX"
    env -u DISPLAY WINEPREFIX="$PREFIX" WINEARCH=win64 "$WINE" wineboot --init 2>/dev/null
    "$WINESERVER" -w 2>/dev/null || true
    sleep 2
    echo "  Prefix created: $PREFIX (win64)"
fi

# --- 3. Configure Wine display drivers ----------------------------------------
step "Configuring display drivers..."
# X11 driver for NVIDIA GLX (via XWayland)
env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" reg add \
    "HKCU\\Software\\Wine\\X11 Driver" /v Decorated /t REG_SZ /d N /f 2>/dev/null
env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" reg add \
    "HKCU\\Software\\Wine\\X11 Driver" /v Managed /t REG_SZ /d N /f 2>/dev/null
# Wayland driver as fallback (Intel/AMD)
env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" reg add \
    "HKCU\\Software\\Wine\\Wayland Driver" /v Decorated /t REG_SZ /d N /f 2>/dev/null
"$WINESERVER" -w 2>/dev/null || true
echo "  X11 + Wayland drivers: no decorations"

# --- 4. Install core fonts ---------------------------------------------------
step "Installing Windows core fonts..."
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

cleanup_wine

echo ""
echo "=== Setup complete ==="
echo "  Prefix: $PREFIX"
echo "  Wine:   $("$WINE" --version)"
echo ""
echo "Next: install your game into this prefix, then launch with:"
echo "  ./run.sh $NAME \"/path/to/game.exe\""
