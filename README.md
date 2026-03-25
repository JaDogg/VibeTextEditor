# VTE — Plain Text Editor for macOS

A minimal, distraction-free plain text editor for macOS. Single Swift source file, no dependencies beyond Cocoa.

## Features

- Line numbers
- Monospace font with persistent font/size preferences (Cmd+`+`/`-`/`0`, or Format menu)
- Cmd+scroll to zoom font size
- Auto-save (2 s after last edit, when a file is open)
- Encoding detection: UTF-8 with Latin-1 fallback
- Light/dark mode support with 10 built-in themes (Format → Theme)
- Word wrap toggle (Format → Word Wrap)
- Find bar (Cmd+F)
- Go to Line (Cmd+L)
- Duplicate line (Cmd+D)
- Tab / Shift+Tab indent and dedent for multi-line selections
- Auto-indent: new lines inherit the leading whitespace of the previous line
- File → Open Recent (last 10 files)
- Opens plain text files via drag-and-drop or File → Open

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New | Cmd+N |
| Open | Cmd+O |
| Save | Cmd+S |
| Save As | Cmd+Shift+S |
| Find | Cmd+F |
| Find and Replace | Cmd+H |
| Find Next | Cmd+G |
| Find Previous | Cmd+Shift+G |
| Go to Line | Cmd+L |
| Duplicate Line | Cmd+D |
| Indent | Tab (with selection) |
| Dedent | Shift+Tab |
| Font Bigger | Cmd++ |
| Font Smaller | Cmd+- |
| Font Default Size | Cmd+0 |
| Zoom font (scroll) | Cmd+Scroll |

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
