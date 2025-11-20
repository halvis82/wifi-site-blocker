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

# Function to get current blocked domains from hosts file
get_currently_blocked_domains() {
    if ! is_blocking_active; then
        echo ""
        return
    fi

    # Extract domains between markers (only the base domains, not subdomains)
    sed -n "/$MARKER_START/,/$MARKER_END/p" "$HOSTS_FILE" | \
        grep "^0.0.0.0" | \
        awk '{print $2}' | \
        grep -v "^www\." | \
        grep -v "^m\." | \
        grep -v "^mobile\." | \
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
    local restarted=false

    for browser in "${browsers[@]}"; do
        if pgrep -x "$browser" > /dev/null 2>&1; then
            echo "Restarting $browser to kill persistent connections..."

            # Quit browser gracefully
            osascript -e "quit app \"$browser\"" 2>/dev/null

            restarted=true
        fi
    done

    if [ "$restarted" = true ]; then
        # Wait for browsers to fully quit
        sleep 2

        # Reopen the browsers that were closed
        for browser in "${browsers[@]}"; do
            # Check if browser was running by seeing if it just quit
            if ! pgrep -x "$browser" > /dev/null 2>&1; then
                # Try to reopen (will only work if browser exists on system)
                open -a "$browser" 2>/dev/null &
            fi
        done

        echo "Browsers restarted"
    fi
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

    # Restart browsers if setting is enabled
    if [ "$RESTART_BROWSERS" = "true" ]; then
        restart_browsers
    fi

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

    # Restart browsers if setting is enabled
    if [ "$RESTART_BROWSERS" = "true" ]; then
        restart_browsers
    fi

    echo "Blocking removed"
}

# Main logic
CURRENT_SSID=$(get_current_ssid)

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
