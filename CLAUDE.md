# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
bash build.sh
open VTE.app
```

Requires macOS with `swiftc` (Xcode Command Line Tools). The build script compiles `main.swift` directly — no Xcode project, no Package.swift. The resulting `VTE.app` is ad-hoc code-signed and ready to run.

For icon generation from `icon.svg`, either `imagemagick` or `librsvg` must be installed (`brew install imagemagick`). A pre-built `AppIcon.icns` is checked in so icon tools are optional.

There are no automated tests.

## Architecture

The entire app is a single file: `main.swift`. It contains:

- **`LineNumberRulerView`** — a plain `NSView` (not `NSRulerView`) that draws line numbers. It observes `NSText.didChangeNotification` and `NSView.boundsDidChangeNotification` to stay in sync with scroll position.
- **`EditorTextView`** — `NSTextView` subclass that intercepts Cmd+scroll to change font size.
- **`AppDelegate`** — owns the window, text view, scroll view, and ruler view; handles file I/O, font management, auto-save, and menus.

### Layout — critical constraint

Do **not** use `NSScrollView`'s built-in ruler integration (`hasVerticalRuler`, `verticalRulerView`, `rulersVisible`). It silently misplaces the `NSClipView`, making the text view invisible. The layout is manual:

```
contentView (NSView)
├── LineNumberRulerView   — left strip, fixed width (50 pt), autoresizes height
└── NSScrollView          — right of ruler, autoresizes width+height
```

`NSScrollView` must have `borderType = .noBorder` when embedded this way.

### Theme / colors

Colors use semantic `NSColor` values (`.textColor`, `.textBackgroundColor`) so they adapt to light/dark automatically. `usesAdaptiveColorMappingForDarkAppearance` is set to `false` because theming is applied manually on `effectiveAppearance` KVO changes. After any programmatic `textView.string = …` assignment, `applyTheme()` must be called to restore `textColor` and `typingAttributes`, since string assignment resets text storage attributes.

### Font persistence

Font name and size are stored in `UserDefaults` under `VTEFontName` / `VTEFontSize`. `resolveFont()` falls back through Menlo → Monaco → SF Mono → Courier New → system monospaced if the saved font is unavailable.

### Auto-save

A 2-second debounce timer saves to `currentFileURL` after each edit. Only fires when a file URL is set (no auto-save for unsaved documents).
