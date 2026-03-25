import Cocoa

// MARK: - Constants & UserDefaults Keys

let kFontNameKey     = "VTEFontName"
let kFontSizeKey     = "VTEFontSize"
let kDefaultFontName = "JaDogg Mono"
let kDefaultFontSize: CGFloat = 14.0
let kAutoSaveDelay: TimeInterval = 2.0
let kMinFontSize: CGFloat = 8.0
let kMaxFontSize: CGFloat = 72.0

// MARK: - Font Helpers

func resolveFont(name: String, size: CGFloat) -> NSFont {
    if let f = NSFont(name: name, size: size) { return f }
    for fallback in ["Menlo", "Monaco", "SF Mono", "Courier New", "Courier"] {
        if let f = NSFont(name: fallback, size: size) { return f }
    }
    return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
}

func savedFont() -> NSFont {
    let name = UserDefaults.standard.string(forKey: kFontNameKey) ?? kDefaultFontName
    let size = UserDefaults.standard.object(forKey: kFontSizeKey) as? CGFloat ?? kDefaultFontSize
    return resolveFont(name: name, size: size)
}

// MARK: - Comparable Clamp

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        return min(max(self, r.lowerBound), r.upperBound)
    }
}

// MARK: - Theme

struct Theme {
    let name: String
    let background: NSColor
    let foreground: NSColor
}

extension NSColor {
    convenience init(rgb hex: UInt32) {
        self.init(red:   CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >>  8) & 0xFF) / 255,
                  blue:  CGFloat( hex        & 0xFF) / 255,
                  alpha: 1)
    }
    var relativeLuminance: CGFloat {
        guard let c = usingColorSpace(.deviceRGB) else { return 0.5 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}

let kThemeIndexKey      = "VTEThemeIndex"
let kStatusBarVisibleKey  = "VTEStatusBarVisible"
let kColumnGuidesKey      = "VTEColumnGuides"
let kSmartTypingKey       = "VTESmartTyping"

let kThemes: [Theme] = [
    // ── Light ─────────────────────────────────────────────────────────────────
    Theme(name: "Default Light",   background: .white,                    foreground: NSColor(rgb: 0x1C1C1C)),
    Theme(name: "Solarized Light", background: NSColor(rgb: 0xFDF6E3),    foreground: NSColor(rgb: 0x657B83)),
    Theme(name: "GitHub",          background: NSColor(rgb: 0xFFFFFF),    foreground: NSColor(rgb: 0x24292E)),
    Theme(name: "Paper",           background: NSColor(rgb: 0xF5F0E8),    foreground: NSColor(rgb: 0x3B3B3B)),
    Theme(name: "Quiet Light",     background: NSColor(rgb: 0xF8F8F8),    foreground: NSColor(rgb: 0x333333)),
    // ── Dark ──────────────────────────────────────────────────────────────────
    Theme(name: "Default Dark",    background: NSColor(rgb: 0x1E1E1E),    foreground: NSColor(rgb: 0xD4D4D4)),
    Theme(name: "Solarized Dark",  background: NSColor(rgb: 0x002B36),    foreground: NSColor(rgb: 0x839496)),
    Theme(name: "Monokai",         background: NSColor(rgb: 0x272822),    foreground: NSColor(rgb: 0xF8F8F2)),
    Theme(name: "One Dark",        background: NSColor(rgb: 0x282C34),    foreground: NSColor(rgb: 0xABB2BF)),
    Theme(name: "Tokyo Night",     background: NSColor(rgb: 0x1A1B2E),    foreground: NSColor(rgb: 0xA9B1D6)),
]

// MARK: - Status Bar

let kStatusBarHeight: CGFloat = 22

class StatusBarView: NSView {
    private let posLabel   = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")

    var bgColor:     NSColor = NSColor(white: 0.95, alpha: 1) { didSet { needsDisplay = true } }
    var borderColor: NSColor = NSColor(white: 0.76, alpha: 1) { didSet { needsDisplay = true } }
    var fgColor:     NSColor = NSColor(white: 0.45, alpha: 1) { didSet {
        posLabel.textColor   = fgColor
        statsLabel.textColor = fgColor
    }}

    override init(frame: NSRect) {
        super.init(frame: frame)
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        for lbl in [posLabel, statsLabel] {
            lbl.font            = font
            lbl.isBezeled       = false
            lbl.drawsBackground = false
            lbl.isEditable      = false
            lbl.isSelectable    = false
            addSubview(lbl)
        }
        posLabel.frame   = NSRect(x: 8, y: 3, width: 200, height: 16)
        statsLabel.frame = NSRect(x: frame.width - 208, y: 3, width: 200, height: 16)
        statsLabel.alignment         = .right
        statsLabel.autoresizingMask  = [.minXMargin]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill(); dirtyRect.fill()
        borderColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    func update(line: Int, col: Int, words: Int, chars: Int) {
        posLabel.stringValue   = "Line \(line), Col \(col)"
        statsLabel.stringValue = "\(words) words · \(chars) chars"
    }
}

// MARK: - Line Number Ruler View

// Plain NSView — no NSScrollView ruler integration (which was hiding the text view).
class LineNumberRulerView: NSView {

    weak var textView: NSTextView?
    weak var attachedScrollView: NSScrollView?
    private var observations: [Any] = []
    private static let sidePad: CGFloat = 8.0
    private var cachedLineCount: Int = 1

    // Set by AppDelegate whenever the theme changes
    var rulerBg:     NSColor = NSColor(white: 0.94, alpha: 1)
    var rulerBorder: NSColor = NSColor(white: 0.76, alpha: 1)
    var rulerFg:     NSColor = NSColor(white: 0.55, alpha: 1)

    static let width: CGFloat = 50

    override var isFlipped: Bool { true }

    private func rulerFont() -> NSFont {
        let tf   = textView?.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let size = max(tf.pointSize - 1, 9)
        return NSFont(name: tf.fontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func setup(with tv: NSTextView, scrollView sv: NSScrollView) {
        textView          = tv
        attachedScrollView = sv
        let nc = NotificationCenter.default
        observations.append(
            nc.addObserver(forName: NSText.didChangeNotification, object: tv, queue: .main) { [weak self] _ in
                self?.cachedLineCount = tv.string.components(separatedBy: "\n").count
                self?.needsDisplay    = true
            }
        )
        observations.append(
            nc.addObserver(forName: NSView.boundsDidChangeNotification,
                           object: sv.contentView, queue: .main) { [weak self] _ in
                self?.needsDisplay = true
            }
        )
        cachedLineCount = max(tv.string.components(separatedBy: "\n").count, 1)
    }

    func refresh() {
        cachedLineCount = max(textView?.string.components(separatedBy: "\n").count ?? 1, 1)
        needsDisplay    = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView,
              let lm = tv.layoutManager,
              let sv = attachedScrollView else { return }

        // Background
        rulerBg.setFill()
        dirtyRect.fill()

        // Right border
        rulerBorder.setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        guard lm.numberOfGlyphs > 0 else { return }

        let font    = rulerFont()
        let fgColor = rulerFg
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fgColor]

        let nsStr    = tv.string as NSString
        let origin   = tv.textContainerOrigin
        let visibleY = sv.contentView.bounds.minY

        var lineNum = 1

        lm.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)
        ) { [weak self] fragRect, _, _, glyphRange, stop in
            guard let self else { stop.pointee = true; return }

            let charRange  = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isLineStart = charRange.location == 0
                || nsStr.character(at: charRange.location - 1) == 10

            let docY   = fragRect.minY + origin.y
            let rulerY = docY - visibleY

            if rulerY > dirtyRect.maxY + 4 { stop.pointee = true; return }

            if isLineStart && rulerY + fragRect.height >= dirtyRect.minY - 4 {
                let label     = "\(lineNum)" as NSString
                let labelSize = label.size(withAttributes: attrs)
                let drawX     = self.bounds.width - labelSize.width - Self.sidePad
                let drawY     = rulerY + (fragRect.height - labelSize.height) / 2
                label.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
            }
            if isLineStart { lineNum += 1 }
        }

        // Trailing empty line after a final '\n'
        if nsStr.length > 0 && nsStr.character(at: nsStr.length - 1) == 10 {
            var lastFragRange = NSRange()
            let lastFragRect  = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1,
                                                    effectiveRange: &lastFragRange)
            let docY   = lastFragRect.maxY + origin.y
            let rulerY = docY - visibleY
            if rulerY + lastFragRect.height >= dirtyRect.minY - 4 && rulerY <= dirtyRect.maxY + 4 {
                let label     = "\(lineNum)" as NSString
                let labelSize = label.size(withAttributes: attrs)
                let drawX     = bounds.width - labelSize.width - Self.sidePad
                let drawY     = rulerY + (lastFragRect.height - labelSize.height) / 2
                label.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
            }
        }
    }

    deinit {
        observations.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

// MARK: - Editor Text View

class EditorTextView: NSTextView {

    /// Called when the user Cmd+scrolls to change font size
    var onFontSizeChange: ((CGFloat) -> Void)?

    var showColumnGuides = true
    var columnGuideColor: NSColor = NSColor(white: 0.5, alpha: 0.25)

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard showColumnGuides, let font = self.font else { return }
        let charWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let originX   = textContainerOrigin.x
        columnGuideColor.setFill()
        for col in [80, 120] {
            let x = (originX + charWidth * CGFloat(col)).rounded()
            guard x >= rect.minX - 1 && x <= rect.maxX + 1 else { continue }
            NSRect(x: x, y: rect.minY, width: 1, height: rect.height).fill()
        }
    }

    // NSTextView's default sizeToFit adds only one textContainerInset.height
    // (for the top), leaving the bottom inset unaccounted for and clipping the
    // last line. It also omits the extraLineFragmentRect (the cursor line after
    // a trailing newline). Both are corrected here.
    override func sizeToFit() {
        guard let lm = layoutManager, let tc = textContainer else {
            super.sizeToFit()
            return
        }
        lm.ensureLayout(for: tc)
        var bottomY = lm.usedRect(for: tc).maxY
        let extra = lm.extraLineFragmentRect
        if extra != .zero { bottomY = max(bottomY, extra.maxY) }
        let insetH = textContainerInset.height
        setFrameSize(NSSize(width: frame.width,
                            height: max(minSize.height, ceil(bottomY + insetH * 2))))
    }

    // Tab with a multi-line selection indents all selected lines;
    // single-line/no-selection falls through to normal tab insertion.
    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let str = string as NSString
        if sel.length > 0 && (str.substring(with: sel).contains("\n")) {
            shiftLines(dedent: false); return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        shiftLines(dedent: true)
    }

    private func shiftLines(dedent: Bool) {
        let str       = string as NSString
        let sel       = selectedRange()
        let lineRange = str.lineRange(for: sel)
        var lines     = str.substring(with: lineRange).components(separatedBy: "\n")
        let hadTrailingNewline = str.substring(with: lineRange).hasSuffix("\n")
        if hadTrailingNewline, lines.last == "" { lines.removeLast() }

        let shifted = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if dedent {
                if line.hasPrefix("\t")    { return String(line.dropFirst()) }
                if line.hasPrefix("    ")  { return String(line.dropFirst(4)) }
                if line.hasPrefix("   ")   { return String(line.dropFirst(3)) }
                if line.hasPrefix("  ")    { return String(line.dropFirst(2)) }
                if line.hasPrefix(" ")     { return String(line.dropFirst(1)) }
                return line
            } else {
                return "\t" + line
            }
        }
        var result = shifted.joined(separator: "\n")
        if hadTrailingNewline { result += "\n" }

        if shouldChangeText(in: lineRange, replacementString: result) {
            textStorage?.replaceCharacters(in: lineRange,
                with: NSAttributedString(string: result, attributes: typingAttributes))
            didChangeText()
        }
        setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length))
    }

    override func insertNewline(_ sender: Any?) {
        super.insertNewline(sender)
        // Replicate leading whitespace of the previous line
        let str    = string as NSString
        let cursor = selectedRange().location
        // Find the start of the PREVIOUS line (the one we just left)
        guard cursor > 0 else { return }
        let prevLineRange = str.lineRange(for: NSRange(location: cursor - 1, length: 0))
        var indent = ""
        var i = prevLineRange.location
        while i < prevLineRange.location + prevLineRange.length {
            let c = str.character(at: i)
            if c == 32 || c == 9 { indent.append(Character(UnicodeScalar(c)!)); i += 1 }
            else { break }
        }
        if !indent.isEmpty {
            insertText(indent, replacementRange: selectedRange())
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        // Use scrollingDeltaY; positive = scroll up = zoom in
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.1 else { return }
        let direction: CGFloat = delta > 0 ? 1 : -1
        onFontSizeChange?((font?.pointSize ?? kDefaultFontSize) + direction)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {

    var window: NSWindow!
    var textView: EditorTextView!
    var scrollView: NSScrollView!
    var rulerView: LineNumberRulerView!
    var statusBarView: StatusBarView!

    var currentFileURL: URL?
    var isModified     = false
    var autoSaveTimer: Timer?

    var currentFontName   = kDefaultFontName
    var currentFontSize   = kDefaultFontSize
    var currentThemeIndex = 0
    var wordWrapEnabled   = true
    var statusBarVisible  = true
    var columnGuidesOn    = true
    var smartTypingOn     = false
    var pendingOpenURL:   URL?
    weak var recentFilesMenu: NSMenu?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        loadFontPrefs()
        loadThemePrefs()
        wordWrapEnabled  = UserDefaults.standard.object(forKey: "VTEWordWrap") as? Bool ?? true
        statusBarVisible = UserDefaults.standard.object(forKey: kStatusBarVisibleKey) as? Bool ?? true
        columnGuidesOn   = UserDefaults.standard.object(forKey: kColumnGuidesKey) as? Bool ?? true
        smartTypingOn    = UserDefaults.standard.object(forKey: kSmartTypingKey)  as? Bool ?? false
        buildWindow()
        buildMenu()
        applyStatusBarVisibility()
        updateStatusBar()
        if let url = pendingOpenURL {
            pendingOpenURL = nil
            openFile(url: url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if textView == nil {
            pendingOpenURL = url   // window not ready yet; defer until applicationDidFinishLaunching
        } else {
            openFile(url: url)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Font Prefs

    func loadFontPrefs() {
        currentFontName = UserDefaults.standard.string(forKey: kFontNameKey) ?? kDefaultFontName
        currentFontSize = UserDefaults.standard.object(forKey: kFontSizeKey) as? CGFloat ?? kDefaultFontSize
    }

    func persistFontPrefs() {
        UserDefaults.standard.set(currentFontName, forKey: kFontNameKey)
        UserDefaults.standard.set(currentFontSize, forKey: kFontSizeKey)
    }

    // MARK: - Theme Prefs

    func loadThemePrefs() {
        let saved = UserDefaults.standard.integer(forKey: kThemeIndexKey)
        currentThemeIndex = saved.clamped(to: 0...(kThemes.count - 1))
    }

    func persistThemePrefs() {
        UserDefaults.standard.set(currentThemeIndex, forKey: kThemeIndexKey)
    }

    @objc func selectTheme(_ sender: NSMenuItem) {
        currentThemeIndex = sender.tag
        persistThemePrefs()
        applyTheme()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectTheme(_:)) {
            menuItem.state = menuItem.tag == currentThemeIndex ? .on : .off
        }
        if menuItem.action == #selector(toggleWordWrap) {
            menuItem.state = wordWrapEnabled ? .on : .off
        }
        if menuItem.action == #selector(toggleStatusBar) {
            menuItem.state = statusBarVisible ? .on : .off
        }
        if menuItem.action == #selector(toggleColumnGuides) {
            menuItem.state = columnGuidesOn ? .on : .off
        }
        if menuItem.action == #selector(toggleSmartTyping) {
            menuItem.state = smartTypingOn ? .on : .off
        }
        return true
    }

    func currentFont() -> NSFont {
        return resolveFont(name: currentFontName, size: currentFontSize)
    }

    // MARK: - Window & Editor Setup

    func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 860, height: 640)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title              = "Untitled"
        window.delegate           = self
        window.center()
        window.setFrameAutosaveName("VTEMainWindow")
        window.titlebarAppearsTransparent = false

        let rw = LineNumberRulerView.width

        // ── Scroll view (right of ruler) ──────────────────────────────────────
        scrollView = NSScrollView(frame: NSRect(x: rw, y: kStatusBarHeight,
                                               width: frame.width - rw,
                                               height: frame.height - kStatusBarHeight))
        scrollView.borderType            = .noBorder
        scrollView.autoresizingMask      = [.width, .height]
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true

        // ── Text view ─────────────────────────────────────────────────────────
        let contentSize = scrollView.contentSize
        textView = EditorTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize         = NSSize(width: 0, height: contentSize.height)
        textView.maxSize         = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                          height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]

        textView.isEditable   = true
        textView.isSelectable = true
        textView.allowsUndo   = true
        textView.isRichText   = false

        applySmartTyping()

        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable   = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize =
            NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)

        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.font               = currentFont()
        textView.usesFindBar        = true
        textView.usesAdaptiveColorMappingForDarkAppearance = false

        textView.delegate = self
        textView.onFontSizeChange = { [weak self] newSize in
            self?.applyFontSize(newSize)
        }

        scrollView.documentView = textView

        // ── Line number view (plain NSView, left strip) ───────────────────────
        rulerView = LineNumberRulerView(frame: NSRect(x: 0, y: kStatusBarHeight,
                                                      width: rw,
                                                      height: frame.height - kStatusBarHeight))
        rulerView.autoresizingMask = [.height]
        rulerView.setup(with: textView, scrollView: scrollView)

        // ── Status bar ────────────────────────────────────────────────────────
        statusBarView = StatusBarView(frame: NSRect(x: 0, y: 0,
                                                    width: frame.width,
                                                    height: kStatusBarHeight))
        statusBarView.autoresizingMask = [.width]

        // ── Container holds ruler + scroll view + status bar ──────────────────
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(statusBarView)
        container.addSubview(rulerView)
        container.addSubview(scrollView)

        applyTheme()
        applyWordWrap()

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        window.addObserver(self, forKeyPath: "effectiveAppearance",
                           options: [.new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            applyTheme()
            rulerView.needsDisplay = true
        }
    }

    func applyTheme() {
        let theme = kThemes[currentThemeIndex]
        let bg = theme.background
        let fg = theme.foreground

        textView.backgroundColor     = bg
        textView.textColor           = fg
        textView.insertionPointColor = fg

        scrollView.backgroundColor             = bg
        scrollView.contentView.backgroundColor = bg
        scrollView.contentView.drawsBackground = true

        window.backgroundColor = bg

        var ta = textView.typingAttributes
        ta[.foregroundColor] = fg
        ta[.font] = currentFont()
        textView.typingAttributes = ta

        // Derive ruler colors by blending theme bg toward white/black
        let dark  = bg.relativeLuminance < 0.4
        let blend = NSColor(white: dark ? 1 : 0, alpha: 1)
        rulerView.rulerBg     = bg.blended(withFraction: 0.08,  of: blend) ?? bg
        rulerView.rulerBorder = bg.blended(withFraction: 0.20,  of: blend) ?? bg
        rulerView.rulerFg     = fg.withAlphaComponent(0.5)
        rulerView.needsDisplay = true

        statusBarView.bgColor     = rulerView.rulerBg
        statusBarView.borderColor = rulerView.rulerBorder
        statusBarView.fgColor     = rulerView.rulerFg
        statusBarView.needsDisplay = true

        textView.columnGuideColor  = rulerView.rulerBorder.withAlphaComponent(0.6)
        textView.showColumnGuides  = columnGuidesOn
        textView.needsDisplay      = true

        applyFontToStorage()
    }

    // MARK: - Menu

    func buildMenu() {
        let bar = NSMenu()
        NSApp.mainMenu = bar

        // ── App ──────────────────────────────────────────────────────────────
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "About VTE",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit VTE",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))

        // ── File ──────────────────────────────────────────────────────────────
        let fileItem = NSMenuItem(); bar.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(NSMenuItem(title: "New",   action: #selector(newDocument),  keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Open…", action: #selector(openDocument), keyEquivalent: "o"))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentItem.submenu = recentMenu
        recentFilesMenu    = recentMenu
        fileMenu.addItem(recentItem)
        rebuildRecentFilesMenu()
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Save",  action: #selector(saveDocument), keyEquivalent: "s"))
        let saveAs = NSMenuItem(title: "Save As…", action: #selector(saveDocumentAs), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)

        // ── View ──────────────────────────────────────────────────────────────
        let viewItem = NSMenuItem(); bar.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(NSMenuItem(title: "Status Bar",    action: #selector(toggleStatusBar),    keyEquivalent: ""))
        viewMenu.addItem(NSMenuItem(title: "Column Guides", action: #selector(toggleColumnGuides), keyEquivalent: ""))

        // ── Edit ──────────────────────────────────────────────────────────────
        let editItem = NSMenuItem(); bar.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Smart Typing", action: #selector(toggleSmartTyping), keyEquivalent: ""))
        editMenu.addItem(.separator())
        let dupLine = NSMenuItem(title: "Duplicate Line", action: #selector(duplicateLine), keyEquivalent: "d")
        dupLine.keyEquivalentModifierMask = .command
        editMenu.addItem(dupLine)
        let goToLine = NSMenuItem(title: "Go to Line…", action: #selector(goToLine), keyEquivalent: "l")
        goToLine.keyEquivalentModifierMask = .command
        editMenu.addItem(goToLine)

        // ── Format ────────────────────────────────────────────────────────────
        let fmtItem = NSMenuItem(); bar.addItem(fmtItem)
        let fmtMenu = NSMenu(title: "Format")
        fmtItem.submenu = fmtMenu
        fmtMenu.addItem(NSMenuItem(title: "Choose Font…", action: #selector(chooseFont), keyEquivalent: ""))
        fmtMenu.addItem(.separator())
        let bigger = NSMenuItem(title: "Bigger",  action: #selector(fontBigger),  keyEquivalent: "+")
        bigger.keyEquivalentModifierMask = .command
        fmtMenu.addItem(bigger)
        let smaller = NSMenuItem(title: "Smaller", action: #selector(fontSmaller), keyEquivalent: "-")
        smaller.keyEquivalentModifierMask = .command
        fmtMenu.addItem(smaller)
        let reset = NSMenuItem(title: "Default Size", action: #selector(fontResetSize), keyEquivalent: "0")
        reset.keyEquivalentModifierMask = .command
        fmtMenu.addItem(reset)
        fmtMenu.addItem(.separator())
        let wrapItem = NSMenuItem(title: "Word Wrap", action: #selector(toggleWordWrap), keyEquivalent: "")
        fmtMenu.addItem(wrapItem)
        fmtMenu.addItem(.separator())
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        for (i, theme) in kThemes.enumerated() {
            if i == 5 { themeMenu.addItem(.separator()) }   // divider between light and dark
            let item = NSMenuItem(title: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.tag = i
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        fmtMenu.addItem(themeItem)

        // ── Window ────────────────────────────────────────────────────────────
        let winItem = NSMenuItem(); bar.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winItem.submenu = winMenu
        winMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        winMenu.addItem(NSMenuItem(title: "Zoom",     action: #selector(NSWindow.zoom(_:)),        keyEquivalent: ""))
        NSApp.windowsMenu = winMenu
    }

    // MARK: - Recent Files

    private let kRecentFilesKey = "VTERecentFiles"
    private let kMaxRecentFiles = 10

    func addToRecents(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: kRecentFilesKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > kMaxRecentFiles { paths = Array(paths.prefix(kMaxRecentFiles)) }
        UserDefaults.standard.set(paths, forKey: kRecentFilesKey)
        rebuildRecentFilesMenu()
    }

    func rebuildRecentFilesMenu() {
        guard let menu = recentFilesMenu else { return }
        menu.removeAllItems()
        let paths = UserDefaults.standard.stringArray(forKey: kRecentFilesKey) ?? []
        if paths.isEmpty {
            let empty = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for path in paths {
                let url  = URL(fileURLWithPath: path)
                let item = NSMenuItem(title: url.lastPathComponent,
                                      action: #selector(openRecentFile(_:)),
                                      keyEquivalent: "")
                item.toolTip          = path
                item.representedObject = url
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Clear Menu",
                                    action: #selector(clearRecentFiles),
                                    keyEquivalent: ""))
        }
    }

    @objc func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        guard confirmDiscardChanges(reason: "opening another file") else { return }
        openFile(url: url)
    }

    @objc func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: kRecentFilesKey)
        rebuildRecentFilesMenu()
    }

    // MARK: - File Operations

    @objc func newDocument() {
        guard confirmDiscardChanges(reason: "creating a new document") else { return }
        currentFileURL = nil
        textView.string = ""
        isModified = false
        window.isDocumentEdited = false
        window.title = "Untitled"
        rulerView.refresh()
    }

    @objc func openDocument() {
        guard confirmDiscardChanges(reason: "opening another file") else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        if panel.runModal() == .OK, let url = panel.url {
            openFile(url: url)
        }
    }

    func openFile(url: URL) {
        do {
            let raw = try Data(contentsOf: url)
            // Detect encoding; fall back to Latin-1 if not valid UTF-8
            let content = String(data: raw, encoding: .utf8)
                ?? String(data: raw, encoding: .isoLatin1)
                ?? ""

            // Normalise line endings to \n
            let normalised = content
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r",   with: "\n")

            textView.string = normalised
            applyTheme()           // reapply textColor/typingAttributes/storage after string reset
            currentFileURL  = url
            isModified      = false
            window.isDocumentEdited = false
            window.title    = url.lastPathComponent
            textView.scrollToBeginningOfDocument(nil)
            rulerView.refresh()
            updateStatusBar()
            addToRecents(url)
        } catch {
            let alert = NSAlert(error: error); alert.runModal()
        }
    }

    @discardableResult
    @objc func saveDocument() -> Bool {
        if let url = currentFileURL { return write(to: url) }
        return saveDocumentAs()
    }

    @discardableResult
    @objc func saveDocumentAs() -> Bool {
        let panel = NSSavePanel()
        if #available(macOS 12.0, *) { panel.allowedContentTypes = [.plainText] }
        let suggested = window.title.hasSuffix(".txt") ? window.title : "\(window.title).txt"
        panel.nameFieldStringValue = suggested == "Untitled.txt" ? "Untitled.txt" : suggested
        if panel.runModal() == .OK, let url = panel.url {
            currentFileURL = url
            return write(to: url)
        }
        return false
    }

    private func write(to url: URL) -> Bool {
        // Always write with \n line endings
        let content = textView.string
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            isModified = false
            window.isDocumentEdited = false
            window.title = url.lastPathComponent
            return true
        } catch {
            let alert = NSAlert(error: error); alert.runModal()
            return false
        }
    }

    // MARK: - Auto-save

    func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        guard currentFileURL != nil else { return }
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: kAutoSaveDelay, repeats: false) { [weak self] _ in
            guard let self, self.isModified, let url = self.currentFileURL else { return }
            _ = self.write(to: url)
        }
    }

    // MARK: - Duplicate Line

    @objc func duplicateLine() {
        let str       = textView.string as NSString
        let sel       = textView.selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText  = str.substring(with: lineRange)
        // If the line has no trailing newline (last line of file), prepend one
        let toInsert  = lineText.hasSuffix("\n") ? lineText : "\n" + lineText
        let insertAt  = lineRange.upperBound

        if textView.shouldChangeText(in: NSRange(location: insertAt, length: 0),
                                      replacementString: toInsert) {
            textView.textStorage?.insert(
                NSAttributedString(string: toInsert, attributes: textView.typingAttributes),
                at: insertAt)
            textView.didChangeText()
        }
        // Place cursor on duplicate at the same column
        let col         = sel.location - lineRange.location
        let newLineStart = insertAt + (toInsert.hasPrefix("\n") ? 1 : 0)
        textView.setSelectedRange(NSRange(location: newLineStart + col, length: 0))
        isModified = true; window.isDocumentEdited = true; scheduleAutoSave()
    }

    // MARK: - Word Wrap

    @objc func toggleWordWrap() {
        wordWrapEnabled.toggle()
        UserDefaults.standard.set(wordWrapEnabled, forKey: "VTEWordWrap")
        applyWordWrap()
    }

    func applyWordWrap() {
        let width = wordWrapEnabled ? scrollView.contentSize.width : CGFloat.greatestFiniteMagnitude
        textView.isHorizontallyResizable            = !wordWrapEnabled
        textView.textContainer?.widthTracksTextView = wordWrapEnabled
        textView.textContainer?.containerSize       = NSSize(width: width, height: .greatestFiniteMagnitude)
        scrollView.hasHorizontalScroller            = !wordWrapEnabled
    }

    // MARK: - Status Bar

    @objc func toggleStatusBar() {
        statusBarVisible.toggle()
        UserDefaults.standard.set(statusBarVisible, forKey: kStatusBarVisibleKey)
        applyStatusBarVisibility()
        if statusBarVisible { updateStatusBar() }
    }

    @objc func toggleColumnGuides() {
        columnGuidesOn.toggle()
        UserDefaults.standard.set(columnGuidesOn, forKey: kColumnGuidesKey)
        textView.showColumnGuides = columnGuidesOn
        textView.needsDisplay     = true
    }

    @objc func toggleSmartTyping() {
        smartTypingOn.toggle()
        UserDefaults.standard.set(smartTypingOn, forKey: kSmartTypingKey)
        applySmartTyping()
    }

    func applySmartTyping() {
        let on = smartTypingOn
        textView.isAutomaticQuoteSubstitutionEnabled  = on
        textView.isAutomaticDashSubstitutionEnabled   = on
        textView.isAutomaticSpellingCorrectionEnabled = on
        textView.isAutomaticTextReplacementEnabled    = on
        textView.isContinuousSpellCheckingEnabled     = on
        textView.isGrammarCheckingEnabled             = on
    }

    func applyStatusBarVisibility() {
        statusBarView.isHidden = !statusBarVisible
        guard let cv = window?.contentView else { return }
        let rw        = LineNumberRulerView.width
        let barHeight: CGFloat = statusBarVisible ? kStatusBarHeight : 0
        rulerView.frame  = NSRect(x: 0,  y: barHeight,
                                  width: rw,
                                  height: cv.bounds.height - barHeight)
        scrollView.frame = NSRect(x: rw, y: barHeight,
                                  width: cv.bounds.width - rw,
                                  height: cv.bounds.height - barHeight)
    }

    // MARK: - Go to Line

    @objc func goToLine() {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        tf.placeholderString = "Line number"
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard let lineNum = Int(input), lineNum > 0 else { return }

        let lines  = textView.string.components(separatedBy: "\n")
        let target = min(lineNum, lines.count) - 1
        var offset = 0
        for i in 0..<target { offset += lines[i].utf16.count + 1 }
        let len   = lines[target].utf16.count
        let range = NSRange(location: offset, length: len)
        textView.scrollRangeToVisible(range)
        textView.setSelectedRange(range)
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: - NSTextDelegate / NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        isModified = true
        window.isDocumentEdited = true
        rulerView.needsDisplay  = true
        updateStatusBar()
        scheduleAutoSave()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatusBar()
    }

    func updateStatusBar() {
        let str = textView.string
        let loc = textView.selectedRange().location
        let prefix = (str as NSString).substring(to: min(loc, str.utf16.count))
        let lines  = prefix.components(separatedBy: "\n")
        let line   = lines.count
        let col    = (lines.last?.count ?? 0) + 1
        let words  = str.isEmpty ? 0 : str.components(separatedBy: .whitespacesAndNewlines)
                                           .filter { !$0.isEmpty }.count
        statusBarView.update(line: line, col: col, words: words, chars: str.count)
    }

    // MARK: - Font

    @objc func chooseFont() {
        let fm = NSFontManager.shared
        fm.setSelectedFont(currentFont(), isMultiple: false)
        fm.target = self
        fm.orderFrontFontPanel(self)
    }

    // Called by NSFontManager when user picks a font in the panel
    @objc func changeFont(_ sender: NSFontManager?) {
        guard let fm = sender else { return }
        let new = fm.convert(currentFont())
        currentFontName = new.fontName
        currentFontSize = new.pointSize.clamped(to: kMinFontSize...kMaxFontSize)
        applyFont()
        persistFontPrefs()
    }

    @objc func fontBigger()    { applyFontSize(currentFontSize + 1) }
    @objc func fontSmaller()   { applyFontSize(currentFontSize - 1) }
    @objc func fontResetSize() { applyFontSize(kDefaultFontSize) }

    func applyFontSize(_ size: CGFloat) {
        currentFontSize = size.clamped(to: kMinFontSize...kMaxFontSize)
        applyFont()
        persistFontPrefs()
    }

    func applyFont() {
        let f = currentFont()
        textView.font = f
        applyFontToStorage()
        rulerView.needsDisplay = true
    }

    /// Applies the current font and foreground color to the entire text storage.
    /// Needed after programmatic string assignment, which can reset attributes.
    private func applyFontToStorage() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.addAttributes([.font: currentFont(), .foregroundColor: kThemes[currentThemeIndex].foreground],
                               range: NSRange(location: 0, length: storage.length))
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isModified else { return true }
        let alert = NSAlert()
        alert.messageText     = "Save changes to \u{201C}\(window.title)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you close without saving."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return saveDocument()
        case .alertSecondButtonReturn: return true
        default:                       return false
        }
    }

    // MARK: - Helpers

    /// Returns true if it is safe to discard the current document.
    private func confirmDiscardChanges(reason: String) -> Bool {
        guard isModified else { return true }
        let alert = NSAlert()
        alert.messageText     = "Save changes before \(reason)?"
        alert.informativeText = "Your unsaved changes will be lost."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return saveDocument()
        case .alertSecondButtonReturn: return true
        default:                       return false
        }
    }

    deinit {
        window?.removeObserver(self, forKeyPath: "effectiveAppearance")
    }
}

// MARK: - Entry Point

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
