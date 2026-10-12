# TopoText with ODataSync

A note's body, or any rich text in a Core Data model, synced by [ODataKit](https://github.com/ashalkhakov/ODataKit)'s ODataSync: as a merged attribute that moves deltas, or through a conflict resolver that merges whole states.

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

**As a merged attribute** (ODataSync's, `docs/offline-sync.md` section 14 in
ODataKit), the text moves as deltas instead of whole states, and what every
device has seen deleted is collected:

```objc
//   bodyText   Binary   userInfo: ODataSync.merge = TopoText, TopoText.text = YES, TopoText.string = body

[engine setMerger:[[TTSyncMerger alloc] init] forName:TTSyncMergerName];   // on each device
[sync.engine setMerger:[[TTSyncMerger alloc] init] forName:TTSyncMergerName];  // at the service (ODataSyncService)
```

A row then goes up and comes down without its text. After the row, one
`MergeAttributes` call sends each changed note's version and gets what the
device lacks, and a second sends what the service lacks. The service keeps
which version each device has seen, and once all have seen a deletion, the
service and the devices collect its tombstones
(`collectTombstonesSeenBy:`). After a merge, the merger sets the plain-text
copy (`TopoText.string`) again; a subclass can set more (SimpleNotes sets the
title). A service without merged attributes (an older one) is synced with as
before, through the resolver below.

**As a conflict resolver**, over whole states:

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
