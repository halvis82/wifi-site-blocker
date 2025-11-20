#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WiFi Site Blocker Uninstallation${NC}"
echo "================================"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo${NC}"
    echo "Usage: sudo ./uninstall.sh"
    exit 1
fi

echo "Removing WiFi Site Blocker..."
echo ""

# Step 1: Unload the LaunchDaemon
echo "→ Stopping service..."
launchctl bootout system/com.youtube-blocker 2>/dev/null || true
launchctl bootout system/com.wifi-site-blocker 2>/dev/null || true

# Step 2: Remove LaunchDaemon plist
echo "→ Removing LaunchDaemon..."
rm -f /Library/LaunchDaemons/com.youtube-blocker.plist
rm -f /Library/LaunchDaemons/com.wifi-site-blocker.plist

# Step 3: Remove script
echo "→ Removing script..."
rm -f /usr/local/bin/youtube-blocker.sh
rm -f /usr/local/bin/site-blocker.sh

# Step 4: Remove settings
echo "→ Removing settings..."
rm -rf /usr/local/etc/wifi-site-blocker

# Step 5: Remove site blocking from hosts file
echo "→ Cleaning up hosts file..."
MARKER_START_OLD="# YOUTUBE-BLOCKER-START"
MARKER_END_OLD="# YOUTUBE-BLOCKER-END"
MARKER_START_NEW="# WIFI-SITE-BLOCKER-START"
MARKER_END_NEW="# WIFI-SITE-BLOCKER-END"

# Remove old markers
if grep -q "$MARKER_START_OLD" /etc/hosts 2>/dev/null; then
    sed -i.bak "/$MARKER_START_OLD/,/$MARKER_END_OLD/d" /etc/hosts
fi

# Remove new markers
if grep -q "$MARKER_START_NEW" /etc/hosts 2>/dev/null; then
    sed -i.bak "/$MARKER_START_NEW/,/$MARKER_END_NEW/d" /etc/hosts
fi

dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
discoveryutil mdnsflushcache 2>/dev/null || true
discoveryutil udnsflushcaches 2>/dev/null || true

# Step 6: Remove logs
echo "→ Removing logs..."
rm -f /tmp/youtube-blocker.log
rm -f /tmp/youtube-blocker-error.log
rm -f /tmp/wifi-site-blocker.log
rm -f /tmp/wifi-site-blocker-error.log

echo ""
echo -e "${GREEN}✓ Uninstallation complete!${NC}"
echo ""
echo "WiFi Site Blocker has been completely removed from your system."
