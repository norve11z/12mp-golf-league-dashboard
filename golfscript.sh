#!/bin/bash

# ================================
# Minigolf Kiosk One-Time Installer
# ================================

set -e  # Exit on any error

# Get the folder where this script lives (should contain score.html)
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8000
KIOSK_SCRIPT="$APP_DIR/start-kiosk.sh"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/minigolf.service"

echo "=========================================="
echo "  Minigolf Kiosk Installer"
echo "=========================================="
echo "App directory: $APP_DIR"
echo ""

# ---- Sanity check ----
if [ ! -f "$APP_DIR/score.html" ]; then
    echo "❌ ERROR: score.html not found in $APP_DIR"
    echo "   Place this installer in the same folder as score.html and try again."
    exit 1
fi

# ---- Check for python3 ----
if ! command -v python3 &>/dev/null; then
    echo "❌ ERROR: python3 is not installed."
    echo "   Install it with: sudo apt install python3"
    exit 1
fi

# ---- Check for a browser ----
BROWSER=""
for b in chromium-browser chromium google-chrome firefox; do
    if command -v "$b" &>/dev/null; then
        BROWSER="$b"
        break
    fi
done
if [ -z "$BROWSER" ]; then
    echo "❌ ERROR: No supported browser found (chromium, chrome, or firefox)."
    echo "   Install one: sudo apt install chromium-browser"
    exit 1
fi
echo "✅ Found browser: $BROWSER"

# ---- Create the kiosk launcher script ----
echo "📝 Creating $KIOSK_SCRIPT ..."
cat > "$KIOSK_SCRIPT" <<EOF
#!/bin/bash
APP_DIR="$APP_DIR"
PORT=$PORT
URL="http://localhost:\$PORT/score.html"

cd "\$APP_DIR"

# Prevent screen blanking (ignore errors if X isn't available)
xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

# Kill any existing server on this port
fuser -k \$PORT/tcp 2>/dev/null
sleep 1

# Start the web server in the background
python3 -m http.server \$PORT >/dev/null 2>&1 &
SERVER_PID=\$!

# Wait for server to be ready
sleep 2

# Launch browser in kiosk mode
if command -v chromium-browser &>/dev/null; then
    chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble --disable-features=TranslateUI --no-first-run "\$URL"
elif command -v chromium &>/dev/null; then
    chromium --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble "\$URL"
elif command -v google-chrome &>/dev/null; then
    google-chrome --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble "\$URL"
elif command -v firefox &>/dev/null; then
    firefox --kiosk "\$URL"
fi

# Cleanup when browser closes
kill \$SERVER_PID 2>/dev/null
EOF

chmod +x "$KIOSK_SCRIPT"
echo "✅ Launcher script created and made executable"

# ---- Create the systemd user service ----
echo "📝 Creating systemd user service ..."
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Minigolf Scoreboard Kiosk
After=graphical-session.target

[Service]
Type=simple
ExecStart=$KIOSK_SCRIPT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

echo "✅ Service file created at $SERVICE_FILE"

# ---- Enable and start the service ----
echo "🔄 Enabling service ..."
systemctl --user daemon-reload
systemctl --user enable minigolf.service

# ---- Enable lingering so it can run without login ----
if command -v loginctl &>/dev/null; then
    echo "🔧 Enabling user lingering (allows service to run on boot before login)..."
    loginctl enable-linger "$USER" 2>/dev/null || echo "   (Skipped — may require sudo. Run 'sudo loginctl enable-linger $USER' manually if needed.)"
fi

# ---- Also create a desktop autostart entry as backup ----
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/minigolf.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Minigolf Kiosk
Exec=$KIOSK_SCRIPT
X-GNOME-Autostart-enabled=true
Terminal=false
EOF
echo "✅ Desktop autostart entry created (backup method)"

echo ""
echo "=========================================="
echo "  ✅ Installation Complete!"
echo "=========================================="
echo ""
echo "USEFUL COMMANDS:"
echo ""
echo "  Start now:        systemctl --user start minigolf.service"
echo "  Stop:             systemctl --user stop minigolf.service"
echo "  Status:           systemctl --user status minigolf.service"
echo "  View logs:        journalctl --user -u minigolf.service -f"
echo "  Disable autostart: systemctl --user disable minigolf.service"
echo "  Uninstall:        $APP_DIR/uninstall-minigolf.sh"
echo ""
echo "  Manual launch:    $KIOSK_SCRIPT"
echo ""
echo "  Exit kiosk mode:  Ctrl+F4 or Alt+F4"
echo ""

# ---- Create uninstaller ----
cat > "$APP_DIR/uninstall-minigolf.sh" <<EOF
#!/bin/bash
echo "Uninstalling Minigolf Kiosk..."
systemctl --user stop minigolf.service 2>/dev/null
systemctl --user disable minigolf.service 2>/dev/null
rm -f "$SERVICE_FILE"
rm -f "$AUTOSTART_DIR/minigolf.desktop"
systemctl --user daemon-reload
echo "✅ Uninstalled. (Your score.html and start-kiosk.sh were NOT deleted.)"
EOF
chmod +x "$APP_DIR/uninstall-minigolf.sh"

# ---- Ask to start now ----
read -p "Start the kiosk right now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl --user start minigolf.service
    echo "🚀 Started! The browser should open in a moment."
fi
