# TopoText

[![Build](https://github.com/ashalkhakov/TopoText/actions/workflows/build.yml/badge.svg)](https://github.com/ashalkhakov/TopoText/actions/workflows/build.yml)

A rich text that merges itself. Copies of a text edited apart, on devices
that are offline or on either side of a server, become the same text again by
exchanging what each has, and nothing either side typed is lost. Nobody is
asked to pick a version.

In Objective-C 2.0 with ARC, on Apple's Foundation (macOS, iOS) and on
GNUstep (Linux).

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

| Library | What it is |
|---|---|
| `TopoText` | The text: edits, attributes, positions, tables, undo, merging, deltas, the wire format. Foundation only. |
| `TopoTextSync` | Its part in an [ODataKit](https://github.com/ashalkhakov/ODataKit) ODataSync store: a merger that moves texts as deltas, a conflict resolver that merges whole states, and `NSManagedObject` helpers. |

## SimpleNotes

[SimpleNotes](Examples/SimpleNotes/README.md) is a small, self-hosted Apple
Notes built on both, for macOS, Linux and iPhone/iPad, with a server of your
own. Notes edited apart on two devices come out with both edits. Download it
from [Releases](https://github.com/ashalkhakov/TopoText/releases/latest).

## What it does

- **Merges without conflicts.** Every character has an id and is placed by
  another one (RGA, with Fugue's ordering), so two people typing at one
  place each get their text unbroken, whichever copy hears of what first.
- **Rich text that merges by key.** Bold set here and italic set there are
  both kept; paragraph formatting (headings, lists, checklists) follows the
  paragraph's newline.
- **Tables** that merge as Apple Notes' do: rows and columns added apart are
  all kept, and each cell merges as text.
- **Deltas and a canonical state.** A copy sends only what the other lacks;
  two copies that have seen the same edits write the same bytes, on every
  system.
- **An editor stays put.** A merge reports its edits one by one, so a text
  view's selection and scroll position survive; anchors pin a cursor or a
  comment to a character; undo of one's own edits survives others'.
- **Old tombstones go.** Text every copy has seen deleted is collected, so a
  text doesn't grow for ever.

How: [How TopoText works](docs/how-it-works.md).

## Build

```sh
# Apple's platforms, with ODataKit's XCFrameworks in .deps/ (.github/pins.env)
make -f Makefile.apple && make -f Makefile.apple check
# GNUstep (clang, libobjc2), with FreeCoreData and ODataKit installed
make && make check && make install
make WITH_SYNC=no      # TopoText alone: Foundation, nothing else
```

Or open `TopoText.xcworkspace` in Xcode. Details: [docs/building.md](docs/building.md).

## Limitations

- **Every operation is O(runs).** That is fine for notes: in a worst-case
  document of 20k one-character runs, an edit takes 15 µs, and merging 2000
  concurrent edits takes 0.16 s. A book-length text would want a tree.
- **On GNUstep** the libraries need clang and libobjc2, and SimpleNotes needs
  GNUstep patched by [gnustep-patches](https://github.com/ashalkhakov/gnustep-patches)
  until its fixes are upstream.

## Layout

| Path | What |
|---|---|
| `Sources/TopoText/` | The text, its wire format (`TTCoding.m`) and tables (`TTTable.m`) |
| `Sources/TopoTextSync/` | `TTSyncMerger`, `TTSyncResolver`, `NSManagedObject (TopoText)` |
| `Tests/` | Unit tests, the convergence fuzz, ODataSync end to end |
| `Examples/SimpleNotes/` | The notes app and its server |
| `Scripts/`, `Docker/` | The Xcode projects (written by `xcodeproj.py`), SimpleNotes' AppImage and the server's image |
| `docs/` | How it works, ODataSync, building, references |

## Documentation

- [How TopoText works](docs/how-it-works.md): ids and runs, ordering,
  tombstones, attributes, tables, undo, deltas, editors, replicas, the wire
  format
- [TopoText with ODataSync](docs/odatasync.md): as a merged attribute, or as
  a conflict resolver
- [Building](docs/building.md): Xcode, make, GNUstep, Docker, CI and releases
- [References](docs/References.md): the papers behind it

## License

LGPL 2.1 or later (`LICENSE`). SimpleNotes, the example, is under it too.
