#!/bin/bash
# Try multiple methods to get SSID

get_cached_scan_record_ssid() {
    local scan_record_hex=""

    scan_record_hex=$(scutil << 'SCUTILEOF' 2>/dev/null | sed -n 's/.*CachedScanRecord :  *<data> 0x//p' | head -1
show State:/Network/Interface/en0/AirPort
SCUTILEOF
)

    if [ -z "$scan_record_hex" ]; then
        return
    fi

    python3 - "$scan_record_hex" <<'PYEOF' 2>/dev/null
import plistlib
import sys


def uid_value(value):
    uid_type = getattr(plistlib, "UID", None)
    if uid_type is not None and isinstance(value, uid_type):
        return value.data
    if isinstance(value, dict) and "CF$UID" in value:
        return value["CF$UID"]
    return None


def resolve(objects, value):
    uid = uid_value(value)
    if uid is None:
        return value
    if 0 <= uid < len(objects):
        return objects[uid]
    return None


def nsdict_to_dict(objects, value):
    obj = resolve(objects, value)
    if not isinstance(obj, dict):
        return {}

    keys = obj.get("NS.keys", [])
    values = obj.get("NS.objects", [])
    result = {}

    for key_ref, value_ref in zip(keys, values):
        key = resolve(objects, key_ref)
        result[key] = resolve(objects, value_ref)

    return result


def usable_ssid(value):
    return isinstance(value, str) and value and value != "<redacted>"


try:
    data = bytes.fromhex(sys.argv[1].strip())
    plist = plistlib.loads(data)
    objects = plist.get("$objects", [])
    root = resolve(objects, plist.get("$top", {}).get("root"))
    record = nsdict_to_dict(objects, root)

    ssid = record.get("SSID_STR")
    if usable_ssid(ssid):
        print(ssid)
        raise SystemExit(0)

    ssid_data = record.get("SSID")
    if isinstance(ssid_data, bytes):
        ssid = ssid_data.decode("utf-8", "ignore").strip("\x00")
        if usable_ssid(ssid):
            print(ssid)
            raise SystemExit(0)
except Exception:
    pass

raise SystemExit(1)
PYEOF
}

# Method 1: scutil CachedScanRecord (works when SSID APIs are redacted)
SSID=$(get_cached_scan_record_ssid)
if [ -n "$SSID" ] && [ "$SSID" != "<redacted>" ]; then
    echo "$SSID"
    exit 0
fi

# Method 2: wdutil (requires root, available on Sequoia)
SSID=$(wdutil info 2>/dev/null | grep -E '^\s+SSID\s+:' | awk -F': ' '{print $2}' | head -1)
if [ -n "$SSID" ] && [ "$SSID" != "<redacted>" ]; then
    echo "$SSID"
    exit 0
fi

# Method 3: networksetup
SSID=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')
if [ -n "$SSID" ] && [ "$SSID" != "You are not associated with an AirPort network." ]; then
    echo "$SSID"
    exit 0
fi

# Method 4: system_profiler (often redacted on Sequoia)
SSID=$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{getline; gsub(/^[ \t]+|:$/, ""); print; exit}')
if [ -n "$SSID" ] && [ "$SSID" != "<redacted>" ]; then
    echo "$SSID"
    exit 0
fi

# Method 5: ipconfig
SSID=$(ipconfig getsummary en0 2>/dev/null | grep ' SSID' | awk -F' : ' '{print $2}')
if [ -n "$SSID" ] && [ "$SSID" != "<redacted>" ]; then
    echo "$SSID"
    exit 0
fi

echo "NO_SSID"
