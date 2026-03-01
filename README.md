Run Windows games on Linux via Wine 11, with automatic GPU detection for hybrid NVIDIA/Intel setups.

---

## Quick Start: ShootersPool Online

```bash
# 1. Install the game (run once)
./games/shooterspool.sh /path/to/ShootersPool-*_Setup.exe

# 2. Launch
./run.sh shooterspool "$HOME/.local/share/wine-shooterspool/drive_c/Program Files (x86)/ShootersPool/bin/ShootersPool Online.exe"
```

The installer script handles everything: Wine setup, the NSIS installer, binary patching, symlinks, and graphics config.

---

## Scripts

### `setup.sh <prefix-name> [--clean]`

Creates a 64-bit Wine prefix at `~/.local/share/wine-<prefix-name>`.

What it does:
- Installs Wine 11 stable from WineHQ if not already present
- Initializes a `win64` prefix
- Configures X11 and Wayland drivers with no window decorations
- Installs winetricks and Windows core fonts

Pass `--clean` to wipe and recreate the prefix from scratch. Safe to run multiple times otherwise.

```bash
./setup.sh my-game
./setup.sh my-game --clean
```

### `run.sh <prefix-name> "/path/to/game.exe"`

Generic launcher for any game installed into a Wine prefix.

What it does:
- Detects GPU (see GPU Detection below)
- Kills any previous Wine instances for the prefix
- `cd`s into the exe's parent directory before launching (critical for games that use relative paths)
- Runs with `WINEDEBUG=-all` to suppress noise

```bash
./run.sh shooterspool "$HOME/.local/share/wine-shooterspool/drive_c/Program Files (x86)/ShootersPool/bin/ShootersPool Online.exe"
```

### `games/shooterspool.sh /path/to/ShootersPool-*_Setup.exe`

ShootersPool-specific installer. Calls `setup.sh shooterspool --clean`, then applies four fixes:

1. **NSIS installer** -- tries silent `/S` flag first, falls back to GUI with a 120-second timeout
2. **Binary patch** -- replaces `steam=1` with `steam=0` in the exe to bypass Steam auth
3. **Case-sensitivity symlink** -- creates `data -> Data` in the game directory so Linux can find the assets
4. **`gfx.ini`** -- writes fullscreen graphics config to `drive_c/users/<you>/AppData/Roaming/ShootersPool/settings/gfx.ini`, auto-detecting resolution via `xrandr` (defaults to 2560x1440@165Hz if detection fails)

---

## GPU Detection

`run.sh` checks for `nvidia-smi` at launch:

**NVIDIA detected:**
- Uses XWayland (`DISPLAY=:1` or `$GNOME_SETUP_DISPLAY`)
- Sets `__NV_PRIME_RENDER_OFFLOAD=1` and `__GLX_VENDOR_LIBRARY_NAME=nvidia`
- Renders via GLX on the discrete GPU

**No NVIDIA (Intel/AMD):**
- Unsets `DISPLAY`, uses native Wayland (`WAYLAND_DISPLAY=wayland-0`)
- Renders via EGL on the integrated GPU

This means on a hybrid laptop, the game always runs on the NVIDIA GPU when it's available.

---

## Tested Configurations

| Wine build | Result | Why |
|---|---|---|
| Wine 11 stable (WineHQ) | Works | Vanilla WGL, compatible with CEGUIOpenGLRenderer |
| Wine-GE | Fails | WGL patches break OpenGL pixel format negotiation |
| Proton-GE | Fails | Same root cause as Wine-GE |

Wine-GE and Proton-GE both produce `Can't find a suitable pixel format` at launch. This is a known conflict between their custom WGL patches and games using CEGUIOpenGLRenderer for OpenGL rendering. Vanilla Wine 11 is the only working option for this game.

---

## Key Discoveries

**CWD requirement.** The game exe must be launched from its `bin/` directory. It resolves assets via relative paths (`../data/`), so launching from any other directory causes it to fail silently or crash.

**OpenGL pixel format.** The `Can't find a suitable pixel format` error is not a driver or system issue. It's caused by Wine-GE/Proton-GE's WGL patches conflicting with CEGUIOpenGLRenderer. Switching to vanilla Wine 11 fixes it entirely.

**Hybrid GPU behavior.** On a system with both Intel iGPU and NVIDIA dGPU, Wine under native Wayland uses the Intel GPU. XWayland with PRIME offload is required to reach the NVIDIA GPU. The launcher handles this automatically.

**Steam auth.** The game binary contains a `steam=1` flag that causes it to attempt Steam authentication. Patching it to `steam=0` lets it run standalone.

**Linux case-sensitivity.** The installer creates a `Data/` directory. The game references it as `data/`. A `data -> Data` symlink resolves this without touching any game files.

---

## Adding a New Game

Create `games/<name>.sh`. The pattern is:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="${1:?Usage: games/<name>.sh /path/to/installer.exe}"
INSTALLER="$(realpath "$INSTALLER")"

NAME="<name>"
PREFIX="$HOME/.local/share/wine-$NAME"
WINE="/opt/wine-stable/bin/wine"
WINESERVER="/opt/wine-stable/bin/wineserver"

# 1. Generic Wine setup
"$SCRIPT_DIR/setup.sh" "$NAME" --clean

# 2. Run installer
env -u DISPLAY WINEPREFIX="$PREFIX" "$WINE" "$INSTALLER" /S 2>/dev/null
"$WINESERVER" -w 2>/dev/null || true

GAME_EXE="$PREFIX/drive_c/Program Files (x86)/<GameDir>/Game.exe"

# 3. Any game-specific fixes go here
#    - binary patches (sed -i)
#    - symlinks (ln -s)
#    - config files (cat > ...)

echo "Launch with:"
echo "  ./run.sh $NAME \"$GAME_EXE\""
```

Then launch with:

```bash
./run.sh <name> "/path/to/Game.exe"
```

The only hard requirement from `run.sh` is that the exe path is absolute and the file exists. Everything else (GPU detection, CWD, prefix lookup) is handled automatically.

---

## System

Tested on: Ubuntu, vanilla GNOME on Wayland, Intel iGPU + NVIDIA RTX 5070 Laptop GPU.
