# Building TopoText

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

The commits it builds on (ODataKit, gnustep-patches, FreeCoreData) are named
in one place, `.github/pins.env`, which CI, the release and the Dockerfiles
all read. To move one, change it there.

Releases (`release.yml`, `docker.yml`, ported from ODataKit's, XFormsKit's
and RDLKit's) package SimpleNotes from a `v*` tag: the macOS app (signed and
notarized when the secrets are set), a Linux AppImage, unsigned iOS builds,
and the server's image on the GitHub Container Registry. See
[SimpleNotes' releases](../Examples/SimpleNotes/docs/development.md#releases).
