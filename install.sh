#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WiFi Site Blocker Installation${NC}"
echo "================================"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo${NC}"
    echo "Usage: sudo ./install.sh"
    exit 1
fi

# Get the real user (not root when using sudo)
REAL_USER="${SUDO_USER:-$USER}"

echo "Installing WiFi Site Blocker..."
echo ""

# Step 1: Create default settings.json if it doesn't exist
if [ ! -f "$SCRIPT_DIR/settings.json" ]; then
    echo "→ Creating default settings.json..."
    cat > "$SCRIPT_DIR/settings.json" <<'EOF'
{
  "network_specific_blocking": {
    "ssids": [
      "YourHomeWiFi",
      "YourOfficeWiFi"
    ],
    "sites": [
      "example.com",
      "distractingsite.com"
    ]
  },
  "always_block": {
    "sites": []
  }
}
EOF
    chown "$REAL_USER" "$SCRIPT_DIR/settings.json"
    echo -e "${YELLOW}  ⚠ Default settings.json created. Please edit it to configure your SSIDs and sites to block.${NC}"
fi

# Step 2: Copy script to /usr/local/bin
echo "→ Installing script to /usr/local/bin..."
mkdir -p /usr/local/bin
cp "$SCRIPT_DIR/site-blocker.sh" /usr/local/bin/site-blocker.sh
chmod +x /usr/local/bin/site-blocker.sh
chown root:wheel /usr/local/bin/site-blocker.sh

# Step 3: Copy settings file to /usr/local/etc
echo "→ Installing settings file..."
mkdir -p /usr/local/etc/wifi-site-blocker
cp "$SCRIPT_DIR/settings.json" /usr/local/etc/wifi-site-blocker/settings.json
chmod 644 /usr/local/etc/wifi-site-blocker/settings.json
chown root:wheel /usr/local/etc/wifi-site-blocker/settings.json

# Step 4: Update script to point to installed settings file
echo "→ Updating script configuration..."
sed -i '' "s|SETTINGS_FILE=\"\$SCRIPT_DIR/settings.json\"|SETTINGS_FILE=\"/usr/local/etc/wifi-site-blocker/settings.json\"|" /usr/local/bin/site-blocker.sh

# Step 5: Copy LaunchDaemon plist
echo "→ Installing LaunchDaemon..."
cp "$SCRIPT_DIR/com.wifi-site-blocker.plist" /Library/LaunchDaemons/com.wifi-site-blocker.plist
chmod 644 /Library/LaunchDaemons/com.wifi-site-blocker.plist
chown root:wheel /Library/LaunchDaemons/com.wifi-site-blocker.plist

# Step 6: Unload old service if it exists
launchctl bootout system/com.youtube-blocker 2>/dev/null || true
launchctl bootout system/com.wifi-site-blocker 2>/dev/null || true

# Clean up old installation files
rm -f /usr/local/bin/youtube-blocker.sh
rm -f /Library/LaunchDaemons/com.youtube-blocker.plist

# Step 7: Load the LaunchDaemon
echo "→ Starting service..."
launchctl bootstrap system /Library/LaunchDaemons/com.wifi-site-blocker.plist

# Step 8: Run the script once to check current network
echo "→ Checking current network..."
/usr/local/bin/site-blocker.sh

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "WiFi Site Blocker is now active. It will:"
echo "  • Block sites based on your settings.json configuration"
echo "  • Monitor WiFi changes automatically"
echo "  • Start automatically on boot"
echo ""
echo "Configuration file: /usr/local/etc/wifi-site-blocker/settings.json"
echo "Edit the settings file and run 'sudo launchctl kickstart -k system/com.wifi-site-blocker' to apply changes"
echo ""
echo "To uninstall, run: sudo ./uninstall.sh"
echo "Check logs at: /tmp/wifi-site-blocker.log"
