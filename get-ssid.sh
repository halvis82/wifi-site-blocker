#!/bin/bash
# Try multiple methods to get SSID

# Method 1: wdutil (requires root, available on Sequoia)
SSID=$(wdutil info 2>/dev/null | grep -E '^\s+SSID\s+:' | awk -F': ' '{print $2}' | head -1)
if [ -n "$SSID" ] && [ "$SSID" != "<redacted>" ]; then
    echo "$SSID"
    exit 0
fi

# Method 2: networksetup
SSID=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')
if [ -n "$SSID" ] && [ "$SSID" != "You are not associated with an AirPort network." ]; then
    echo "$SSID"
    exit 0
fi

# Method 3: system_profiler (often redacted on Sequoia)
SSID=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{getline; gsub(/^[ \t]+|:$/, ""); print; exit}')
if [ -n "$SSID" ] && [ "$SSID" != "<redacted>" ]; then
    echo "$SSID"
    exit 0
fi

# Method 4: ipconfig
SSID=$(ipconfig getsummary en0 2>/dev/null | grep ' SSID' | awk -F' : ' '{print $2}')
if [ -n "$SSID" ] && [ "$SSID" != "<redacted>" ]; then
    echo "$SSID"
    exit 0
fi

echo "NO_SSID"
