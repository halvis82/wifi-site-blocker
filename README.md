# WiFi Site Blocker

A flexible system-level website blocker for macOS with WiFi-aware blocking capabilities.

## What It Does

- **Blocks websites system-wide** - Works across all browsers and applications
- **WiFi-aware blocking** - Block specific sites only when connected to certain networks
- **Always-block list** - Block sites on any network
- **Configurable via JSON** - Easy to edit settings without touching code
- **Automatic** - Runs as a background service, no manual intervention needed
- **Persistent** - Starts on boot and monitors network changes
- **Hard to bypass** - No browser extensions to disable, works at the OS level

## How It Works

1. A LaunchDaemon monitors your WiFi connection for changes
2. The script reads `settings.json` to determine which sites to block
3. Sites are blocked by modifying `/etc/hosts` to redirect them to `0.0.0.0`
4. DNS cache is automatically flushed when changes are made

## Installation

### First Installation

1. Open Terminal and navigate to this directory:
   ```bash
   cd ~/path/to/wifi-site-blocker
   ```

2. Run the installation script:
   ```bash
   sudo ./install.sh
   ```

3. Enter your password when prompted

4. **Important:** The installer will create a default `settings.json` file if one doesn't exist. You must edit it to configure your WiFi SSIDs and sites to block:
   ```bash
   nano settings.json
   ```

   See the [Configuration](#configuration) section below for details.

5. After editing `settings.json`, reinstall to apply your settings:
   ```bash
   sudo ./install.sh
   ```

The settings will be copied to `/usr/local/etc/wifi-site-blocker/settings.json` where the system service reads from.

## Configuration

The blocker is configured via `settings.json`. When you run `install.sh` for the first time, it will create a default `settings.json` file with placeholder values.

### Default Settings File

The installer creates this default `settings.json`:

```json
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
```

**You must edit this file** to replace the placeholder values with your actual WiFi network names and sites you want to block.

### Configuration Sections

1. **`network_specific_blocking.ssids`** - List of WiFi network names to activate blocking on
2. **`network_specific_blocking.sites`** - Sites to block ONLY when on the specified networks
3. **`always_block.sites`** - Sites to block on ANY network, regardless of WiFi

### Editing Configuration

The settings file is installed to `/usr/local/etc/wifi-site-blocker/settings.json`

To edit the configuration:

```bash
sudo nano /usr/local/etc/wifi-site-blocker/settings.json
```

After editing, restart the service to apply changes:

```bash
sudo launchctl kickstart -k system/com.wifi-site-blocker
```

### Example Use Cases

**Block YouTube only at home:**
```json
{
  "network_specific_blocking": {
    "ssids": ["YourHomeWiFi"],
    "sites": ["youtube.com", "www.youtube.com"]
  },
  "always_block": {
    "sites": []
  }
}
```

**Block social media everywhere:**
```json
{
  "network_specific_blocking": {
    "ssids": [],
    "sites": []
  },
  "always_block": {
    "sites": [
      "facebook.com",
      "twitter.com",
      "instagram.com",
      "tiktok.com"
    ]
  }
}
```

**Hybrid approach:**
```json
{
  "network_specific_blocking": {
    "ssids": ["YourHomeWiFi", "YourOfficeWiFi"],
    "sites": ["youtube.com", "netflix.com"]
  },
  "always_block": {
    "sites": ["gambling-site.com"]
  }
}
```

## Uninstallation

To completely remove the blocker:

```bash
cd ~/Documents/personal_coding/wifi-site-blocker
sudo ./uninstall.sh
```

This will:
- Stop and remove the background service
- Remove the blocking script
- Remove the settings file
- Clean up `/etc/hosts`
- Remove all logs

## Monitoring & Logs

Check if the service is running:
```bash
sudo launchctl list | grep wifi-site-blocker
```

View logs:
```bash
cat /tmp/wifi-site-blocker.log
cat /tmp/wifi-site-blocker-error.log
```

Check current hosts file entries:
```bash
grep WIFI-SITE-BLOCKER /etc/hosts
```

Check your current WiFi SSID:
```bash
system_profiler SPAirPortDataType | grep -A 1 "Current Network"
```

## Testing

### Test if blocking is active:
```bash
ping youtube.com
```
If blocking is active, you should see it trying to ping `0.0.0.0`

### Manual test run:
```bash
sudo /usr/local/bin/site-blocker.sh
```

## Troubleshooting

### Sites still load despite being blocked

1. Clear your browser cache and cookies
2. Flush DNS cache manually:
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```
3. Restart your browser completely
4. If using a VPN, the blocker may be bypassed

### Blocker not activating on home WiFi

1. Check logs: `cat /tmp/wifi-site-blocker.log`
2. Verify your WiFi SSID:
   ```bash
   system_profiler SPAirPortDataType | grep -A 1 "Current Network"
   ```
3. Make sure it matches an SSID in your `settings.json`
4. Check the settings file:
   ```bash
   cat /usr/local/etc/wifi-site-blocker/settings.json
   ```

### Service not starting on boot

1. Check the LaunchDaemon status:
   ```bash
   sudo launchctl list | grep wifi-site-blocker
   ```
2. Reinstall the service:
   ```bash
   cd ~/Documents/personal_coding/wifi-site-blocker
   sudo ./uninstall.sh
   sudo ./install.sh
   ```

### JSON syntax errors

If you get errors about the settings file:
1. Validate your JSON syntax at https://jsonlint.com/
2. Common mistakes:
   - Missing commas between array items
   - Trailing comma after last item
   - Missing quotes around strings
   - Unclosed brackets

## Files

- `settings.json` - Configuration file (auto-generated by install.sh, not in repo)
- `site-blocker.sh` - Main blocking script
- `com.wifi-site-blocker.plist` - LaunchDaemon configuration
- `install.sh` - Installation script
- `uninstall.sh` - Uninstallation script
- `.gitignore` - Git ignore file (excludes settings.json)
- `README.md` - This file

## Important Notes

- The script requires `sudo` privileges to modify `/etc/hosts`
- The LaunchDaemon runs as root, which is necessary for system-level blocking
- Blocking is based on DNS resolution - VPNs or custom DNS settings may bypass it
- The blocker will persist across restarts and updates
- To temporarily disable, you must edit settings.json or fully uninstall
- The script automatically adds `www.` versions of domains (unless already specified)

## Security Considerations

This tool modifies a system file (`/etc/hosts`) and runs with elevated privileges. The code is transparent and auditable - feel free to review all scripts before installation.

## Advanced Tips

### Block all subdomains
To block all YouTube subdomains, add variations:
```json
"sites": [
  "youtube.com",
  "m.youtube.com",
  "music.youtube.com",
  "youtubei.googleapis.com",
  "youtu.be"
]
```

### Find your WiFi SSID
```bash
system_profiler SPAirPortDataType | awk '/Current Network Information:/{getline; gsub(/^[ \t]+|:$/, ""); print; exit}'
```

### Temporarily disable without uninstalling
Stop the service:
```bash
sudo launchctl bootout system/com.wifi-site-blocker
```

Re-enable later:
```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.wifi-site-blocker.plist
```
