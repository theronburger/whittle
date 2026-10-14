# Whittle

Whittle is a native Mac menu bar companion and iPad PencilKit app for fast screen
annotation for agentic development. The Mac captures and exports; the iPad edits.

Keep the domain model and wire protocol in WhittleCore. Keep platform integration
in the relevant app. Preserve annotations as structured text alongside ink.

Run relevant tests at logical development checkpoints. Use `swift test` for core
changes and `scripts/test.sh` for app and rendering changes. CI runs the native UI
tests on hosted runners. Do not drive the user's desktop as a routine test loop.
Use a focused visual check only to answer a specific unresolved question.

Changes reach main through a pull request with passing required CI checks. Never
bypass the checks. Keep credentials, pairing codes, device identifiers, signing
configuration, and private screenshots out of commits and test artifacts.

Updates for this release use TestFlight on both platforms. Do not add Sparkle.
