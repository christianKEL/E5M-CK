#!/bin/sh
# ============================================================
# install_screenshot.sh
# Installs the Nebula Pad screenshot macro for Klipper/Fluidd
# Auto-detects Guppy Screen for portrait/landscape orientation
# Screenshots are saved in config/ folder, accessible via Fluidd
# Tested on: Creality Ender 5 Max — Nebula Pad — Klipper
# Signature: E5M DOC CK — Christian KELHETTER
# v1.3 — March 2026
# ============================================================

CONFIG_DIR="/usr/data/printer_data/config"
SCREENSHOT_CFG="$CONFIG_DIR/screenshot.cfg"
PRINTER_CFG="$CONFIG_DIR/printer.cfg"
SHELL_CMD_SRC="https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/gcode-shell-command/gcode_shell_command.py"
SHELL_CMD_DEST="/usr/share/klipper/klippy/extras/gcode_shell_command.py"
INCLUDE_LINE="[include screenshot.cfg] # E5M DOC CK - Nebula Pad Screenshot macro"

echo ""
echo "============================================================"
echo "  Nebula Pad Screenshot Macro Installer"
echo "  E5M DOC CK — Christian KELHETTER — v1.3 March 2026"
echo "============================================================"
echo ""

# ── STEP 1: Check gcode_shell_command ──────────────────────────
echo "[1/4] Checking gcode_shell_command..."

if [ -f "$SHELL_CMD_DEST" ]; then
    echo "      OK  gcode_shell_command already installed — skipping"
else
    echo "      --  Not found — downloading from Guilouz repository..."
    wget -O "$SHELL_CMD_DEST" "$SHELL_CMD_SRC"
    if [ $? -eq 0 ]; then
        echo "      OK  gcode_shell_command installed successfully"
    else
        echo ""
        echo "  ERROR: Download failed."
        echo "         Check your internet connection and try again."
        echo ""
        exit 1
    fi
fi

# ── STEP 2: Create/overwrite screenshot.cfg ────────────────────
echo "[2/4] Creating screenshot.cfg..."

if [ -f "$SCREENSHOT_CFG" ]; then
    echo "      --  screenshot.cfg already exists — overwriting"
fi

cat > "$SCREENSHOT_CFG" << 'EOF'
# ============================================================
# screenshot.cfg
# Captures the Nebula Pad screen as a properly oriented PNG
# Auto-detects display mode:
#   - Guppy Screen running -> landscape (no rotation)
#   - Stock Nebula UI      -> portrait (90 degrees clockwise rotation)
# Screenshots are saved in config/ folder, accessible via Fluidd
# Usage: run the SCREENSHOT macro from Fluidd
# E5M DOC CK - Christian KELHETTER - v1.3 March 2026
# ============================================================

[gcode_shell_command screenshot]
command: sh -c "FNAME=/usr/data/printer_data/config/screenshot_$(date +%Y%m%d_%H%M%S).png; cat /dev/fb0 > /tmp/fb.raw; if pgrep guppyscreen > /dev/null 2>&1; then ffmpeg -y -vcodec rawvideo -f rawvideo -pix_fmt bgra -s 480x272 -i /tmp/fb.raw $FNAME; else ffmpeg -y -vcodec rawvideo -f rawvideo -pix_fmt bgra -s 480x272 -i /tmp/fb.raw -vf transpose=1 $FNAME; fi; rm -f /tmp/fb.raw"
timeout: 15
verbose: True

[gcode_macro SCREENSHOT]
description: Capture Nebula Pad screen to config/ (auto portrait/landscape)
gcode:
    RESPOND TYPE=command MSG="// Taking screenshot (auto-detect mode)..."
    RUN_SHELL_COMMAND CMD=screenshot
    RESPOND TYPE=command MSG="// Screenshot saved to config/"
EOF
echo "      OK  screenshot.cfg created"

# ── STEP 3: Insert include at FIRST line of printer.cfg ────────
echo "[3/4] Checking printer.cfg include..."

if grep -q "include screenshot.cfg" "$PRINTER_CFG" 2>/dev/null; then
    echo "      OK  Include already present in printer.cfg — skipping"
else
    sed -i "1s|^|${INCLUDE_LINE}\n\n|" "$PRINTER_CFG"
    echo "      OK  Include inserted at first line of printer.cfg"
fi

# ── STEP 4: Restart Klipper then reboot ────────────────────────
echo "[4/4] Restarting Klipper then rebooting..."
echo ""
echo "============================================================"
echo "  Installation complete!"
echo "  The Nebula Pad will reboot in 5 seconds."
echo "  After reboot, use the SCREENSHOT macro in Fluidd"
echo "  to capture the Nebula Pad screen."
echo "  Screenshots are saved in: config/"
echo "  E5M DOC CK — Christian KELHETTER"
echo "============================================================"
echo ""
sleep 5
systemctl restart klipper
sleep 3
reboot
