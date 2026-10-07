# TopoText

A rich text that merges itself. Copies of a text edited apart, on devices
that are offline or on either side of a server, become the same text again by
exchanging what each has, and nothing either side typed is lost. Nobody is
asked to pick a version.

In Objective-C 2.0 with ARC, on Apple's Foundation (macOS, iOS) and on
GNUstep. With [ODataKit](https://github.com/ashalkhakov/ODataKit)'s ODataSync,
a note's body edited on two devices merges when they sync, whether through
the service or directly between peers.

| Library | What it is |
|---|---|
| `TopoText` | The text: edits, attributes, positions, merging, deltas, the wire format. Foundation only. |
| `TopoTextSync` | Its part in an ODataSync store: a conflict resolver that merges texts, and `NSManagedObject` helpers. |

[SimpleNotes](Examples/SimpleNotes/README.md) is a small Apple Notes built on
both. It runs on macOS, on GNUstep and on iOS, keeps every note on the
device, and syncs through an OData server built on ODataKit, which can
store its data in SQLite, PostgreSQL or MariaDB. Notes edited apart on two
devices come out with both edits.

```objc
TopoText *mine = [TopoText text];                       // a replica of its own
[mine insertString:@"Hello world" atIndex:0 attributes:nil];
TopoText *theirs = [mine copyWithReplica:0];            // another device's copy

[mine insertString:@"big " atIndex:6 attributes:nil];   // apart: here...
[theirs addAttributes:@{ @"bold": @YES } range:NSMakeRange(0, 5)];  // ...and there

[mine applyData:[theirs deltaSinceVersion:mine.version] error:NULL];
[theirs applyData:mine.data error:NULL];                // a delta, or the whole state
// both: "Hello big world", "Hello" bold, byte for byte the same -data
```

## How it works

The shape is Apple Notes' topotext, which is RGA (a replicated growable
array):

- **Every UTF-16 unit ever typed has an id**, `(replica, clock)`. The replica is
  the copy that typed it; the clock is a Lamport counter that every edit ticks.
  Units typed in one go form a *run*: consecutive ids, each placed after the one
  before it. Typing on at the end of your own latest run makes it longer, so a
  typed paragraph is one run, not one object per keystroke.
- **A character is inserted after another one**, its *origin*. The characters
  inserted after the same origin come newest first, ordered by
  `(clock, replica)`. So text typed at a place lands where the typist saw it,
  and two people typing at one place each get one unbroken run that never
  interleaves with the other's. The order is the same whichever copy heard of
  what first.
- **Deleting a character tombstones it.** It keeps its id and its place, so it
  can still anchor what others insert next to it. Its text and attributes are
  dropped.
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
  TopoText's text, are in [docs/References.md](docs/References.md).
- **Values are property-list types**: strings, numbers, data, dates, and arrays
  and dictionaries of them. NSNull removes a key. An editor maps its fonts and
  colours to such values and back.

### Merging, deltas, versions

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

### In an editor

- A merge returns `TTEdit`s: each insert, delete and attribute change, in
  order, with ranges in the text as the previous edits left it. Apply them to
  the `NSTextStorage` one by one (`-applyToAttributedString:`) instead of
  replacing the whole text, and the selection and scroll position survive.
- `-anchorAtIndex:` and `-indexForAnchor:` keep a cursor or a comment pinned to
  a character while others edit around it. An anchor on a deleted character
  resolves to where that character was.
- `-setString:` and `-setAttributedString:` change the text to a new value
  with the smallest replacement, for code that has only the new value.

### Replicas

Two copies must never write as the same replica at once, or their ids would
collide. By default every text, and every `-tt_textForKey:`, takes a fresh
random 64-bit replica, so each editing session is its own writer. The cost is
one entry per session in the version.

Plain text stored before TopoText is adopted with
`+textSeededWithString:replica:`. The seed run's id comes from the string
alone, so two devices that adopt the same text end up with it once, not twice.

## With ODataSync

The model: a Binary attribute holds the state, and a String attribute beside
it may hold the plain text, so the service can `$filter` and `$search` it.

```objc
// Note: ODataSync.direction both, ODataSync.versions versions, ODataSync.modified modified
//   body       String
//   bodyText   Binary   userInfo: TopoText.text = YES, TopoText.string = body

sync.resolver = [[TTSyncResolver alloc] init];   // or -setResolver:forEntityName:

// Editing: a session's copy, stored back with its plain text.
TopoText *text = [note tt_textForKey:@"bodyText"];
[text insertString:@"…" atIndex:0 attributes:nil];
[note tt_setText:text forKey:@"bodyText"];

// After a sync changed the note under an open editor:
for (TTEdit *edit in [note tt_mergeKey:@"bodyText" intoText:text])
  [edit applyToAttributedString:textView.textStorage];
```

When versions meet, ODataSync applies a version that already includes the
other side's as it is. Only edits made without knowing of each other reach
the resolver. The resolver merges every TopoText attribute and its plain
text; the other properties are left to a fallback (`ODataSyncMergeFields` by
default). The merge comes out the same whichever side makes it, which is what
a peer's conflict requires (`ODataSyncConflict.withPeer`). The service and
peers store the state as an ordinary binary property; all merging happens on
the devices.

`Tests/TopoTextSyncTests.m` covers this end to end. Two devices and an
`ODataService` run in one process: both devices edit the same note apart and
sync through the service, then again directly as peers. Every side ends with
both edits, byte for byte. As a control, the same test with ODataSync's stock
resolver loses one side's edit.

## Building

**Xcode**: `TopoText.xcworkspace` has the frameworks (`TopoText.xcodeproj`, for
macOS and iOS), SimpleNotes, and ODataKit's project from `../ODataKit`. The
projects are written by `Scripts/xcodeproj.py`: change that script and run
it, rather than editing the projects by hand.

**macOS without Xcode's projects** (with ODataKit checked out beside this repository):

```sh
make odatakit          # ODataKit's frameworks, by its workspace, into build/ODataKit
make                   # build/libTopoText.dylib, build/libTopoTextSync.dylib
make test              # the suites, by xctest
make odatakit-ios ios  # both libraries compiled for iOS and its simulator
```

**GNUstep** (clang, libobjc2, gnustep-make, plus FreeCoreData and ODataKit
installed for TopoTextSync):

```sh
. /path/to/GNUstep.sh
make && make test && make install
make WITH_SYNC=no      # TopoText alone: Foundation, nothing else
```

Or in a container, on top of ODataKit's `sdk` image:

```sh
docker build -f Docker/Dockerfile --target check .
```

`TOPOTEXT_SEEDS=2000` runs the convergence fuzz longer. That test has
several copies edit and sync at random until they agree; each copy keeps an
editor's attributed string, updated only by its own edits and the `TTEdit`s
its merges report, and that string must match the text at every step.

CI (`.github/workflows/ci.yml`) is ported from ODataKit's. On macOS it builds
ODataKit's frameworks, runs the suites, runs a long fuzz, and compiles for
iOS. On Ubuntu it builds the same pinned gnustep-patches stack (cached),
FreeCoreData and ODataKit, then builds and tests TopoText, also checking that
TopoText builds alone.

Releases (`release.yml`, `docker.yml`, ported from ODataKit's, XFormsKit's
and RDLKit's) package SimpleNotes from a `v*` tag: the macOS app (signed and
notarized when the secrets are set), a Linux AppImage, unsigned iOS builds,
and the server's image on the GitHub Container Registry. See
SimpleNotes' README, "Releases".

## The files

| File | What it does |
|---|---|
| `Sources/TopoText/include/TopoText/TopoText.h` | The public API: `TopoText`, `TTId`, `TTVersion`, `TTEdit` |
| `Sources/TopoText/TopoText.m` | The text: runs, local edits, integration (RGA), deltas, edits reported |
| `Sources/TopoText/TTCoding.m` | The wire format: varints, WTF-8 text, attribute values, payloads, versions |
| `Sources/TopoText/TTTable.m` | Tables that merge: row and column orders, a TopoText per cell |
| `Sources/TopoText/TTInternal.h` | Runs, registers, payloads, shared by both |
| `Sources/TopoTextSync/` | `TTSyncResolver`, `NSManagedObject (TopoText)` |
| `Tests/` | Unit tests, the convergence fuzz, ODataSync end to end |
| `Examples/SimpleNotes/` | The notes app and its server |
| `Scripts/xcodeproj.py` | The Xcode projects and workspace, written |
| `Scripts/prepare-appdir.sh`, `package-appimage.sh`, `appimage/` | SimpleNotes' AppImage |
| `Docker/server.Dockerfile`, `collect-server.sh` | The server's image, FROM scratch |

The wire format is described at the top of `TTCoding.m`. Text is WTF-8,
because a run split by a remote insert between the two halves of a surrogate
pair must still encode.

## Not yet

- **Tombstones are never collected.** A deleted character keeps its id, though
  not its text, forever. That costs a few bytes per deleted run.
  Collecting them safely needs every replica to have seen the deletion, which
  ODataSync's version vectors could tell.
- **Undo** of one's own edits, as edits on the CRDT.
- **Deltas over the wire.** ODataSync sends the whole state of a changed note.
  Exchanging `-deltaSinceVersion:` instead would need an OData action of its
  own, or a peer route.
- **Typing backwards** (each keystroke inserted before the last one) can
  interleave with another writer at the same place. This is RGA's known case;
  Fugue's ordering fixes it at the cost of a second origin per run.
- **Every operation is O(runs).** That is fine for notes: in a worst-case
  document of 20k one-character runs, an edit takes 15 µs, and merging 2000
  concurrent edits takes 0.16 s. A book-length text would want a tree.

## License

LGPL 2.1 or later (`LICENSE`). SimpleNotes, the example, is under it too.
