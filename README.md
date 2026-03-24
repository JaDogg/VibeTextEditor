# VTE — Plain Text Editor for macOS

A minimal, distraction-free plain text editor for macOS. Single Swift source file, no dependencies beyond Cocoa.

## Features

- Line numbers
- Monospace font with persistent font/size preferences (Cmd+`+`/`-`/`0`, or Format menu)
- Cmd+scroll to zoom font size
- Auto-save (2 s after last edit, when a file is open)
- Encoding detection: UTF-8 with Latin-1 fallback
- Light/dark mode support
- Find bar (Cmd+F)
- Opens plain text files via drag-and-drop or File → Open

## Build & Run

Requires macOS 13+ and Xcode Command Line Tools.

```bash
bash build.sh
open VTE.app
```

To install permanently, move `VTE.app` to `/Applications`.

For icon generation from source, install ImageMagick or librsvg:

```bash
brew install imagemagick   # or: brew install librsvg
```

A pre-built `AppIcon.icns` is included so this step is optional.

## Supported File Types

`.txt` `.text` `.md` `.log` `.sh` `.swift` `.py` `.js` `.ts` `.css` `.html` `.json` `.yaml` `.yml` `.toml` `.conf` `.ini` `.csv`
