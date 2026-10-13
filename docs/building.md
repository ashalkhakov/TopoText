# Building TopoText

What TopoText builds on is named by exact release in `.github/pins.env`: the
GNUstep stack, FreeCoreData, GCDWebServer, ODataKit and Sparkle. To move one,
change it there.

**Apple's platforms**: ODataKit's XCFrameworks and Sparkle's go in `.deps/`
(gnustep-release-actions' `scripts/deps.sh apple`, from the repository's
root, fetches them by those versions). Then:

```sh
make -f Makefile.apple            # the libraries, SimpleNotes for macOS and its server
make -f Makefile.apple check      # the suites, a long fuzz, SimpleNotes' tests
make -f Makefile.apple install DESTDIR=out
make -f Makefile.apple ios ios-check   # SimpleNotes for iOS; the libraries compiled for it
```

or open `TopoText.xcworkspace` in Xcode. Its projects (`TopoText.xcodeproj`,
the frameworks for macOS and iOS, and SimpleNotes') are written by
`Scripts/xcodeproj.py`: change that script and run it, rather than editing
the projects by hand.

**GNUstep** (clang, libobjc2, gnustep-make, plus FreeCoreData and ODataKit
installed: `scripts/deps.sh linux` unpacks their releases into `/opt/gnustep`):

```sh
. /path/to/GNUstep.sh
make                   # the libraries, SimpleNotes and its server
make check             # the tests; the server on PostgreSQL and MariaDB when given
make install
make WITH_SYNC=no      # TopoText alone: Foundation, nothing else
```

Or in a container, on ODataKit's published `sdk` image:

```sh
v=$(sed -n 's/^ODATAKIT_VERSION=//p' .github/pins.env)
docker build -f Docker/Dockerfile --build-arg ODATAKIT_VERSION=$v --target check .
```

`TOPOTEXT_SEEDS=2000` runs the convergence fuzz longer. That test has
several copies edit and sync at random until they agree; each copy keeps an
editor's attributed string, updated only by its own edits and the `TTEdit`s
its merges report, and that string must match the text at every step.

One workflow, `.github/workflows/build.yml`, builds, tests and releases
everything, by gnustep-release-actions' workflows, the same as every
repository's: they run the commands above (make, make check, make install;
`Makefile.apple` on Apple's platforms, with `installcheck` and
`ios-installcheck`: the installed app's self-test against its own server, on
the Mac and in a simulator), then package what was installed. On Linux that
is the AppImage, checked on a clean Ubuntu
(`Examples/SimpleNotes/Tests/appimage-smoke.sh`), and the server's image
(`Docker/server.Dockerfile`, tested by `.github/release/docker-test.sh`).

A `v*` tag releases SimpleNotes: the macOS app (signed and notarized when the
secrets are set), a Linux AppImage, unsigned iOS builds,
and the server's image on the GitHub Container Registry. See
[SimpleNotes' releases](../Examples/SimpleNotes/docs/development.md#releases).
