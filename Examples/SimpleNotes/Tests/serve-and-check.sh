#!/bin/bash
# The server started on a free port with a temporary store, the check run
# against it, the server stopped: serve-and-check.sh <server> <check command...>
# (the check gets the server's root as its last argument).
set -u
# SN_STORE_ARGS: the server's store (default -StoreURL Temporary), e.g.
#   -StoreType PostgreSQL -StoreURL postgresql://user:password@host/notes
server=$1; shift
port=${SN_CHECK_PORT:-18080}
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
"$@" "http://127.0.0.1:$port/odata/"
status=$?
[ $status -eq 0 ] || { echo "--- server log"; cat "$log"; }
exit $status
