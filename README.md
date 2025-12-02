# WiFi Site Blocker

Block distracting websites based on which WiFi network you're connected to.

**Example:** Block YouTube at home, allow it at coffee shops. Block Instagram everywhere.

## Requirements

- **macOS only** (tested on macOS 12-15/Sequoia)
- No Location Services needed
- No additional dependencies (uses built-in macOS tools)

## How It Works

Modifies `/etc/hosts` to redirect blocked domains to `0.0.0.0`. A background service monitors WiFi changes and updates the block list automatically.

Works in all browsers and apps. Can't be bypassed with incognito mode or browser extensions.

## Quick Start

```bash
sudo ./install.sh
# Edit settings.json with your WiFi names and sites to block
sudo ./install.sh
```

## Configuration

Edit `settings.json`:

```json
{
  "network_specific_blocking": {
    "ssids": ["HomeWiFi", "OfficeWiFi"],
    "sites": ["youtube.com", "reddit.com"]
  },
  "always_block": {
    "sites": ["instagram.com", "tiktok.com"]
  },
  "restart_browsers": true
}
```

- **ssids**: WiFi networks where blocking activates
- **network_specific_blocking.sites**: Blocked only on listed networks
- **always_block.sites**: Blocked everywhere

Subdomains (www, m, mobile) are blocked automatically.

After editing, run `sudo ./install.sh` again or:
```bash
sudo launchctl kickstart -k system/com.wifi-site-blocker
```

## Uninstall

```bash
sudo ./uninstall.sh
```

## Troubleshooting

**Sites still loading?**
- Disable "Use secure DNS" in Chrome (`chrome://settings/security`)
- Flush DNS: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`
- Restart browser

**Check if working:**
```bash
ping youtube.com  # Should show 0.0.0.0
cat /tmp/wifi-site-blocker.log
```

## Files

- `settings.json` - Your configuration
- `site-blocker.sh` - Main script
- `install.sh` / `uninstall.sh` - Setup scripts
