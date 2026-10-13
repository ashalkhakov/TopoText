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

One workflow, `.github/workflows/build.yml`, builds, tests and releases
everything, by gnustep-release-actions' workflows (the same as every app's)
and the hooks in `.github/release/`. On macOS it builds ODataKit's frameworks,
runs the suites and a long fuzz, and SimpleNotes' tests, then the app; for iOS,
the libraries and the app, its self-test in a simulator. On Linux it takes
the patched GNUstep stack gnustep-patches publishes (its newest image), builds
FreeCoreData and ODataKit, then builds and tests TopoText (also alone) and
SimpleNotes, its server on PostgreSQL and MariaDB too, and checks the AppImage
on a clean Ubuntu.

The commits it builds on (ODataKit, FreeCoreData) are named in one place,
`.github/pins.env`, which the workflows and the Dockerfiles read. To move
one, change it there.

A `v*` tag releases SimpleNotes: the macOS app (signed and notarized when the
secrets are set), a Linux AppImage, unsigned iOS builds,
and the server's image on the GitHub Container Registry. See
[SimpleNotes' releases](../Examples/SimpleNotes/docs/development.md#releases).
