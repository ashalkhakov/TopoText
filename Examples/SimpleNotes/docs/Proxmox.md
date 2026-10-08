# SimpleNotes' server on Proxmox VE, signed in with Keycloak

How to run `simplenotes-server` on Proxmox VE as a container made from its
Docker image (an OCI image pulled as a CT template), behind a reverse proxy,
with users signing in through Keycloak. The names below are examples:

| | |
|---|---|
| SimpleNotes, as users reach it | `https://notes.example.com/odata/` |
| Keycloak, its realm | `https://id.example.com/realms/myrealm` |
| The container | CT `100`, LAN address `10.0.0.20` |

## 1. Keycloak

In the realm, Clients › Create client:

- **Client ID** `simplenotes`, OpenID Connect. The apps use this name.
- **Client authentication** off: a public client. The apps can't keep a secret.
- **OAuth 2.0 Device Authorization Grant** on. The apps sign in with a code
  entered in a browser, so they need no redirect URI. Standard flow can stay off.
- **PKCE** (Advanced › Proof Key for Code Exchange Code Challenge Method): `S256`, or leave it empty.
  The apps send PKCE either way (from 0.2.0-rc2 on).
- **Audience** (only if the server checks one, `SN_JWT_AUDIENCE`): Client
  scopes › `simplenotes-dedicated` › Add mapper › By configuration ›
  Audience, Included Client Audience `simplenotes`, Add to access token on.
  Keycloak's tokens otherwise say `aud: account`, and every sync is refused 401.

Each user's notes are their own: the server keeps them under the user's
Keycloak ID (the token's `sub`, the ID on the user's page in Keycloak).

## 2. The image

Datacenter › node › storage (`local`) › CT Templates › **Pull from OCI
Registry**:

```
ghcr.io/ashalkhakov/simplenotes-server:0.2.0
```

Name the version. `latest` is the last release; a release candidate
(`0.2.0-rc5`) is published under its own name only.

## 3. The container

Create a CT from that template.

**Network.** A fixed address (or a DHCP reservation): the reverse proxy
forwards to it.

**`/data` as a mount point of its own.** Resources › Add › Mount Point, path
`/data`. The notes (`notes.sqlite`, with `-wal` and `-shm`) and the key peer
tokens are signed with (`SimpleNotes-peer-key.json`) live there, and a mount
point moves from one container to the next when updating (step 6).

**Environment** (Options › Environment):

```
SN_SERVICE_ROOT=https://notes.example.com/odata/
SN_JWT_ISSUER=https://id.example.com/realms/myrealm
SN_ALLOW_ANONYMOUS=NO
```

- `SN_SERVICE_ROOT` is the address users reach. The server's links begin
  with it; left out, they name the container (`http://CT100:8080/odata/`) and
  the apps cannot follow them.
- `SN_JWT_ISSUER` is the realm, exactly as Keycloak's discovery document says
  it (no trailing `/`).
- `SN_ALLOW_ANONYMOUS=NO` refuses requests from no one. `$metadata` and the
  service document stay readable: that is where the apps learn how to sign in.
- `SN_JWT_AUDIENCE=simplenotes` only with Keycloak's audience mapper (step 1).

The image's own variables (`SN_PORT=8080`, `SN_STORE_URL=/data/notes.sqlite`,
`CURL_CA_BUNDLE`, ...) come with the template; leave them.

**DNS.** Proxmox does not write `/etc/resolv.conf` into a container made from
an OCI image, and the image has none, so the server cannot look up the
identity provider. Bind-mount the host's, on the Proxmox host:

```sh
echo 'lxc.mount.entry: /etc/resolv.conf etc/resolv.conf none bind,ro,create=file 0 0' >> /etc/pve/lxc/100.conf
```

Then start the container.

## 4. The reverse proxy

Forward the users' host (`notes.example.com`) to `http://10.0.0.20:8080`,
with TLS at the proxy (Nginx Proxy Manager, Caddy, Traefik). The server
answers `/health` for the proxy's checks.

If the router does not loop the public addresses back into the LAN, the
container must still reach `id.example.com`: a DNS override on the router
pointing it at the proxy's LAN address does it.

## 5. Checking it

```sh
curl https://notes.example.com/odata/\$metadata             # 200, the schema, naming the realm
curl -i https://notes.example.com/odata/Notes                # 401: sign in
curl -s https://notes.example.com/odata/ | head -c 120       # its links begin with SN_SERVICE_ROOT
```

After a device signed in and synced:

```sh
curl -s https://notes.example.com/metrics | grep http_auth_provider_requests_total
```

shows `outcome="200"`. `outcome="error"` means the server did not reach
Keycloak (step 3's DNS, or step 4's loop back).

Inside the container, from the Proxmox host (the image has no shell):

```sh
PID=$(lxc-info -n 100 -p -H)
cat /proc/$PID/root/etc/resolv.conf                          # the host's nameservers
ls -l /proc/$PID/root/etc/ssl/certs/ca-certificates.crt     # the CA certificates (0.2.0-rc4 on)
tr '\0' '\n' < /proc/$PID/environ | grep -E 'SN_|CURL'       # what the server was started with
```

## 6. Updating

A container made from an image is not updated in place: a new one is made
from the new image, and the notes move to it.

1. Pull the new version (step 2).
2. Note the old container's environment, network and the `lxc.mount.entry`
   line in `/etc/pve/lxc/<id>.conf`.
3. Create the new container from the new template, with the same
   environment, address and DNS line (step 3). Do not start it.
4. Shut the old one down. On its `/data` mount point, Volume Action ›
   **Reassign Owner** › the new container.
5. Start the new one and check it (step 5). A newer version brings the store
   up to its model the first time it opens it; keep a copy of `notes.sqlite`
   beforehand.
6. Remove the old container.

Without `/data` as a mount point, copy the files across instead (both
containers stopped); the image runs as user 10001, which an unprivileged
container maps to 110001 on the host:

```sh
pct mount OLD && cp -a /var/lib/lxc/OLD/rootfs/data/. /root/sn-backup/ && pct unmount OLD
pct mount NEW && cp -a /root/sn-backup/. /var/lib/lxc/NEW/rootfs/data/ \
  && chown -R 110001:110001 /var/lib/lxc/NEW/rootfs/data && pct unmount NEW
```

## PostgreSQL instead of SQLite

```
SN_STORE_TYPE=PostgreSQL
SN_STORE_URL=postgresql://notes:secret@10.0.0.30:5432/notes
```

The server makes its tables in that database the first time it opens it,
and brings them up to a newer model itself. Keep `/data` as a mount point
all the same: the peer-token signing key (`SimpleNotes-peer-key.json`) is
kept there whatever the store is, and a new key makes every device's peer
token worthless.

Switch while the server is new. The notes of a SQLite store are not copied
into the database, and devices remember what they last sent to the
server's address: one that finds the same address answering from an empty
database does not send everything again. Moving a server that already has
notes is not covered yet.

## 7. Notes from before sign-in

Notes synced while the server had no sign-in (or with SimpleNotes 0.1) are
no one's, and a signed-in user sees only their own. To give them to one
user, start the server once with

```
SN_GIVE_UNOWNED_TO=<the user's Keycloak ID>
```

then remove it. Neither the server nor the apps make notes of their own: a
new server and a new device sync an empty notebook.

## When it goes wrong

| What the app says | Why | |
|---|---|---|
| The sign-in provider refused: Missing parameter: code_challenge_method | The client wants PKCE; an app before 0.2.0-rc2 sends none | Update the app, or clear the client's PKCE method |
| The issuer's discovery document does not name its keys | The server could not fetch Keycloak's keys | DNS (step 3), CA certificates (0.2.0-rc4 on), or the router's loop back (step 4) |
| A server with the specified hostname could not be found (`http://CT100:8080/…`) | `SN_SERVICE_ROOT` is not set | Set it (step 3); on the device, start from a new store, as the link it saved names the container |
| Not synced, 401, after signing in | The token's audience is not `SN_JWT_AUDIENCE` | Add Keycloak's audience mapper, or remove `SN_JWT_AUDIENCE` |
| Synced, and no notes | The notes are no one's, or the container's `/data` is new | Step 7, or move the old `/data` over (step 6) |
