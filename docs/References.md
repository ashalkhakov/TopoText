# References

The research TopoText builds on, and the papers for what it doesn't do yet.

## Text

- **RGA (Replicated Growable Array).** H.-G. Roh, M. Jeon, J.-S. Kim, J. Lee.
  "Replicated abstract data types: Building blocks for collaborative
  applications." *Journal of Parallel and Distributed Computing* 71(3), 2011.
  TopoText's sequence: each character has an ID (replica, clock) and is
  placed after the character it was typed after. A deleted character stays
  as a tombstone.
- **Peritext.** G. Litt, S. Lim, M. Kleppmann, P. van Hardenberg. "Peritext:
  A CRDT for Collaborative Rich Text Editing." *Proc. ACM on
  Human-Computer Interaction* 6 (CSCW2), 2022. Formatting as spans
  anchored to characters, which merge better at a span's edges than
  TopoText's per-character attributes do. Not done.

## Tables (`TTTable`)

A table is a composition, not one named algorithm:

- **Row order and column order** are each an RGA sequence (a TopoText with
  one character per row or column). A row's identity is its character's
  ID, not its position.
- **Cells** are a map from (row ID, column ID) to a TopoText of their own.
  Nesting sequences in a map, keyed by IDs, is the pattern of:
  M. Kleppmann, A. R. Beresford. "A Conflict-Free Replicated JSON
  Datatype." *IEEE Transactions on Parallel and Distributed Systems*
  28(10), 2017. Automerge works the same way.
- **Merging whole tables** makes TTTable a state-based CRDT: merging is a
  join, so copies converge whatever order they arrive in.
  M. Shapiro, N. Preguiça, C. Baquero, M. Zawirski. "Conflict-free
  Replicated Data Types." *SSS 2011*, LNCS 6976. See also their INRIA
  report "A comprehensive study of Convergent and Commutative Replicated
  Data Types" (RR-7506, 2011).
- **Deletion wins:** a row or column removed takes its cells with it,
  including text typed into them concurrently on another device.

## Not done yet

- **Sending only what changed** instead of whole tables: P. S. Almeida,
  A. Shoker, C. Baquero. "Delta state replicated data types." *Journal of
  Parallel and Distributed Computing* 111, 2018.
- **Moving a row or column** while keeping its identity (today a move
  would be a delete and an insert): M. Kleppmann. "Moving elements in list
  CRDTs." *PaPoC 2020*.
