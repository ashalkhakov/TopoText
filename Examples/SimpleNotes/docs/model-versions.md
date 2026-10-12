# Model versions

How the Core Data model has changed, how to add a version, and how stores are migrated.

`SimpleNotes.xcdatamodeld` holds every version of the model:

- **Version 2** added `Note.deletedAt` (Recently Deleted).
- **Version 3** added `Folder.parent` (folders in folders). It also renamed
  `Note.updated` to `edited`, with Renaming ID `updated` so migration keeps
  the dates. On Apple's Core Data, `updated` is `NSManagedObject`'s own
  (`-isUpdated`), and key-value coding gets that rather than the attribute.
  Syncing goes through key-value coding, so on macOS and iOS a note's edit
  date never reached the server.
- **Version 4** added `Attachment` (images and tables in notes).
- **Version 5** added `Folder.filter` (smart folders), `Folder.sortOrder`
  (a folder's own order) and `Attachment.name` (files).
- **Version 6** added `owner` to every entity (a notebook per user).
- **Version 7** added `NoteVersion` (version history, kept by the server).

To add a version:

1. Add a version in Xcode (or copy the latest `.xcdatamodel` and name it
   `SimpleNotes 8.xcdatamodel`), and give it the next
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
- **A server not yet updated** does not take a newer device: it answers
  "The service has no schema version N", and the device doesn't sync until
  the server is updated. So update the server first, then the apps.

Core Data's automatic migration can't do the device's part, because a store
holding ODataSync's entities wasn't made from any of the compiled models as
they are. `SNMigration` finds the right version and migrates it explicitly.
