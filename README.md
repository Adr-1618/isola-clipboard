# Isola Clipboard

**A native macOS menu bar clipboard manager** built with SwiftUI and AppKit. Isola Clipboard keeps your latest copied text, links, images, and files in a compact animated island below the menu bar.

## Features

- Keeps up to five recent clipboard items in memory.
- Supports plain text, URLs, images, and files.
- Drag items natively to Finder and other apps; file drags preserve the original file URL and name.
- Opens with a global keyboard shortcut (`Control-Option-Space` by default).
- Dismisses automatically after two seconds by default; the timeout is configurable from one to ten seconds.
- Offers settings for appearance, login launch, privacy filters, and menu bar visibility.
- Stores clipboard history only in process memory. The app does not send clipboard contents to a cloud service.

The current app interface is in Italian. A three-finger trackpad gesture is not built in; the keyboard shortcut can be mapped with BetterTouchTool.

## Download

Check [Releases](https://github.com/Adr-1618/isola-clipboard/releases) for the downloadable Apple Silicon (arm64) ZIP. If no release is listed yet, use the build instructions below. Extract the ZIP and move `Isola Clipboard.app` into Applications. The build is ad-hoc signed and **not Apple-notarized**, so macOS Gatekeeper may block the first launch; if needed, review the warning in System Settings > Privacy & Security and choose Open Anyway only if you trust the source.

## Build and test

Open `IsolaClipboard.xcodeproj` in Xcode, or run the included scripts on macOS:

```sh
sh scripts/run-smoke-tests.sh
sh scripts/package-release.sh
```

The package script creates an arm64 app bundle in `release/Isola Clipboard.app`. Local builds and packaged bundles are excluded from this repository. The generated bundle uses ad-hoc signing and is not notarized. Maintainers can publish a ZIP using the manually triggered **Publish macOS release** GitHub Actions workflow; release availability depends on that workflow completing successfully.

## Verification

- Automated smoke tests cover clipboard types, the five-item limit, privacy filters, preference persistence, native drag formats, and original file URLs.
- File drag-and-drop into Finder, launch at login after a Mac restart, and use with multiple monitors have been confirmed manually.
- Runtime logs show the default idle timeout and outside-click dismissal completing.
- Theme changes applied live and custom timeout settings have not been checked in an isolated manual test.

Diagnostic logs contain panel state and geometry, not clipboard contents.

## License

No license file is included yet.
