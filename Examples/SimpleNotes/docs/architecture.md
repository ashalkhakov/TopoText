# How SimpleNotes is built

The parts of the app and the server, and how a note's text is kept so it syncs and merges.

## The parts

| Part | Where | What |
|---|---|---|
| The device | `Shared/` | Foundation and Core Data, shared by every app; the rich text and tables too, with no `#if`: what they need of AppKit or UIKit is `SNTextSystem.h` and `SNTableGrid+System.h`, each system's in its own folder |
| The AppKit app | `AppKit/` | macOS and GNUstep: `MainMenu.xib`, `NotesWindow.xib` (folders, notes, the note), `TextPanel.xib`; `SNTextSystem.m` and `SNTableGrid+System.m`, AppKit's part of the shared code (GNUstep's differences inside, `#ifdef GNUSTEP`) |
| The iOS app | `iOS/` | Folders, then a folder's notes, then the editor (`SNEditorViewController.xib`, with a format bar over the keyboard); UIKit's `SNTextSystem.m` and `SNTableGrid+System.m` |
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
  follows Apple Notes' typing rules for lists (see [Lists and checklists](features.md#lists-and-checklists)).
- **`SNListLayoutManager`**: draws list markers and checkboxes beside the
  text, and tells which checkbox a click or tap landed on.
- **`SNResolver`**: merges a note's body; its title becomes the merged first
  line. Other properties are taken from whichever side changed them, or from
  the later writer if both did. An edit outlives a deletion that didn't see it.
- **`SNMigration`**: brings a store made by an older version of the model up
  to date when it opens (see [Model versions](model-versions.md)).

## Rich text

A note's text uses plain values that sync and merge the same way
everywhere. `SNRichText` turns them into each system's fonts, indents and
list markers, and back.

- **Per character:** `bold`, `italic`, `underline`, `strike`, and `color`
  and `highlight`, each a colour's name: `purple`, `pink`, `orange`, `mint`
  or `blue`, Apple Notes' five. Each system shows the name in its own
  shade, in dark mode too. A name a device doesn't know (one added later)
  is shown as no colour.
- **Per paragraph:** `style` (`title`, `heading`, `subheading`, or `mono`;
  none is body), `list` (`bullet`, `dash`, `number`, or `check`), `checked`,
  `indent` (1 to 8), and `quote` (a block quote, which goes with any of
  them).

Character formatting is per character, and the last writer wins per
attribute, as in TopoText. Bold applied to a line does not spread to text
someone else typed into it at the same time.

Paragraph formatting is kept on every character of the paragraph,
including its newline. When those disagree after a merge, the newline's
value wins (TopoText's `Paragraphs` category), and the view shows the whole
paragraph that way. So a line that one device turned into a checklist item
stays one when another device typed into it meanwhile. A checklist item's
`checked` is a single register, so the last tick or untick wins.
