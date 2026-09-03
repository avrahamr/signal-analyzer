# Contributing

Thanks for helping. This is a small project with a single maintainer, so the
rules are short.

## Ground rules

- Be kind; see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Open an issue before a large change so we agree on the approach. Small
  fixes can go straight to a pull request.
- Every pull request needs the maintainer's approval and a green CI run
  before it can merge. Please keep PRs focused on one thing.
- By contributing you agree your work is released under the [MIT license](LICENSE).

## Setting up

```bash
brew install xcodegen
make open      # generates WiFiSignal.xcodeproj and opens Xcode
make test      # runs the unit tests from the terminal
```

Requires macOS 14+ and Xcode 16 or newer. The `.xcodeproj` is generated from
`project.yml` and is not committed; edit `project.yml` when you need a new
target, framework or build setting.

## Demo data and screenshots

Launch with `--demo` to see fictional networks and devices instead of your
surroundings (Xcode: Product → Scheme → Edit Scheme → Arguments, or
`open "build/Build/Products/Debug/Signal Analyzer.app" --args --demo`).
Use it for screenshots in issues and PRs so nobody's real network names leak.
`--render-screenshots <dir>` regenerates the README images offscreen.

## What a good PR looks like

- **Tests for decoding and maths.** Anything that parses bytes (802.11
  information elements, Bluetooth advertisements) or computes channels,
  frequencies, overlap or distance must come with unit tests using hand-built
  fixtures, like the existing ones under `Tests/WiFiSignalTests`.
- **No new dependencies without discussion.** The app deliberately uses only
  Apple frameworks.
- **Keep the main actor clean.** Scanning and anything that blocks runs off
  the main thread and hands plain value types back to `ScanStore` or
  `BluetoothScanner`.
- **Explain regulatory or protocol claims.** If you change what counts as
  DFS, a Wi-Fi generation, a cipher, etc., link the spec or a reliable source
  in the PR description.
- **Screenshots for UI changes**, before and after.

## Reporting bugs

Use the bug report template. Include your macOS version, whether Location
access was granted, and if it is a decoding bug, the raw information elements
from the network's detail page (Advanced → Raw information elements).

## Ideas

[ROADMAP.md](ROADMAP.md) lists planned work in priority order. Comment on or
open an issue for the item you want to take so we do not duplicate effort.
