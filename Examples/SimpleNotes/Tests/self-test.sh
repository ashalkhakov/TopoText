#!/bin/bash
# The app's self-test against a server of its own: the server started with
# a temporary store and seeded (seed.py), the app run with --self-test,
# with a display of its own (xvfb-run) where there is none.
#   self-test.sh <server> <app executable>
set -u
# SN_STORE_ARGS: the server's store (default -StoreURL Temporary), e.g.
#   -StoreType PostgreSQL -StoreURL postgresql://user:password@host/notes
server=$1; app=$2
port=${SN_CHECK_PORT:-18090}
root="http://127.0.0.1:$port/odata/"
here=$(cd "$(dirname "$0")" && pwd)
log=$(mktemp)
"$server" ${SN_STORE_ARGS:--StoreURL Temporary} -Port "$port" -AccessLog NO > "$log" 2>&1 &
pid=$!
stop() { kill $pid 2>/dev/null; wait $pid 2>/dev/null; rm -f "$log"; }
trap stop EXIT
for i in $(seq 1 100); do
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break
  kill -0 $pid 2>/dev/null || { echo "the server did not start:"; cat "$log"; exit 1; }
  sleep 0.2
done
python3 "$here/seed.py" "$root" || exit 1
# On GNUstep, the Eau theme, set in the app's defaults as our other apps'
# launchers (AppRun) set it.
if [ "$(uname -s)" != Darwin ] && command -v defaults >/dev/null; then defaults write SimpleNotes GSTheme Eau; fi
display=()
if [ "$(uname -s)" != Darwin ] && [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then display=(xvfb-run -a); fi
${display[@]+"${display[@]}"} "$app" --self-test "$root"
status=$?
[ $status -eq 0 ] || { echo "--- server log"; cat "$log"; }
exit $status
