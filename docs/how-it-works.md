# How TopoText works

## The shape

The shape is Apple Notes' topotext, which is RGA (a replicated growable
array), with Fugue's ordering:

- **Every UTF-16 unit ever typed has an id**, `(replica, clock)`. The replica is
  the copy that typed it; the clock is a Lamport counter that every edit ticks.
  Units typed in one go form a *run*: consecutive ids, each placed after the one
  before it. Typing on at the end of your own latest run makes it longer, so a
  typed paragraph is one run, not one object per keystroke.
- **A character is placed by another one**, its *origin*: as its right
  child (after it), or as its left child (before it), in Fugue's tree. A
  character typed is the right child of the one before it, unless that one
  has a right child already; then it is the left child of the node right
  after it. The text is the tree read in order: a node's left subtree, the
  node, its right subtree; children on one side newest first, by
  `(clock, replica)`. So text typed at a place lands where the typist saw
  it, and two people typing at one place, forwards or backwards, each get
  their text unbroken, never interleaved with the other's. The order is the
  same whichever copy heard of what first. RGA is this tree with right
  children only, so data from before (format 1) reads in its order.
- **Deleting a character tombstones it.** It keeps its id and its place, so it
  can still anchor what others insert next to it. Its text and attributes are
  dropped; who deleted it, and when, is kept. Once every copy has seen the
  deletion (`collectTombstonesSeenBy:`, given the version all copies have),
  a tombstone nothing is placed by goes entirely, and the rest that follow
  one another become one record. What went is remembered as ranges of ids,
  so a copy that had not seen the deletion yet cannot bring the text back.
- **Attributes are per-character registers, one per key**, and the last writer
  wins. Bold set here and italic set there at the same time are both kept.
  Applying bold to existing characters does not spread to a run someone
  inserts inside that span at the same time; the inserted run keeps the
  attributes it was typed with. This is the Notes race, and it is kept on
  purpose.
- **Paragraph formatting** (a heading, a list item, whether a checklist item
  is ticked) is set on every character of the paragraph, its newline too
  (`addParagraphAttributes:range:`). When those disagree after a merge, the
  newline's value wins (`paragraphAttributesAtIndex:keys:`); the last
  paragraph has no newline, so its first character's does. Text typed into a
  line that was made a list item elsewhere ends up in the item.
- **Tables** (`TTTable`) merge as Apple Notes' do. Row order and column
  order are each a TopoText whose characters stand for the rows (or
  columns): a row's identity is its character's id, so rows added apart are
  both kept, in one order. Each cell is a TopoText, keyed by its row's id
  and its column's. Edits to a cell merge as text, and a column removed
  takes its cells with it. A table is exchanged and merged whole, because
  its pieces' clocks are each their own. The papers behind it, and behind
  TopoText's text, are in [docs/References.md](References.md).
- **Undo** of one's own edits survives others' (`TopoText (Undo)`). Between
  `-beginUndoStep` and `-endUndoStep` a copy keeps what it edits by the
  characters' ids, not their positions. Undone after other edits were merged
  in, it does what was meant: text it typed comes out wherever it is now,
  text it deleted goes back where it was, and the attributes it set are set
  back, only those keys. The undo is an ordinary edit, so it merges and
  syncs. It is recorded in turn, as the step that redoes it.
- **Values are property-list types**: strings, numbers, data, dates, and arrays
  and dictionaries of them. NSNull removes a key. An editor maps its fonts and
  colours to such values and back.

## Merging, deltas, versions

- `-version` records what a copy has seen: for each replica, the clock of its
  latest edit.
- `-deltaSinceVersion:` is what a copy at that version lacks: the runs new to
  it, every deletion, and the attribute registers it has not seen.
- `-applyData:error:` takes a delta or a whole state. Applying one twice, or
  out of order, does no harm. A delta made for a copy that had seen more than
  this one is refused (`TopoTextErrorMissingHistory`) and changes nothing; the
  whole state always applies.
- **`-data` is canonical.** Two copies that have seen the same edits write the
  same bytes, whatever order they heard of them in, on every system. A golden
  test checks that on both Foundations. That property is what makes merges
  safe to compute on either side of a sync.

## In an editor

- A merge returns `TTEdit`s: each insert, delete and attribute change, in
  order, with ranges in the text as the previous edits left it. Apply them to
  the `NSTextStorage` one by one (`-applyToAttributedString:`) instead of
  replacing the whole text, and the selection and scroll position survive.
- `-anchorAtIndex:` and `-indexForAnchor:` keep a cursor or a comment pinned to
  a character while others edit around it. An anchor on a deleted character
  resolves to where that character was.
- `-setString:` and `-setAttributedString:` change the text to a new value
  by the fewest edits, for code that has only the new value (a snapshot, a
  version restored). They diff the two (Myers' algorithm, by lines and then
  by characters within the lines that changed), so what is the same keeps
  its characters, and another copy's edits in it merge where they were
  made. `TTStringChanges()` gives the same changes, for showing them.

## Replicas

Two copies must never write as the same replica at once, or their ids would
collide. By default every text, and every `-tt_textForKey:`, takes a fresh
random 64-bit replica, so each editing session is its own writer. The cost is
one entry per session in the version.

Plain text stored before TopoText is adopted with
`+textSeededWithString:replica:`. The seed run's id comes from the string
alone, so two devices that adopt the same text end up with it once, not twice.

## The wire format

The wire format is described at the top of `TTCoding.m`. Text is WTF-8,
because a run split by a remote insert between the two halves of a surrogate
pair must still encode. The format is versioned (its third byte): this
TopoText writes format 2 (left children, deleters, the ids collected) and
still reads format 1, so a text stored before is read and written anew.

## The files

| File | What it does |
|---|---|
| `Sources/TopoText/include/TopoText/TopoText.h` | The public API: `TopoText`, `TTId`, `TTVersion`, `TTEdit` |
| `Sources/TopoText/TopoText.m` | The text: runs, local edits, integration (Fugue), deltas, edits reported, undo, tombstones collected |
| `Sources/TopoText/TTCoding.m` | The wire format: varints, WTF-8 text, attribute values, payloads, versions |
| `Sources/TopoText/TTTable.m` | Tables that merge: row and column orders, a TopoText per cell |
| `Sources/TopoText/TTInternal.h` | Runs, registers, payloads, shared by both |
| `Sources/TopoTextSync/` | `TTSyncMerger`, `TTSyncResolver`, `NSManagedObject (TopoText)` |
| `Tests/` | Unit tests, the convergence fuzz, ODataSync end to end |
| `Examples/SimpleNotes/` | The notes app and its server |
| `Scripts/xcodeproj.py` | The Xcode projects and workspace, written |
| `Scripts/prepare-appdir.sh`, `package-appimage.sh`, `appimage/` | SimpleNotes' AppImage |
| `Docker/server.Dockerfile`, `collect-server.sh` | The server's image, FROM scratch |
