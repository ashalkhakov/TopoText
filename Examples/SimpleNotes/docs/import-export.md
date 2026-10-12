# Export and import

Every note as Markdown, and notes read back from SimpleNotes' exports and other apps'.

**File > Export All Notes…** (on iOS, **Export All Notes** in the folder
list's + menu, saved to Files) writes every note as Markdown, in a zip. On
the Mac and GNUstep, a name given without `.zip` writes a folder instead.
The layout:

- **Folders** become folders. Notes in no folder sit at the top. Smart
  folders and Recently Deleted are left out.
- **Each note** is `<title>.md`, dated when it was last edited.
- **Images and files** are written to `_attachments/<title>/` beside the
  note, and linked from it.
- **Tables** become GFM tables.
- **Formatting** maps both ways (`SNMarkdown.h`):

| In the note | In Markdown |
|---|---|
| Title, heading, subheading | `#`, `##`, `###` |
| Monospaced | a fenced code block |
| Bulleted, dashed, numbered list | `*`, `-`, `1.` |
| Checklist | `- [ ]`, `- [x]` |
| Indent | four spaces per level |
| Bold, italic, strikethrough | `**`, `*`, `~~` |
| Underline | `<u>` |
| Text colour, highlight | `<span data-color="pink">`, `<mark data-color="mint">` |
| Block quote | `>` before the line (a heading's or list item's too) |

Both run in the background, with a window that shows how far they've got
("Importing 1,240 of 25,000 notes…") and a Stop button; the notes can be
read and edited meanwhile. Imported notes are saved a few hundred at a
time, so a large import uses little memory, appears as it goes, and what
was imported before a Stop (or a failure) is kept. When it's done, the
window says what happened and lists anything left out (the rest goes to
the log). On iOS, the same shows in a sheet. The sync that sends an
import to the server says how far it is too, in the status line:
"Sending 3,000 of 25,000 changes…", then "Merging … notes' text…".

**File > Import Notes…** reads such an export back. It also reads other
apps' exports:

- **A folder of Markdown**, or a zip of one (Obsidian's vault, Joplin's or
  Bear's Markdown export). Each `.md`, `.txt` or `.html` file becomes a
  note, and folders with notes in them become folders.
- **Trilium's export**, Markdown or HTML (its default). Trilium's
  `!!!meta.json` gives each note's title and type. A note with notes under
  it becomes a folder, and its own text becomes a note in that folder.
  Code notes become monospaced notes; image and file notes become notes
  holding them. Clones are imported once. Canvases, relation maps and
  other note types are skipped.

What import also does:

- **Images and files** a note links to are attached to it, if they're in
  the export.
- **GFM tables** become tables.
- **Where notes go:** everything goes into a new folder named after what
  was imported. When that is a single folder (Trilium's export of one note
  and those under it, or a zip of one folder), that folder is the one made,
  not one more around it. A single Markdown file goes straight into the
  chosen folder instead.
