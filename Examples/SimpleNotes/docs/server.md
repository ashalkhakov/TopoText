# Running the server

`simplenotes-server` serves the notes over OData, for the apps to sync with. Run it in Docker (the usual way), on Linux from the AppImage, or from a build.

## On this machine

The server, on this machine:

```sh
make -C Examples/SimpleNotes           # macOS: build/; GNUstep: obj/
build/simplenotes-server -StoreURL notes.sqlite -Port 8080 -Localhost NO
python3 Tests/seed.py http://127.0.0.1:8080/odata/      # a few notes to start with
```

Its settings are ois-serve's (`Port`, `Localhost`, sign-in through
`TrustedUserHeader` or `JWTIssuer`, and the rest of HTTPServerKit's). In
addition:

- `StoreType` can be `SQLite` (the default), `PostgreSQL`, or `MySQL` /
  `MariaDB`, using FreeCoreData's SQL stores. Give `StoreURL` as the
  database's URL:

  ```sh
  obj/simplenotes-server -StoreType PostgreSQL -StoreURL postgresql://notes:secret@db/notes
  ```

  Delta links need persistent history. FreeCoreData's SQL stores keep it on
  GNUstep, but not on Apple's Core Data, so a server on macOS uses SQLite.
- `StoreURL Temporary` is a throwaway store, for trying things out.
- `MoveFrom` moves the notes from another store into this one: a SQLite
  file, or a database's URL as `StoreURL` takes it (its type comes from the
  scheme, or from `MoveFromType`). It copies only while this store is
  still empty, so the setting can stay in place afterwards. See [Moving to
  another database](#moving-to-another-database).
- `AllowAnonymous NO` refuses requests that don't say who they're from,
  once a sign-in is set.
- `AllowAnonymousMetadata NO` refuses `$metadata` too. By default anyone may
  read it, since that's where the apps learn how to sign in.
- `Notebooks` is `PerUser` (the default once a sign-in is set: each user
  has their own folders and notes) or `Shared` (every device syncs every
  note).
- `GiveUnownedTo <user>` gives the notes made while the notebook was shared
  to that user (their sign-in's subject), at start.
- `PeerKey` is the file of the key the server signs peer tokens with, which
  let a user's devices nearby sync with each other while offline. It's made
  the first time, beside a SQLite store; `None` turns peer tokens off.

Each setting can also be an environment variable: `SN_` and the setting's
name in capitals, words split by `_` (`SN_STORE_URL`, `SN_SERVICE_ROOT`,
`SN_TRUSTED_USER_HEADER`).

## In Docker

The server's image holds the server, its model, FreeCoreData's PostgreSQL
and MySQL/MariaDB stores, and the libraries they all run on. It has no
shell and no package manager (`Docker/server.Dockerfile`, about 31 MB
compressed). A release publishes it as
`ghcr.io/ashalkhakov/simplenotes-server`.

```sh
docker run -p 8080:8080 -v notes:/data ghcr.io/ashalkhakov/simplenotes-server
docker build -f Docker/server.Dockerfile -t simplenotes-server .   # from the repository's root
```

It runs as an unprivileged user, and by default keeps a SQLite store in
the `/data` volume. Configure it with environment variables:

| Variable | Default | |
|---|---|---|
| `SN_STORE_TYPE` | `SQLite` | `SQLite`, `PostgreSQL`, `MySQL` or `MariaDB` |
| `SN_STORE_URL` | `/data/notes.sqlite` | a path for SQLite, else the database's URL (`postgresql://user:password@host:5432/notes`, `mysql://user:password@host:3306/notes`) |
| `SN_SERVICE_ROOT` | `http://<container>:8080/odata/` | the public URL the service is reached at: set it behind a reverse proxy, as its links begin with it |
| `SN_PORT` | `8080` | |
| `SN_ACCESS_LOG` | `json` | JSON lines, for a log collector |
| `SN_HEALTH_PATH` | `/health` | for the orchestrator or the proxy |

With PostgreSQL:

```sh
docker run -p 8080:8080 \
  -e SN_STORE_TYPE=PostgreSQL -e SN_STORE_URL=postgresql://notes:secret@db:5432/notes \
  ghcr.io/ashalkhakov/simplenotes-server
```

## Moving to another database

A server can start on SQLite and move to PostgreSQL or MariaDB later. Make
an empty database, then start the server on it with `MoveFrom` naming the
old store:

```sh
docker run -p 8080:8080 -v notes:/data \
  -e SN_STORE_TYPE=PostgreSQL -e SN_STORE_URL=postgresql://notes:secret@db:5432/notes \
  -e SN_MOVE_FROM=/data/notes.sqlite \
  ghcr.io/ashalkhakov/simplenotes-server
```

At start, while the new database has nothing in it, the server copies
everything into it: notes, folders, attachments, owners, and ODataSync's
records of deletions and of what each device has seen. The log says
`the notes moved here from …`. The old store is left as it was, so you can
go back to it.

Persistent history isn't copied. Instead, it begins again with the copy,
and every delta link given before the move answers 410. Each device then
reads its notes again at its next sync, and sends whatever it hadn't sent
yet. Peer tokens keep working: the peer key beside the SQLite file comes
along, unless `PeerKey` names one.

Once the database has notes, `MoveFrom` does nothing (the log says
`nothing moved`), so it's safe to leave it set or to remove it. A move
between other types works the same way, for example `MoveFrom
postgresql://…` with `StoreType MariaDB`.

Behind a reverse proxy (Nginx Proxy Manager, Caddy, Traefik), forward a
host to the container's port 8080, and give the address users reach as
`SN_SERVICE_ROOT`, for example `https://notes.example.com/odata/`.
HTTPServerKit's proxy settings work as `SN_` variables too:

- `SN_TRUSTED_USER_HEADER` takes the signed-in user from a header the
  proxy sets.
- `SN_PROXY_SECRET_HEADER` together with `SN_PROXY_SECRET_ENVIRONMENT`
  accepts only requests that carry the proxy's secret.
- `SN_CORS_ORIGINS` sets the allowed origins.

On Proxmox VE, as a container made from the image, signed in with
Keycloak: [docs/Proxmox.md](Proxmox.md), from the image to updating.

## Signing in with Keycloak (or another OpenID Connect provider)

1. In the realm, add a client with Client ID `simplenotes`: public (no
   client authentication), with **OAuth 2.0 Device Authorization Grant**
   on. The apps sign in with a code entered in a browser, so they need no
   redirect URI.
2. Run the server with the realm as its issuer:

   ```sh
   docker run -p 8080:8080 -v notes:/data \
     -e SN_SERVICE_ROOT=https://notes.example.com/odata/ \
     -e SN_JWT_ISSUER=https://id.example.com/realms/<realm> \
     -e SN_ALLOW_ANONYMOUS=NO \
     ghcr.io/ashalkhakov/simplenotes-server
   ```

   `SN_JWT_AUDIENCE` additionally checks the tokens' audience, if your
   realm sets one.
3. In the app, choose Sync… (on iOS, the server button), type the server's
   address, and Sign In. A browser opens on the provider's page with the
   code filled in; once you sign in there, the app syncs as you.

Each user has a notebook of their own. `$metadata` stays readable without
signing in, so the app can find out where to sign in.

## On Linux, without Docker

The Docker image is the way to host the server, on a machine of your own,
in an LXC container, or on a Raspberry Pi (it's built for arm64 too). For a
machine that can run neither, the AppImage carries the server as well. It
never starts on its own: opening the image starts the app, and the server
runs only when asked:

```sh
./SimpleNotes-*.AppImage --server -StoreURL notes.sqlite -Port 8080 -Localhost NO
```
