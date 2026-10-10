#!/bin/bash
# A server's notes moved to another store (MoveFrom), checked:
#
#   move-and-check.sh <server> [the new store's arguments]
#
# The server is started on a SQLite store and seeded (seed.py), then again
# on the new store (default: another SQLite file; e.g. -StoreType
# PostgreSQL -StoreURL postgresql://user:password@host/empty) with
# -MoveFrom the first: it must serve the same notes and folders. Then once
# more, the setting left in place: nothing is moved twice.
set -u
server=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
port=${SN_CHECK_PORT:-18082}
root="http://127.0.0.1:$port/odata/"
dir=$(mktemp -d)
log="$dir/server.log"
pid=
stop() { [ -n "$pid" ] && { kill $pid 2>/dev/null; wait $pid 2>/dev/null; }; pid=; }
trap 'stop; rm -rf "$dir"' EXIT

serve() {
  "$server" "$@" -Port "$port" -AccessLog NO > "$log" 2>&1 &
  pid=$!
  for i in $(seq 1 100); do
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && return 0
    kill -0 $pid 2>/dev/null || { echo "the server did not start:"; cat "$log"; exit 1; }
    sleep 0.2
  done
  echo "the server did not answer:"; cat "$log"; exit 1
}

# What it serves: the notes with their folders, the folders with theirs.
served() {
  python3 - "$root" <<'EOF'
import json, sys, urllib.request
root = sys.argv[1]
def get(path):
    out, url = [], root + path
    while url:
        page = json.load(urllib.request.urlopen(url))
        out += page['value']
        url = page.get('@odata.nextLink')
    return out
notes = get("Notes?$select=Id,Title,Body,Pinned&$expand=Folder($select=Id)&$orderby=Id")
folders = get("Folders?$select=Id,Name&$expand=Parent($select=Id)&$orderby=Id")
print(json.dumps({'notes': notes, 'folders': folders}, sort_keys=True))
EOF
}

serve -StoreURL "$dir/old.sqlite"
python3 "$here/seed.py" "$root" || { cat "$log"; exit 1; }
before=$(served) || { cat "$log"; exit 1; }
# A device's delta link, as one synced before the move holds it.
delta=$(python3 - "$root" <<'EOF'
import json, sys, urllib.request
url = sys.argv[1] + 'Notes'
while True:
    page = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={'Prefer': 'odata.track-changes'})))
    if '@odata.deltaLink' in page: print(page['@odata.deltaLink']); break
    url = page['@odata.nextLink']
EOF
) || { cat "$log"; exit 1; }
stop

status=0
check() {
  after=$(served) || { cat "$log"; exit 1; }
  if [ "$after" = "$before" ]; then echo "ok $1"; else
    echo "FAIL $1"; echo "before: $before"; echo "after:  $after"; echo "--- server log"; cat "$log"; status=1
  fi
}

new=("$@")
[ ${#new[@]} -eq 0 ] && new=(-StoreURL "$dir/new.sqlite")
serve "${new[@]}" -MoveFrom "$dir/old.sqlite"
grep -q "moved here from" "$log" || { echo "FAIL the server says it moved the notes"; cat "$log"; status=1; }
check "the notes and folders are served from the new store"
# Given before the move: gone (410), and the device reads its notes again.
code=$(python3 - "$delta" <<'EOF'
import sys, urllib.request, urllib.error
try:
    urllib.request.urlopen(sys.argv[1]); print(200)
except urllib.error.HTTPError as e:
    print(e.code)
EOF
)
if [ "$code" = 410 ]; then echo "ok a delta link given before the move answers 410"; else
  echo "FAIL a delta link given before the move answers $code, not 410"; status=1
fi
stop

serve "${new[@]}" -MoveFrom "$dir/old.sqlite"
grep -q "nothing moved" "$log" || { echo "FAIL the server says there was nothing to move"; cat "$log"; status=1; }
check "started again, nothing is moved twice"
stop
exit $status
