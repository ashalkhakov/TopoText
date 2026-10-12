# Using SimpleNotes

What each feature does, on the Mac, on Linux and on iOS, and how it syncs.

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
  move it in, or onto All Notes to move it to the top; or choose
  **File > Move Folder To** (which also works where dragging in the
  sidebar doesn't, as on GNUstep for now).
- **On iOS**, swipe a folder and choose **Move**.
- **Deleting a folder** deletes the folders in it too. All their notes go to
  Recently Deleted.

Two devices can each move a folder into the other while apart. When they
sync, the folders would be inside each other. Each device then breaks the
loop at the folder whose ID sorts first, which shows at the top level. Every
device does the same, so nothing is lost and all show the same tree.

## Find and Replace

**Edit > Find** has Apple Notes' items:

- **Search** (⌥⌘F) goes to the search field, which searches every note.
- **Find…** (⌘F), **Find and Replace…**, **Find Next** (⌘G), **Find
  Previous** (⇧⌘G), **Use Selection for Find** (⌘E) and **Jump to
  Selection** (⌘J) work in the open note. On macOS they use the find bar
  over the note. On GNUstep they use its Find panel, which includes
  Replace.

On iOS 16 and later, **Find in Note** in the note's ••• menu opens the
system's find navigator, and so does ⌘F on a hardware keyboard. Replace is
offered there when the note can be edited, so not in Recently Deleted.

A replacement is an ordinary edit of the note's text: it syncs and merges
like typing.

## Print and Export as PDF

**File > Print…** (⌘P) and **File > Export as PDF…** put the open note on
paper as it is now, including typing not yet saved: lists and checkboxes,
quotes, colours and highlights, images, files' cards, and tables with their
cells. Pages break between lines. Colours are the light ones, whatever the
window is showing. On macOS and GNUstep this is AppKit's print operation,
on a text view of the page's width laid out for the purpose; GNUstep writes
the PDF through cairo.

On iOS, the note's ••• menu has **Print**, which opens the system's print
sheet, and **Export as PDF**, which offers the file to Save to Files,
AirDrop, Mail and so on. Pages are A4, or Letter where inches are used.

## Collapsed sections

A title, heading or subheading with something under it has a chevron in the
margin to its left. Clicking (or tapping) it collapses the section: what
follows the heading, down to the next heading at the same level or higher,
is hidden. **Format > Collapse All Sections** and **Expand All Sections**
(on iOS, in the note's ••• menu) do all of them at once.

Collapsing is a paragraph attribute of the heading, `collapsed`, so it syncs
and merges like other formatting. Hiding is the view's alone: the text is
unchanged, and export and search see all of it. The insertion point moves
past a hidden section rather than into it, and Return at the end of a
collapsed heading expands it first, so what you type next is visible.

## Sharing into SimpleNotes

**On iOS**, SimpleNotes is in the share sheet. Text, a web page (its title
and link) or pictures shared from another app go into a new note at the
top, the next time SimpleNotes opens or comes back. The sheet's text can
be changed before it's posted.

**On the Mac and on Linux**, **Services > Add to SimpleNotes** makes a note
of what is selected in another app: text, a link or a picture. The note
opens at once. On GNUstep the service is listed once `make_services` has
run after the app was installed.

Both go the same way. The item is written as Markdown with its pictures
beside it, into an inbox: on iOS, the container of the App Group the app
and the extension share (`group.io.github.ashalkhakov.SimpleNotes`); on the
Mac and Linux, a temporary folder. The app imports it as a note at the
top, as File > Import would, and removes it from the inbox
(`Shared/SNShares.h`). The extension needs neither the store nor Core
Data.

To sign the app and its extension for a device, the team in
`iOS/Local.xcconfig` needs the App Group. If Xcode's automatic signing
doesn't add it, add it to both identifiers in the Apple Developer account.

## Version history

**File > Version History…** (on iOS, **Version History** in the note's •••
menu) lists a note's earlier versions, the newest first. Choosing one shows
it beside the note as it is now: what restoring it brings back is
highlighted, and what it takes away is struck through. **Restore This
Version** makes the note as it was then.

The server keeps the versions, so every device has the same history. When a
write is about to change a note's text and the note's newest version is at
least ten minutes old, the server keeps the text as it was before the write
(`Server/SNVersions.h`). A version is a clean copy of the text and its
formatting, without the deleted characters a note's text accumulates, so it
stays small. Versions are thinned as they age: all of the last day, the
newest of each hour for a week, the newest of each day for 30 days, none
older. They are a synced entity, `NoteVersion` (model version 7), that
devices only download (`ODataSync.direction` `down`), and the server
refuses a client's writes to them. A note deleted for good takes its
versions with it.

Edits made offline make no versions of their own; they reach the server as
one write when the device syncs. Offline, the versions already downloaded
still show what has changed since each of them.

Restoring changes the note by the fewest edits it takes. TopoText's
`-setAttributedString:` diffs the two texts (Myers' algorithm, line by line
and then character by character), so text that is the same keeps its
characters. Another device's typing in that text, merged later, stays where
it was typed. The restore syncs and merges like typing.

## Gallery and attachments

**View > as Gallery** (⌘2) shows the notes as cards: each note's first
image, or the start of its text, with its title and date under it. The
cards take the list's place, and its pane widens for them. Choosing a card
opens its note, as choosing a row does. **View > as List** (⌘1) brings the
list back. The choice is remembered. Window > Notes is ⌘0, as in Apple Notes.

**View > Show Attachments** (⌘3) opens a window with every image in the
notes (**Photos**) and every file (**Files**), the newest first. Choosing
one shows its note in All Notes, scrolled to where it is. An attachment
taken out of its note's text is kept (Undo, or another device, can bring
it back) but isn't listed.

On iOS, a list's ••• menu has **View as Gallery** (and the gallery's has
**View as List**), and the folders' menu has **View Attachments**.

Pictures are made small, when their cards come into view, one at a time,
and kept for a while; an image's data isn't held in memory once its
picture is made.

## Links

A web address you type becomes a link, as in Apple Notes. That link is
only shown, not kept: it's worked out from the text each time.
**Format > Add Link…** (⌘K; on iOS, **Add Link** in the menu over the
selected text, or under the format bar's paperclip) puts a link on the
selected text, and that one is part of the note and syncs with it.

A link can also point to another note: **File > Copy Link to Note** (on iOS,
press and hold a note in the list) copies a `simplenotes://note/<id>` link.
Paste it with Add Link, and clicking it opens that note.

## Images

**File > Attach File…** (⇧⌘A), or paste or drop an image; on iOS, **Choose
Photo** under the format bar's paperclip. An image is as wide as it is, or
as the text when the text is narrower; it follows the text's width when the
window or the screen turns. It's one of the note's attachments, with its own
record that syncs like a note does. The note's text holds one character for
it. Images larger than 1600 pixels across are scaled down.

A note's text can reach a device before its attachment does. Until the
attachment arrives, a grey box takes its place. Deleting a note for good
deletes its attachments.

## Files

Any other file (a PDF, a document, a recording) goes in the same way:
**File > Attach File…**, paste, or drop it; on iOS, **Attach File** under
the paperclip. It shows as a card with the file's icon, name, kind and
size. Double-click the card to open the file in its own application; on
iOS, tap it to see it in Quick Look. A file syncs whole with the note, so
it can be no larger than 25 MB.

## Tables

**Format > Table > Insert Table** (⌥⌘T; on iOS, the format bar's table
button) puts a two-by-two table in the note, and you type into its first
cell. Tables are edited where they are in the note, as in Apple Notes:

- **Tab** goes to the next cell (Shift-Tab, the one before; on iOS, with a
  hardware keyboard, or the bar's Next Cell button). Tab in the last cell
  adds a row. Return starts a new line in the cell.
- **Add Row Above/Below, Add Column Before/After, Delete Row, Delete
  Column** are in Format > Table and in a cell's context menu. On iOS
  they're on the table button in the bar over the keyboard, and in a cell's
  edit menu.
- **Bold, italic, underline, strikethrough and links** work in a cell as in
  the note: from the Format menu and its shortcuts, or on iOS from the
  format button in the bar over the keyboard. A link in a cell opens as one
  in the note does, by a click or a tap. Styles and lists don't, as in
  Apple Notes. Each cell has a text binding of its own (`SNTextBinding`,
  over the cell's TopoText).

Each table is a grid of text views (`SNTableGrid`) laid over its place in
the note. That place is the table's character, which keeps the grid's room.

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

**View > Sort Folder By** (on iOS, the same menu in a folder) gives the
folder shown an order of its own. That order belongs to the folder, so it
syncs with it. **Default** goes back to the device's order.

## Smart folders

A smart folder lists the notes that match its rules, from any folder, as
in Apple Notes. **File > New Smart Folder…** (⌥⇧⌘N; on iOS, **New Smart
Folder** in the folder list's + menu) asks for its name and rules:

- **Tags:** all of them, or any.
- **Edited** or **Created** within a day, 7, 30 or 90 days, or a year.
- **Checklists:** any, ticked items, or items not ticked.
- **With attachments**, **Pinned**.

A note is included when it matches all of the rules, or any of them, as
you choose. Nothing is moved into a smart folder, and a note made in one is
made in no folder. **Edit Smart Folder…** (on iOS, swipe it and choose
**Edit**) changes its rules. It shows a gear before its name. Its rules are
kept in the folder (`Folder.filter`, as JSON), so they sync with it.

When two devices change a smart folder's rules apart, the sync merges them
rule by rule (`SNResolver`), rather than keeping one device's whole set:

- A rule changed on one device keeps that change.
- A rule changed on both keeps the later edit.
- Tags merge as a set: a tag added on either device is added, and a tag
  removed on either device is removed.

## Lists and checklists

The Format menu (AppKit) and the format bar's menus (iOS) have Apple Notes'
paragraph styles and lists, with the same shortcuts: Title ⇧⌘T, Heading ⇧⌘H,
Subheading ⇧⌘J, Body ⇧⌘B, Monostyled ⇧⌘M, Bulleted List ⇧⌘7, Dashed List
⇧⌘8, Numbered List ⇧⌘9, Checklist ⇧⌘L, Mark as Checked ⇧⌘U, and indentation
with ⌘] and ⌘[. **Block Quote** (⌘') draws a bar beside the paragraphs and
indents them; **Highlight** and **Text Color** each offer the five colours
and None. On iOS they are in the Aa menu.

Typing works as in Apple Notes:

- Return in a list item starts the next item. A new checklist item starts
  unticked.
- Return on an empty item ends the list, or outdents it first if it is
  indented.
- Delete at the start of an item removes its marker. A second Delete joins
  the line to the one above, which keeps the upper line's formatting.
- Tab and Shift-Tab indent and outdent an item.
- Return after a title, heading or subheading starts a body line.
- Return in a block quote goes on quoting. Return on an empty quoted line
  ends the quote.

Clicking (or tapping) a checkbox ticks it. Numbered items count up within
their indent level; items indented further don't interrupt the count.

**Format > Move Checked to Bottom** (on iOS, in the list menu) moves the
ticked items of the checklist at the insertion point below the unticked
ones. **Keep Checked at Bottom** does that every time an item is ticked,
which is Apple Notes' "Automatically" setting. Only the ticked items that
are out of place move, and each move is a deletion plus an insertion. So if
another device was typing into an item at the moment it moved, that text
stays where the item was.

## Undo

Undo and Redo work as in any text view, and keep working when a sync
changes the open note: what you typed, deleted or formatted is undone, and
what came from another device stays. Typing goes into one undo step until
you move the insertion point or start a new line. Table cells undo the same
way; adding or deleting a table's rows and columns can't be undone yet.

The text view's own undo keeps positions, which a merge makes wrong, so it
is off. `SNTextBinding` keeps the steps instead, by the characters' ids
(`TopoText (Undo)`), in the window's undo manager (on iOS, an
`SNUndoManager` that takes only the binding's).

## Devices nearby

Sync › Devices Nearby… on the desktop, and the antenna button over the
folder list on iOS, sync your notes directly with your other devices on
the same network, without the server (ODataSync's peer sync). On iOS
the notes are served while SimpleNotes is open.

- **Sync with my devices nearby** (on iOS, **Sync with Devices Nearby**)
  makes this device one the others can reach: advertised over Bonjour
  (Avahi on Linux) and served over TLS. It also syncs by itself with each
  device found that takes this one: when the device appears, about ten
  seconds after you change something, and every five minutes. Devices
  sync one at a time, between server syncs. A device that refuses is tried
  again after half an hour. The setting stays on across launches.
- **Sync** in the list syncs with a device right away.
- The peer token renews by itself while the server is reachable, when it's
  missing or runs out within a day.
- A device syncs with another by one of two things. A **peer token** comes
  from your server while you're signed in, and lasts a day; your devices
  then trust each other even offline. **Pairing** is for a device that
  shares no server with this one: Show Pairing Code on one, Pair With
  Code… on the other (the code is good once, for two minutes).
- Edits made apart merge as they do through the server.
