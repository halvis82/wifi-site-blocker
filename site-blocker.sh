#!/bin/bash

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SETTINGS_FILE="$SCRIPT_DIR/settings.json"
HOSTS_FILE="/etc/hosts"
MARKER_START="# WIFI-SITE-BLOCKER-START"
MARKER_END="# WIFI-SITE-BLOCKER-END"

# Function to get current SSID
get_current_ssid() {
    system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{getline; gsub(/^[ \t]+|:$/, ""); print; exit}'
}

# Function to check if blocking is active in hosts file
is_blocking_active() {
    grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null
}

# Function to read settings from JSON file
read_settings() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo "Error: Settings file not found at $SETTINGS_FILE"
        exit 1
    fi

    # Read JSON using python3 (available on macOS by default)
    python3 -c "
import json
import sys

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

# Print SSIDs (one per line)
print('SSIDS_START')
for ssid in settings['network_specific_blocking']['ssids']:
    print(ssid)
print('SSIDS_END')

# Print network-specific sites (one per line)
print('NETWORK_SITES_START')
for site in settings['network_specific_blocking']['sites']:
    print(site)
print('NETWORK_SITES_END')

# Print always-block sites (one per line)
print('ALWAYS_SITES_START')
for site in settings['always_block']['sites']:
    print(site)
print('ALWAYS_SITES_END')
"
}

# Function to parse settings output
parse_settings() {
    local settings_output="$1"
    local mode=""

    while IFS= read -r line; do
        case "$line" in
            "SSIDS_START") mode="ssids" ;;
            "SSIDS_END") mode="" ;;
            "NETWORK_SITES_START") mode="network_sites" ;;
            "NETWORK_SITES_END") mode="" ;;
            "ALWAYS_SITES_START") mode="always_sites" ;;
            "ALWAYS_SITES_END") mode="" ;;
            *)
                if [ -n "$mode" ]; then
                    case "$mode" in
                        "ssids") BLOCKING_SSIDS+=("$line") ;;
                        "network_sites") NETWORK_SITES+=("$line") ;;
                        "always_sites") ALWAYS_SITES+=("$line") ;;
                    esac
                fi
                ;;
        esac
    done <<< "$settings_output"
}

# Function to add site blocking to hosts file
enable_blocking() {
    local sites_to_block=("$@")

    if [ ${#sites_to_block[@]} -eq 0 ]; then
        echo "No sites to block"
        return
    fi

    if is_blocking_active; then
        echo "Blocking already active, updating..."
        disable_blocking
    fi

    echo "Enabling site blocking..."

    # Create temporary file with blocking entries
    TEMP_FILE=$(mktemp)
    echo "$MARKER_START" > "$TEMP_FILE"

    for domain in "${sites_to_block[@]}"; do
        echo "0.0.0.0 $domain" >> "$TEMP_FILE"
        # Also block www. version if not already specified
        if [[ ! "$domain" =~ ^www\. ]]; then
            echo "0.0.0.0 www.$domain" >> "$TEMP_FILE"
        fi
    done

    echo "$MARKER_END" >> "$TEMP_FILE"

    # Append to hosts file
    cat "$TEMP_FILE" >> "$HOSTS_FILE"
    rm "$TEMP_FILE"

    # Flush DNS cache
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null

    echo "Blocking enabled for ${#sites_to_block[@]} sites"
}

# Function to remove site blocking from hosts file
disable_blocking() {
    if ! is_blocking_active; then
        return
    fi

    echo "Disabling site blocking..."

    # Remove lines between markers
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

    # Flush DNS cache
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null

    echo "Blocking removed"
}

# Main logic
CURRENT_SSID=$(get_current_ssid)

# Read settings
declare -a BLOCKING_SSIDS
declare -a NETWORK_SITES
declare -a ALWAYS_SITES

settings_output=$(read_settings)
parse_settings "$settings_output"

# Determine which sites to block
declare -a SITES_TO_BLOCK

# Always add the always-block sites
SITES_TO_BLOCK+=("${ALWAYS_SITES[@]}")

# Check if we're on a blocking SSID
on_blocking_network=false
for ssid in "${BLOCKING_SSIDS[@]}"; do
    if [ "$CURRENT_SSID" = "$ssid" ]; then
        on_blocking_network=true
        break
    fi
done

# If on blocking network, add network-specific sites
if [ "$on_blocking_network" = true ]; then
    SITES_TO_BLOCK+=("${NETWORK_SITES[@]}")
    echo "On blocking network: $CURRENT_SSID"
fi

# Enable or disable blocking based on sites list
if [ ${#SITES_TO_BLOCK[@]} -gt 0 ]; then
    enable_blocking "${SITES_TO_BLOCK[@]}"
else
    disable_blocking
fi
