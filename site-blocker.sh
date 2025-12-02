#!/bin/bash

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SETTINGS_FILE="$SCRIPT_DIR/settings.json"
HOSTS_FILE="/etc/hosts"
LAST_SSID_FILE="/tmp/wifi-site-blocker-last-ssid"
MARKER_START="# WIFI-SITE-BLOCKER-START"
MARKER_END="# WIFI-SITE-BLOCKER-END"

# Function to get current SSID
# Uses multiple methods for compatibility across macOS versions
get_current_ssid() {
    local ssid=""

    # Method 1: Extract from scutil's CachedScanRecord (works on macOS Sequoia without Location Services)
    # This extracts the SSID from the binary plist stored in the AirPort state
    ssid=$(scutil << 'SCUTILEOF' 2>/dev/null | sed -n 's/.*CachedScanRecord : <data> 0x//p' | xxd -r -p 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null | grep -A1 '</data>' | grep '<string>' | head -1 | sed 's/.*<string>//;s/<\/string>.*//'
show State:/Network/Interface/en0/AirPort
SCUTILEOF
)
    if [ -n "$ssid" ] && [ "$ssid" != "<redacted>" ]; then
        echo "$ssid"
        return
    fi

    # Method 2: networksetup (works on older macOS versions)
    ssid=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')
    if [ -n "$ssid" ] && [ "$ssid" != "You are not associated with an AirPort network." ]; then
        echo "$ssid"
        return
    fi

    # Method 3: system_profiler (fallback, often redacted on Sequoia)
    ssid=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{getline; gsub(/^[ \t]+|:$/, ""); print; exit}')
    if [ -n "$ssid" ] && [ "$ssid" != "<redacted>" ]; then
        echo "$ssid"
        return
    fi

    # No SSID found
    echo ""
}

# Function to check if blocking is active in hosts file
is_blocking_active() {
    grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null
}

# Function to get current blocked domains from hosts file
get_currently_blocked_domains() {
    if ! is_blocking_active; then
        echo ""
        return
    fi

    # Extract domains between markers (only the base domains, not subdomains or DoH servers)
    sed -n "/$MARKER_START/,/$MARKER_END/p" "$HOSTS_FILE" | \
        grep "^0.0.0.0" | \
        awk '{print $2}' | \
        grep -v "^www\." | \
        grep -v "^m\." | \
        grep -v "^mobile\." | \
        grep -v "dns\." | \
        grep -v "doh\." | \
        grep -v "cloudflare-dns" | \
        grep -v "8888.google" | \
        grep -v "1dot1dot1dot1" | \
        sort | \
        tr '\n' ' '
}

# Function to flush all DNS caches
flush_dns() {
    dscacheutil -flushcache 2>/dev/null
    killall -HUP mDNSResponder 2>/dev/null
    discoveryutil mdnsflushcache 2>/dev/null
    discoveryutil udnsflushcaches 2>/dev/null
}

# Function to restart all browsers (kills persistent connections and restores tabs)
restart_browsers() {
    # List of common browsers to restart
    local browsers=("Google Chrome" "Safari" "Firefox" "Brave Browser" "Microsoft Edge" "Arc" "Opera")
    local running_browsers=()

    # First, find which browsers are actually running
    for browser in "${browsers[@]}"; do
        if pgrep -x "$browser" > /dev/null 2>&1; then
            running_browsers+=("$browser")
        fi
    done

    # If no browsers running, do nothing
    if [ ${#running_browsers[@]} -eq 0 ]; then
        return
    fi

    # Quit the running browsers
    for browser in "${running_browsers[@]}"; do
        echo "Restarting $browser to kill persistent connections..."
        osascript -e "quit app \"$browser\"" 2>/dev/null
    done

    # Wait for browsers to fully quit
    sleep 3

    # Reopen ONLY the browsers that were running
    for browser in "${running_browsers[@]}"; do
        open -a "$browser" 2>/dev/null &
    done

    echo "Browsers restarted"
}

# Function to check if blocking state matches desired state
should_update_blocking() {
    local -a desired_sites=("$@")

    # Get currently blocked base domains
    local current_blocking=$(get_currently_blocked_domains)

    # Create desired blocking string (sorted)
    local desired_blocking=""
    if [ ${#desired_sites[@]} -gt 0 ]; then
        desired_blocking=$(printf '%s\n' "${desired_sites[@]}" | sort | tr '\n' ' ')
    fi

    # Compare
    if [ "$current_blocking" != "$desired_blocking" ]; then
        return 0  # true - should update
    else
        return 1  # false - no update needed
    fi
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

# Print restart_browsers setting
print('RESTART_BROWSERS_START')
print(str(settings.get('restart_browsers', True)).lower())
print('RESTART_BROWSERS_END')
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
            "RESTART_BROWSERS_START") mode="restart_browsers" ;;
            "RESTART_BROWSERS_END") mode="" ;;
            *)
                if [ -n "$mode" ]; then
                    case "$mode" in
                        "ssids") BLOCKING_SSIDS+=("$line") ;;
                        "network_sites") NETWORK_SITES+=("$line") ;;
                        "always_sites") ALWAYS_SITES+=("$line") ;;
                        "restart_browsers") RESTART_BROWSERS="$line" ;;
                    esac
                fi
                ;;
        esac
    done <<< "$settings_output"
}

# Function to expand domain to common subdomains
expand_domain() {
    local domain="$1"

    # Common subdomains to block automatically
    local subdomains=("" "www" "m" "mobile")

    for subdomain in "${subdomains[@]}"; do
        if [ -z "$subdomain" ]; then
            echo "$domain"
        else
            echo "$subdomain.$domain"
        fi
    done
}

# Function to add site blocking to hosts file
enable_blocking() {
    local sites_to_block=("$@")
    local block_doh="${BLOCK_DOH_SERVERS:-false}"

    if [ ${#sites_to_block[@]} -eq 0 ]; then
        echo "No sites to block"
        return
    fi

    if is_blocking_active; then
        echo "Blocking already active, updating..."
        disable_blocking
    fi

    echo "Enabling site blocking..."

    # Create temporary file with hosts blocking entries
    TEMP_FILE=$(mktemp)
    echo "$MARKER_START" > "$TEMP_FILE"

    # Block the sites themselves
    for domain in "${sites_to_block[@]}"; do
        while IFS= read -r expanded; do
            echo "0.0.0.0 $expanded" >> "$TEMP_FILE"
            echo "::1 $expanded" >> "$TEMP_FILE"
        done < <(expand_domain "$domain")
    done

    # If on blocking network, also block DoH servers to force Chrome to use system DNS
    if [ "$block_doh" = "true" ]; then
        echo "# Block DoH servers to force system DNS" >> "$TEMP_FILE"
        echo "0.0.0.0 dns.google" >> "$TEMP_FILE"
        echo "::1 dns.google" >> "$TEMP_FILE"
        echo "0.0.0.0 dns.google.com" >> "$TEMP_FILE"
        echo "::1 dns.google.com" >> "$TEMP_FILE"
        echo "0.0.0.0 8888.google" >> "$TEMP_FILE"
        echo "::1 8888.google" >> "$TEMP_FILE"
        echo "0.0.0.0 cloudflare-dns.com" >> "$TEMP_FILE"
        echo "::1 cloudflare-dns.com" >> "$TEMP_FILE"
        echo "0.0.0.0 1dot1dot1dot1.cloudflare-dns.com" >> "$TEMP_FILE"
        echo "::1 1dot1dot1dot1.cloudflare-dns.com" >> "$TEMP_FILE"
        echo "0.0.0.0 dns.quad9.net" >> "$TEMP_FILE"
        echo "::1 dns.quad9.net" >> "$TEMP_FILE"
        echo "0.0.0.0 doh.opendns.com" >> "$TEMP_FILE"
        echo "::1 doh.opendns.com" >> "$TEMP_FILE"
    fi

    echo "$MARKER_END" >> "$TEMP_FILE"

    # Apply hosts file changes
    cat "$TEMP_FILE" >> "$HOSTS_FILE"
    rm "$TEMP_FILE"

    # Flush DNS cache
    flush_dns

    if [ "$block_doh" = "true" ]; then
        echo "Blocking enabled for ${#sites_to_block[@]} sites + DoH servers"
    else
        echo "Blocking enabled for ${#sites_to_block[@]} sites"
    fi
}

# Function to remove site blocking from hosts file
disable_blocking() {
    if ! is_blocking_active; then
        return
    fi

    echo "Disabling site blocking..."

    # Remove lines between markers from hosts file
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

    # Flush DNS cache
    flush_dns

    echo "Blocking removed"
}

# Main logic
CURRENT_SSID=$(get_current_ssid)

# Check if network actually changed
LAST_SSID=""
if [ -f "$LAST_SSID_FILE" ]; then
    LAST_SSID=$(cat "$LAST_SSID_FILE")
fi

NETWORK_CHANGED=false
if [ "$CURRENT_SSID" != "$LAST_SSID" ]; then
    NETWORK_CHANGED=true
    echo "$CURRENT_SSID" > "$LAST_SSID_FILE"
    echo "Network changed: $LAST_SSID -> $CURRENT_SSID"
fi

# Read settings
declare -a BLOCKING_SSIDS
declare -a NETWORK_SITES
declare -a ALWAYS_SITES
RESTART_BROWSERS="true"  # Default to true

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
    if should_update_blocking "${SITES_TO_BLOCK[@]}"; then
        # Set flag to block DoH servers if on blocking network
        if [ "$on_blocking_network" = true ]; then
            BLOCK_DOH_SERVERS="true"
        else
            BLOCK_DOH_SERVERS="false"
        fi

        enable_blocking "${SITES_TO_BLOCK[@]}"
    else
        # Even if no update needed, flush DNS to clear any stale browser caches
        flush_dns
    fi
else
    if is_blocking_active; then
        disable_blocking
    else
        # Even if already disabled, flush DNS to ensure caches are clear
        flush_dns
    fi
fi

# ONLY restart browsers when network actually changed
if [ "$NETWORK_CHANGED" = true ] && [ "$RESTART_BROWSERS" = "true" ]; then
    restart_browsers
fi
