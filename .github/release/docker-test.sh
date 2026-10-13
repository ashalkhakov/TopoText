#!/bin/bash
# The server's image as a user runs it, for gnustep-release-actions'
# docker-release.yml (given the target and the image built and loaded):
# SQLite in its volume by default, and PostgreSQL by its settings
# (FreeCoreData's store, loaded by name), each started, seeded and its notes
# read back; and signed in through an identity provider, where a token it
# cannot check is refused (401), which needs the image's CA certificates to
# fetch the provider's keys. Its containers are its own, removed at the end.
set -euo pipefail
image=$2
trap 'docker rm -f topotext-db topotext-sqlite topotext-postgres topotext-oidc > /dev/null 2>&1 || true
      docker network rm topotext-notes > /dev/null 2>&1 || true' EXIT
docker network create topotext-notes > /dev/null
docker run -d --name topotext-db --network topotext-notes -e POSTGRES_PASSWORD=notes -e POSTGRES_DB=notes postgres:16 > /dev/null
docker run -d --name topotext-sqlite --network topotext-notes -p 18080:8080 \
  -e SN_SERVICE_ROOT=http://127.0.0.1:18080/odata/ "$image" > /dev/null
for _ in $(seq 1 60); do docker exec topotext-db pg_isready -h 127.0.0.1 -U postgres > /dev/null 2>&1 && break; sleep 1; done
docker run -d --name topotext-postgres --network topotext-notes -p 18081:8080 \
  -e SN_STORE_TYPE=PostgreSQL -e SN_STORE_URL=postgresql://postgres:notes@topotext-db:5432/notes \
  -e SN_SERVICE_ROOT=http://127.0.0.1:18081/odata/ "$image" > /dev/null
for port in 18080 18081; do
  for _ in $(seq 1 60); do curl -sf -o /dev/null "http://127.0.0.1:$port/health" && break; sleep 1; done
  python3 Examples/SimpleNotes/Tests/seed.py "http://127.0.0.1:$port/odata/"
  count=$(curl -sf "http://127.0.0.1:$port/odata/Notes/\$count")
  echo "$port: $count notes"
  [ "$count" = 4 ] || { docker logs topotext-sqlite; docker logs topotext-postgres; exit 1; }
done

docker run -d --name topotext-oidc -p 18082:8080 \
  -e SN_SERVICE_ROOT=http://127.0.0.1:18082/odata/ -e SN_JWT_ISSUER=https://accounts.google.com \
  -e SN_ALLOW_ANONYMOUS=NO "$image" > /dev/null
for _ in $(seq 1 60); do curl -sf -o /dev/null http://127.0.0.1:18082/health && break; sleep 1; done
b64() { base64 -w0 | tr '+/' '-_' | tr -d '='; }
header=$(printf '{"alg":"RS256","typ":"JWT","kid":"none"}' | b64)
claims=$(printf '{"iss":"https://accounts.google.com","sub":"x","exp":9999999999}' | b64)
answer=$(mktemp)
status=$(curl -s -o "$answer" -w '%{http_code}' -H "Authorization: Bearer $header.$claims.c2ln" \
  http://127.0.0.1:18082/odata/Notes)
echo "$status: $(cat "$answer")"
[ "$status" = 401 ] || { docker logs topotext-oidc; exit 1; }
