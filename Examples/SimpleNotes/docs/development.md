# Developing SimpleNotes

Running the apps from source, the checks, and how releases are made.

## The apps, from source


- **macOS**: open `TopoText.xcworkspace` (ODataKit checked out beside this
  repository, at `../ODataKit`) and run the **SimpleNotes** scheme. Then
  choose **SimpleNotes > Server…** and give `http://127.0.0.1:8080/odata/`.
- **iPhone or iPad**: the **SimpleNotes-iOS** scheme. Set the address with
  the server button at the top left. The simulator reaches the Mac at
  `127.0.0.1`. To run on a device, put `DEVELOPMENT_TEAM = <your team>` in
  `iOS/Local.xcconfig`.
- **GNUstep**, with TopoText, ODataKit and FreeCoreData installed:

  ```sh
  make -C Examples/SimpleNotes && openapp Examples/SimpleNotes/SimpleNotes.app
  ```

  For the Eau theme (gnustep-patches' `build-gnustep.sh` builds it), set it
  in the app's defaults, as our other apps' launchers do:
  `defaults write SimpleNotes GSTheme Eau`. The self-test does this itself.

To try two devices on one Mac or Linux machine, give a second instance a
store of its own: `SimpleNotes -SNStore /tmp/second.sqlite`.

## Releases

Tag a version (`git tag v0.1.0 && git push --tags`), and the workflows build
and attach:

- **macOS** (`release.yml`): `SimpleNotes-macOS-<version>.zip`, universal.
  It is signed with a Developer ID and notarized when the `production`
  environment has the secrets `MACOS_CERTIFICATE` (a base64 .p12),
  `MACOS_CERTIFICATE_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and
  `NOTARY_PASSWORD`; otherwise it's unsigned, and named so. Either way it
  must pass its self-test first.
  A release (not a pre-release) also gets `appcast.xml`, the feed the
  app's Sparkle reads (`SUFeedURL`: the newest release's), its update
  signed with the EdDSA key in the `SPARKLE_PRIVATE_KEY` secret, whose
  public half is `SUPublicEDKey` in `AppKit/Info.plist`. Without the
  secret there is no appcast, and the Mac app isn't offered the release.
- **Linux** (`release.yml`): `SimpleNotes-<version>-x86_64.AppImage`,
  built on Ubuntu 22.04 so it runs there and on anything newer. It is
  checked on a clean Ubuntu: its own server is started and seeded, and the
  app's self-test runs against it.
  A release's AppImage carries update information (`gh-releases-zsync`,
  the newest release), and its `.zsync` is attached beside it, so
  AppImageUpdate, Gear Lever and the like update it by the blocks that
  changed. A pre-release's carries none: "latest" would offer it the
  release before it.
- **iOS** (`release.yml`): `SimpleNotes-iOS-<version>-unsigned.ipa`, to be
  signed for TestFlight and the App Store once there is an account, and a
  simulator build. The simulator build must pass its self-test.
- **The server's image** (`docker.yml`): pushed to
  `ghcr.io/ashalkhakov/simplenotes-server:<version>` and `:latest`, for
  amd64 and arm64. Every push builds it and checks it on SQLite and
  PostgreSQL.

Run `release.yml` by hand to build any branch's packages as artifacts,
without releasing.

## Checked

```sh
make -C Examples/SimpleNotes check
```

This runs four things:

- **The tests.** Two devices and the service run in one process: edits made
  apart, a deletion against an edit, an open editor merged while its own
  typing is kept, folders moved into each other apart, tags, sorting and
  grouping, migrations from each older version, and the text view's
  binding both ways. Notes are exported as Markdown and imported back with
  their folders and attachments, and a Trilium export is imported.
- **Two devices through the server, over HTTP**
  (`Tests/serve-and-check.sh`, `SimpleNotes --check`). With `SN_STORE_ARGS`,
  the server stores in PostgreSQL or MariaDB instead. Then the server's
  notes move to another store (`Tests/move-and-check.sh`): it must serve the
  same notes and folders, answer 410 to a delta link from before, and not
  move them twice. CI moves them from SQLite to PostgreSQL.
- **The AppKit app driven from within** (`SimpleNotes --self-test`, under
  `xvfb-run` where there's no display). A note is chosen in the list, text
  is typed into the window's text view, and Bold is sent up the responder
  chain. Two lines become a checklist, a click on the first checkbox ticks
  it, and Return starts a third item. The sidebar must show Projects
  inside Work and the tags; a tag and a nested folder list their notes; a
  folder moves to the top; Sort By Title regroups the list. A second device
  must see all of it. With `SN_SELF_TEST_SNAPSHOT=<file.png>`, the window is
  saved as a picture at that point; that's how the README's screenshots
  were made.
- **The iOS app's self-test, in a simulator** (`Tests/ios-self-test.sh`;
  macOS only). It does the same through the iOS view controllers.

CI runs all of these: macOS and iOS against Apple's Core Data, and GNUstep
against FreeCoreData, SQLite, PostgreSQL and MariaDB.
