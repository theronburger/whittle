# Whittle

**Fast screen annotation for agentic dev.**

Whittle pairs a small Mac menu bar app with an iPad PencilKit canvas. Capture a
region, mark it up with your Pencil, dictate or type feedback, and copy the
annotated image plus a Markdown file onto your Mac for your agent.

Requires macOS 26 and iPadOS 26 or later. This release uses TestFlight for updates
on both platforms. There is no cloud account or screenshot relay.

## Development

Install Xcode and XcodeGen, then open `Whittle.xcodeproj`. The project definition
is `project.yml`; regenerate it with `xcodegen generate` after changing targets.

```sh
swift test
./scripts/test.sh
```

Core tests cover local persistence, revision conflicts, the wire protocol, secure
pairing and real encrypted socket transfers. Hostless Mac tests check file
clipboard behavior. iPad tests check rendered exports. CI also runs native Mac
and iPad UI tests. UI tests run on hosted runners, with reports attached to the
workflow; they are not part of the default local test command.

Create an untracked `Config/Signing.xcconfig` from
`Config/Signing.example.xcconfig`, set your Developer Team ID, then build for a
connected iPad. Xcode automatic signing manages the development certificate and
provisioning profile. Keep signing files and pairing codes out of the repository.

## Use

1. Open Whittle on the Mac. Open its menu bar icon and settings to show the QR.
2. Open Whittle on the iPad and scan the code, or paste the pairing code.
3. Use **⌥⇧⌘W** to capture a region, or **⌥⌘W** to import a copied image. Both
   shortcuts are configurable. You can also drop image files into the menu panel.
4. Draw with Pencil. Use two fingers to pan, pinch to zoom, or twist to rotate.
   The reset button restores the view. Choose Arrow and drag to draw an arrow.
5. Drag a note from the toolbar onto the image. Tap its microphone to dictate,
   or type. Drag an existing note to move it; tap it to edit. Undo and redo apply
   to annotations.
6. Tap Copy on the iPad. The Mac clipboard receives **two actual files**:
   `Whittle.png` and `Whittle.md`. Paste them into your agent, or drag the feedback
   card from the Mac menu panel.

Captures queue without replacing an active screenshot. Annotations save locally
before synchronization. Feedback requested while disconnected stays in an outbox
and copies when the Mac reconnects. Both devices exchange revision inventories
after reconnecting to recover missed edits and captures.

Pairing settings show connection status and retry controls. If discovery is
unavailable, use an address from the Mac's Connection Details. Reset pairing on
the Mac to invalidate the old code and scan the replacement on the iPad.

## Privacy and ownership

Screenshots and annotations stay on your devices and travel over an authenticated,
encrypted local connection. Pairing keys are stored in each device's Keychain.
There are no analytics. Dictation uses Apple's Speech framework, preferring
on-device recognition where available; Apple may process speech when the device
does not support on-device recognition for the selected language.

Whittle is source available with rights reserved, not an open-source license.
See [LICENSE](LICENSE). Dependencies keep their own licenses.
