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

// MARK: - Dark Mode Helper

func isDarkMode() -> Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

// MARK: - Line Number Ruler View

// Plain NSView — no NSScrollView ruler integration (which was hiding the text view).
class LineNumberRulerView: NSView {

    weak var textView: NSTextView?
    weak var attachedScrollView: NSScrollView?
    private var observations: [Any] = []
    private static let sidePad: CGFloat = 8.0
    private var cachedLineCount: Int = 1

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

        let dark = isDarkMode()

        // Background
        (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.94, alpha: 1)).setFill()
        dirtyRect.fill()

        // Right border
        (dark ? NSColor(white: 0.28, alpha: 1) : NSColor(white: 0.76, alpha: 1)).setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        guard lm.numberOfGlyphs > 0 else { return }

        let font    = rulerFont()
        let fgColor = dark ? NSColor(white: 0.42, alpha: 1) : NSColor(white: 0.55, alpha: 1)
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

    var currentFileURL: URL?
    var isModified     = false
    var autoSaveTimer: Timer?

    var currentFontName = kDefaultFontName
    var currentFontSize = kDefaultFontSize

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        loadFontPrefs()
        buildWindow()
        buildMenu()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openFile(url: URL(fileURLWithPath: filename))
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
        scrollView = NSScrollView(frame: NSRect(x: rw, y: 0,
                                               width: frame.width - rw,
                                               height: frame.height))
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

        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled    = false
        textView.isContinuousSpellCheckingEnabled     = false
        textView.isGrammarCheckingEnabled             = false

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
        rulerView = LineNumberRulerView(frame: NSRect(x: 0, y: 0,
                                                      width: rw,
                                                      height: frame.height))
        rulerView.autoresizingMask = [.height]
        rulerView.setup(with: textView, scrollView: scrollView)

        // ── Container holds both side by side ─────────────────────────────────
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(rulerView)
        container.addSubview(scrollView)

        applyTheme()

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
        // Semantic colors adapt automatically to light/dark mode.
        let bgColor: NSColor = .textBackgroundColor
        let fgColor: NSColor = .textColor

        textView.backgroundColor = bgColor
        textView.textColor       = fgColor
        textView.insertionPointColor = fgColor

        // The clip view (NSClipView) is what shows when the document doesn't fill
        // the scroll view — set it explicitly so there is no gray bleed-through.
        scrollView.backgroundColor            = bgColor
        scrollView.contentView.backgroundColor = bgColor
        scrollView.contentView.drawsBackground = true

        window.backgroundColor = bgColor

        // Keep typing attributes consistent so newly typed characters are visible.
        var ta = textView.typingAttributes
        ta[.foregroundColor] = fgColor
        ta[.font] = currentFont()
        textView.typingAttributes = ta

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
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Save",  action: #selector(saveDocument), keyEquivalent: "s"))
        let saveAs = NSMenuItem(title: "Save As…", action: #selector(saveDocumentAs), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)

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

        // ── Window ────────────────────────────────────────────────────────────
        let winItem = NSMenuItem(); bar.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winItem.submenu = winMenu
        winMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        winMenu.addItem(NSMenuItem(title: "Zoom",     action: #selector(NSWindow.zoom(_:)),        keyEquivalent: ""))
        NSApp.windowsMenu = winMenu
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

    // MARK: - NSTextDelegate

    func textDidChange(_ notification: Notification) {
        isModified = true
        window.isDocumentEdited = true
        rulerView.needsDisplay  = true
        scheduleAutoSave()
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
        storage.addAttributes([.font: currentFont(), .foregroundColor: NSColor.textColor],
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
