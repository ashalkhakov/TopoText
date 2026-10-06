#!/bin/bash
# The iOS app's self-test in a simulator, against a server of its own on
# this Mac (the simulator shares its network):
#   ios-self-test.sh <server> <SimpleNotes.app for the simulator> [device name]
set -u
server=$1; app=$2; device=${3:-}
port=${SN_CHECK_PORT:-18095}
root="http://127.0.0.1:$port/odata/"
here=$(cd "$(dirname "$0")" && pwd)
[ -n "$device" ] || device=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | head -1 | sed -E 's/^ +//; s/ \(.*//')
udid=$(xcrun simctl list devices available | grep -F "    $device (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$udid" ] || { echo "no simulator named $device"; exit 1; }
echo "simulator: $device ($udid)"
# Booted, and up: simctl's bootstatus -b can wait for ever, so this polls.
xcrun simctl boot "$udid" 2>/dev/null
for i in $(seq 1 120); do
  xcrun simctl list devices | grep -F "($udid) (Booted)" >/dev/null && xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1 && break
  sleep 1
done
log=$(mktemp)
"$server" -StoreURL Temporary -Port "$port" -AccessLog NO > "$log" 2>&1 &
pid=$!
stop() { kill $pid 2>/dev/null; wait $pid 2>/dev/null; rm -f "$log"; }
trap stop EXIT
for i in $(seq 1 100); do
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break
  sleep 0.2
done
python3 "$here/seed.py" "$root" || exit 1
xcrun simctl install "$udid" "$app" || exit 1
id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
out=$(mktemp)
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$id" --self-test "$root" 2>&1 | tee "$out" | grep --line-buffered -E "^(PASS|FAIL|self-test)"
grep -q "^self-test: passed" "$out"; status=$?
rm -f "$out"
exit $status
