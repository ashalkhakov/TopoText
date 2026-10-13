#!/bin/bash
# In a clean Ubuntu (no GNUstep, no fonts): the image's own server started
# and seeded, and the app's self-test driving the window against it.
set -euo pipefail
image=$1
"$image" --server -StoreURL Temporary -Port 18090 -AccessLog NO > /tmp/server.log 2>&1 &
for i in $(seq 1 60); do python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:18090/odata/')" 2>/dev/null && break; sleep 1; done
python3 Examples/SimpleNotes/Tests/seed.py http://127.0.0.1:18090/odata/ || { cat /tmp/server.log; exit 1; }
timeout 300 xvfb-run -a "$image" --self-test http://127.0.0.1:18090/odata/
