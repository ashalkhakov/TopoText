# SimpleNotes

A small Apple Notes: folders (and folders in folders), notes in rich text
with headings, lists and checklists, links, images and tables, tags,
search, pinning, sorting and grouping by date, Recently Deleted, and moving
notes between folders. It runs
on macOS and on Linux (AppKit, through GNUstep), and on iPhone and iPad.
Every note is kept on the device and works offline. Notes sync with a
server, `simplenotes-server`, which serves them over OData.

When the same note is edited on two devices that couldn't reach each other,
both edits end up in the note. The note's body is a [TopoText](../../README.md),
and [ODataSync](https://github.com/ashalkhakov/ODataKit/tree/master/Source/ODataSync)
merges it through `TTSyncResolver`. The note is not settled for one side.

| The AppKit app, on GNUstep (the Eau theme) | On iOS |
|---|---|
| ![SimpleNotes on GNUstep](Screenshots/gnustep.png) | <img src="Screenshots/ios.png" width="240" alt="SimpleNotes on iOS"> |

## What there is

| Part | Where | What |
|---|---|---|
| The device | `Shared/` | Foundation and Core Data only, shared by every app |
| The AppKit app | `AppKit/` | macOS and GNUstep: `MainMenu.xib`, `NotesWindow.xib` (folders, notes, the note), `TextPanel.xib` |
| The iOS app | `iOS/` | Folders, then a folder's notes, then the editor (`SNEditorViewController.xib`, with a format bar over the keyboard) |
| The server | `Server/SNServer.m` | ODataKit's server (HTTPServerKit, ODataService) with ODataSync's part of it |
| The model | `SimpleNotes.xcdatamodeld` | `Folder` and `Note`; the classes' properties are generated as each target builds (Codegen: Category/Extension), by Xcode or by FreeCoreData's momc |
| Tests | `Tests/` | The device against the service in one process; the text view's binding; migration from an older model; two devices through the running server; each app driven from within |

The device, in `Shared/`:

- **`SNNotes`**: the store (SQLite, with persistent history), the ODataSync
  engine, and the queries and changes the views make. A sync runs on its own
  thread while the views carry on. Saves made in the meantime wait for it
  to finish.
- **`SNNoteEditor`**: one open note's TopoText, a session with its own
  replica. Before the note is written again, the editor merges in what the
  last sync brought, and hands the resulting edits to the view.
- **`SNTextBinding`**: keeps a text view's `NSTextStorage` (AppKit's or
  UIKit's) and the editor's TopoText the same, in both directions. What the
  user types goes into the text as they type. What a sync merged comes into
  the storage as edits, and the selection moves along with them. It also
  follows Apple Notes' typing rules for lists (see "Lists and checklists").
- **`SNListLayoutManager`**: draws list markers and checkboxes beside the
  text, and tells which checkbox a click or tap landed on.
- **`SNResolver`**: merges a note's body; its title becomes the merged first
  line. Other properties are taken from whichever side changed them, or from
  the later writer if both did. An edit outlives a deletion that didn't see it.
- **`SNMigration`**: brings a store made by an older version of the model up
  to date when it opens (see "Model versions" below).

## Recently Deleted

Deleting a note moves it to Recently Deleted, as in Apple Notes:

- It leaves its folder's list and search. In Recently Deleted it's read-only
  and shows how many days it has left.
- **Recover** puts it back in its folder, or in All Notes if the folder is
  gone. Moving it to a folder also recovers it.
- **Delete Immediately**, or **Delete All**, removes it for good, on every
  device.
- After 30 days it's removed for good. Each device checks when it opens and
  after every sync.
- Deleting a folder moves its notes to Recently Deleted.

Deleting is an ordinary change to the note (its `deletedAt`), so it syncs and
merges like any other edit. A note deleted on one device while edited on
another ends up deleted on both, with the edit kept, ready to recover.

## Moving notes

On the Mac and GNUstep, use **File > Move To**, or drag a note onto a folder.
Dropping it on Recently Deleted deletes it. On iOS, swipe the note and choose
**Move**.

## Folders in folders

A folder can hold other folders, as in Apple Notes. A folder lists its own
notes; the folders in it appear under it in the sidebar.

- **On the Mac and GNUstep**, **New Folder** makes the folder inside the
  folder chosen (or at the top when none is). Drag a folder onto another to
  move it in, or onto All Notes to move it to the top.
- **On iOS**, swipe a folder and choose **Move**.
- **Deleting a folder** deletes the folders in it too. All their notes go to
  Recently Deleted.

Two devices can each move a folder into the other while apart. When they
sync, the folders would be inside each other. Each device then breaks the
loop at the folder whose ID sorts first, which shows at the top level. Every
device does the same, so nothing is lost and all show the same tree.

## Links

A web address you type becomes a link, as in Apple Notes. That link is
only shown, not kept: it's worked out from the text each time.
**Format > Add Link…** (⌘K; on iOS, the format bar's link button) puts a
link on the selected text, and that one is part of the note and syncs with
it.

A link can also point to another note: **File > Copy Link to Note** (on iOS,
press and hold a note in the list) copies a `simplenotes://note/<id>` link.
Paste it with Add Link, and clicking it opens that note.

## Images

**File > Attach File…** (⇧⌘A), or paste or drop an image; on iOS, the format
bar's photo button. An image is one of the note's attachments, with its own
record that syncs like a note does. The note's text holds one character for
it. Images larger than 1600 pixels across are scaled down.

A note's text can reach a device before its attachment does. Until the
attachment arrives, a grey box takes its place. Deleting a note for good
deletes its attachments.

## Tables

**Format > Table** (⌥⌘T; on iOS, the format bar's table button) puts a table
in the note. Click or tap a table to edit its cells, and to add or remove
rows and columns. In this version cells are edited in a table editor, not
in place in the note.

A table merges as Apple Notes' do, with no cell, row or column lost when
two devices edit apart. It's a `TTTable`, from TopoText. Its rows and
columns are each kept in an order every device agrees on, and each cell is
a TopoText of its own. So:

- Rows (or columns) added on two devices are both kept.
- Edits to different cells both stand; edits to one cell merge character
  by character.
- A column (or row) removed takes its cells with it, including anything
  typed into them meanwhile.

When the same table changed on two devices, the sync merges the two whole
tables (`SNResolver`).

## Tags

Type `#` and a word in a note, and that word becomes a tag, as in Apple
Notes: `#errands`, `#q3-plan`. A tag can contain letters, digits, `-` and
`_`, needs at least one letter, and starts the text or follows a space. Tags
are matched whatever their case.

Tags are read from the note's text, so they sync with it and need nothing
in the model. The sidebar (on iOS, the folder list) shows every tag with
how many notes have it. Choose a tag to list those notes. In the editor,
tags appear in the accent colour.

## Sorting and grouping

**View > Sort By** (on iOS, the **…** menu over a list) sorts every list by
**Date Edited** (the default), **Date Created** or **Title**. Pinned notes
always come first. **Group By Date** puts headings over the list: Pinned,
Today, Yesterday, Previous 7 Days, Previous 30 Days, then each month of this
year, then each earlier year. Sorted by title, a list has just Pinned and
Notes. The choice is the device's own (user defaults), as in Apple Notes.

## Model versions

`SimpleNotes.xcdatamodeld` holds every version of the model:

- **Version 2** added `Note.deletedAt` (Recently Deleted).
- **Version 4** added `Attachment` (images and tables in notes).
- **Version 3** added `Folder.parent` (folders in folders). It also renamed
  `Note.updated` to `edited`, with Renaming ID `updated` so migration keeps
  the dates. On Apple's Core Data, `updated` is `NSManagedObject`'s own
  (`-isUpdated`), and key-value coding gets that rather than the attribute.
  Syncing goes through key-value coding, so on macOS and iOS a note's edit
  date never reached the server.

To add a version:

1. Add a version in Xcode (or copy the latest `.xcdatamodel` and name it
   `SimpleNotes 4.xcdatamodel`), and give it the next
   `userDefinedModelVersionIdentifier`.
2. Make it current in `.xccurrentversion`.
3. Run `Scripts/xcodeproj.py`.

Keep each change additive (new optional attributes, new entities), so a
lightweight migration covers it. When you rename, set the Renaming ID to the
old name, as version 3 does, so the inferred mapping carries values over.
FreeCoreData follows Renaming IDs from its `inferred-mapping-renaming`
branch on.

What happens when a store opens:

- **On a device**, `SNNotes` migrates its SQLite store to the current
  version before opening it. The migration keeps what ODataSync needs: the
  store's metadata (including its replica ID) and its history. So a change
  saved before the update and not yet sent still goes at the next sync. The
  previous store is kept beside the new one, as `.old`.
- **On the server**, a SQLite store is migrated the same way. A PostgreSQL or
  MariaDB store migrates itself, in place.
- **Devices not yet updated** keep syncing: they name their model's version
  with every request, and the server accepts their writes, renaming
  `Updated` to `Edited` on the way (`SNUpgradeBody`).

Core Data's automatic migration can't do the device's part, because a store
holding ODataSync's entities wasn't made from any of the compiled models as
they are. `SNMigration` finds the right version and migrates it explicitly.

## Running it

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
- `AllowAnonymous NO` refuses requests that don't say who they're from,
  once a sign-in is set. Every device syncs every note: one shared notebook.

Each setting can also be an environment variable: `SN_` and the setting's
name in capitals, words split by `_` (`SN_STORE_URL`, `SN_SERVICE_ROOT`,
`SN_TRUSTED_USER_HEADER`).

### In Docker

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

Behind a reverse proxy (Nginx Proxy Manager, Caddy, Traefik), forward a
host to the container's port 8080, and give the address users reach as
`SN_SERVICE_ROOT`, for example `https://notes.example.com/odata/`.
HTTPServerKit's proxy settings work as `SN_` variables too:

- `SN_TRUSTED_USER_HEADER` takes the signed-in user from a header the
  proxy sets.
- `SN_PROXY_SECRET_HEADER` together with `SN_PROXY_SECRET_ENVIRONMENT`
  accepts only requests that carry the proxy's secret.
- `SN_CORS_ORIGINS` sets the allowed origins.

Sign-in with OIDC (`SN_JWT_ISSUER`, `SN_JWT_AUDIENCE`) works the same way.
Separating each user's notes is still to come (see "Not yet").

### On Linux, without Docker

The Docker image is the way to host the server, on a machine of your own,
in an LXC container, or on a Raspberry Pi (it's built for arm64 too). For a
machine that can run neither, the AppImage carries the server as well. It
never starts on its own: opening the image starts the app, and the server
runs only when asked:

```sh
./SimpleNotes-*.AppImage --server -StoreURL notes.sqlite -Port 8080 -Localhost NO
```

The apps:

- **macOS**: open `TopoText.xcworkspace` (ODataKit checked out beside this
  repository, at `../ODataKit`) and run the **SimpleNotes** scheme. Then
  choose **SimpleNotes > Server…** and give `http://127.0.0.1:8080/odata/`.
- **iPhone or iPad**: the **SimpleNotes-iOS** scheme. Set the address with
  the server button at the top left. The simulator reaches the Mac at
  `127.0.0.1`. To run on a device, put `DEVELOPMENT_TEAM = <your team>` in
  `iOS/Local.xcconfig`.
- **GNUstep**, with TopoText, ODataKit and FreeCoreData installed:

  ```sh
  make -C Examples/SimpleNotes && openapp Examples/SimpleNotes/SimpleNotes.app
  ```

  For the Eau theme (gnustep-patches' `build-gnustep.sh` builds it), set it
  in the app's defaults, as our other apps' launchers do:
  `defaults write SimpleNotes GSTheme Eau`. The self-test does this itself.

To try two devices on one Mac or Linux machine, give a second instance a
store of its own: `SimpleNotes -SNStore /tmp/second.sqlite`.

## Releases

Tag a version (`git tag v0.1.0 && git push --tags`), and the workflows build
and attach:

- **macOS** (`release.yml`): `SimpleNotes-macOS-<version>.zip`, universal.
  It is signed with a Developer ID and notarized when the `production`
  environment has the secrets `MACOS_CERTIFICATE` (a base64 .p12),
  `MACOS_CERTIFICATE_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and
  `NOTARY_PASSWORD`; otherwise it's unsigned, and named so. Either way it
  must pass its self-test first.
- **Linux** (`release.yml`): `SimpleNotes-<version>-x86_64.AppImage`,
  built on Ubuntu 22.04 so it runs there and on anything newer. It is
  checked on a clean Ubuntu: its own server is started and seeded, and the
  app's self-test runs against it.
- **iOS** (`release.yml`): `SimpleNotes-iOS-<version>-unsigned.ipa`, to be
  signed for TestFlight and the App Store once there is an account, and a
  simulator build. The simulator build must pass its self-test.
- **The server's image** (`docker.yml`): pushed to
  `ghcr.io/ashalkhakov/simplenotes-server:<version>` and `:latest`, for
  amd64 and arm64. Every push builds it and checks it on SQLite and
  PostgreSQL.

Run `release.yml` by hand to build any branch's packages as artifacts,
without releasing.

## Checked

```sh
make -C Examples/SimpleNotes check
```

This runs four things:

- **The tests.** Two devices and the service run in one process: edits made
  apart, a deletion against an edit, an open editor merged while its own
  typing is kept, folders moved into each other apart, tags, sorting and
  grouping, migrations from each older version, and the text view's
  binding both ways.
- **Two devices through the server, over HTTP**
  (`Tests/serve-and-check.sh`, `SimpleNotes --check`). With `SN_STORE_ARGS`,
  the server stores in PostgreSQL or MariaDB instead.
- **The AppKit app driven from within** (`SimpleNotes --self-test`, under
  `xvfb-run` where there's no display). A note is chosen in the list, text
  is typed into the window's text view, and Bold is sent up the responder
  chain. Two lines become a checklist, a click on the first checkbox ticks
  it, and Return starts a third item. The sidebar must show Projects
  inside Work and the tags; a tag and a nested folder list their notes; a
  folder moves to the top; Sort By Title regroups the list. A second device
  must see all of it. With `SN_SELF_TEST_SNAPSHOT=<file.png>`, the window is
  saved as a picture at that point; that's how the screenshots above were
  made.
- **The iOS app's self-test, in a simulator** (`Tests/ios-self-test.sh`;
  macOS only). It does the same through the iOS view controllers.

CI runs all of these: macOS and iOS against Apple's Core Data, and GNUstep
against FreeCoreData, SQLite, PostgreSQL and MariaDB.

## Rich text

A note's text uses plain values that sync and merge the same way
everywhere. `SNRichText` turns them into each system's fonts, indents and
list markers, and back.

- **Per character:** `bold`, `italic`, `underline`, `strike`.
- **Per paragraph:** `style` (`title`, `heading`, `subheading`, or `mono`;
  none is body), `list` (`bullet`, `dash`, `number`, or `check`), `checked`,
  and `indent` (1 to 8).

Character formatting is per character, and the last writer wins per
attribute, as in TopoText. Bold applied to a line does not spread to text
someone else typed into it at the same time.

Paragraph formatting is kept on every character of the paragraph,
including its newline. When those disagree after a merge, the newline's
value wins (TopoText's `Paragraphs` category), and the view shows the whole
paragraph that way. So a line that one device turned into a checklist item
stays one when another device typed into it meanwhile. A checklist item's
`checked` is a single register, so the last tick or untick wins.

## Lists and checklists

The Format menu (AppKit) and the format bar's menus (iOS) have Apple Notes'
paragraph styles and lists, with the same shortcuts: Title ⇧⌘T, Heading ⇧⌘H,
Subheading ⇧⌘J, Body ⇧⌘B, Monostyled ⇧⌘M, Bulleted List ⇧⌘7, Dashed List
⇧⌘8, Numbered List ⇧⌘9, Checklist ⇧⌘L, Mark as Checked ⇧⌘U, and indentation
with ⌘] and ⌘[.

Typing works as in Apple Notes:

- Return in a list item starts the next item. A new checklist item starts
  unticked.
- Return on an empty item ends the list, or outdents it first if it is
  indented.
- Delete at the start of an item removes its marker. A second Delete joins
  the line to the one above, which keeps the upper line's formatting.
- Tab and Shift-Tab indent and outdent an item.
- Return after a title, heading or subheading starts a body line.

Clicking (or tapping) a checkbox ticks it. Numbered items count up within
their indent level; items indented further don't interrupt the count.

**Format > Move Checked to Bottom** (on iOS, in the list menu) moves the
ticked items of the checklist at the insertion point below the unticked
ones. **Keep Checked at Bottom** does that every time an item is ticked,
which is Apple Notes' "Automatically" setting. Only the ticked items that
are out of place move, and each move is a deletion plus an insertion. So if
another device was typing into an item at the moment it moved, that text
stays where the item was.

## Not yet

- **One shared notebook.** A notebook per user means a handler on the
  server (an `ODataSyncSetHandler` that filters by the signed-in user).
- **Peer sync between devices.** ODataSync can do it (`ODataSyncPeerServer`).
  ODataKit's Device app shows how; SimpleNotes doesn't have it yet.
- Editing a table in place in the note, files other than images, smart
  folders, a sort order per folder, and undo across a merge (the undo stack
  is cleared when a sync changes the open note).
