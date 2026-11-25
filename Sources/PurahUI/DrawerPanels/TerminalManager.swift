// Sources/PurahUI/DrawerPanels/TerminalManager.swift
import AppKit
import Foundation
import SwiftUI
import SwiftTerm
import PurahCore

// MARK: - Stable Terminal Container View
/// Container NSView that shields its child terminal from transient zero-sized frames
/// when drawers collapse, glide, or close, preserving the scrollback buffer and active shell.
public final class StableTerminalContainerView: NSView {
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        syncChildTerminalFrames()
    }

    public override func layout() {
        super.layout()
        syncChildTerminalFrames()
    }

    func syncChildTerminalFrames() {
        let size = bounds.size
        // Block degenerate sizes (e.g. 0x0) that would collapse the terminal to 2x1
        guard size.width >= 10, size.height >= 10 else { return }

        let inset: CGFloat = 4.0
        let terminalFrame = bounds.insetBy(dx: inset, dy: inset)
        for child in subviews {
            if let term = child as? PurahTerminalView {
                if term.frame != terminalFrame {
                    term.frame = terminalFrame
                }
                term.syncProcessWindowSize()
            } else if child is LocalProcessTerminalView {
                child.frame = terminalFrame
            } else {
                child.frame = bounds
            }
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        syncChildTerminalFrames()
        // When reopened on rail expansion, force redraw so SwiftTerm refreshes the terminal screen
        for child in subviews {
            child.needsDisplay = true
        }
    }
}

// MARK: - Purah Terminal View
/// Enhanced terminal view providing:
/// 1. Reliable ⌘C / ⌘V / ⌘A / ⌘K keyboard shortcut routing
/// 2. Smooth edge auto-scrolling during mouse drag selection (top-to-bottom and bottom-to-top)
/// 3. Native contextual menu (Copy, Paste, Select All, Clear Buffer)
/// 4. Strict zero-memory-leak lifecycle (removes monitors & invalidates timers on teardown)
open class PurahTerminalView: LocalProcessTerminalView {
    private var autoScrollTimer: Timer?
    private var activeScrollLines: Int?
    private var mouseMonitorToken: Any?
    private var isDragging: Bool = false

    open override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopAutoScroll()
            if let token = mouseMonitorToken {
                NSEvent.removeMonitor(token)
                mouseMonitorToken = nil
            }
        }
    }

    open override func removeFromSuperview() {
        stopAutoScroll()
        if let token = mouseMonitorToken {
            NSEvent.removeMonitor(token)
            mouseMonitorToken = nil
        }
        super.removeFromSuperview()
    }

    private var lastSyncedCols: Int = -1
    private var lastSyncedRows: Int = -1

    open override func viewDidMoveToWindow() {
        guard !PurahWorkspaceStore.isTestingEnvironment else { return }
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        setupMouseDragMonitorIfNeeded()
        TerminalManager.shared.refreshAppearanceForEffectiveAppearance(of: self)
        syncProcessWindowSize(force: true)
    }

    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard !PurahWorkspaceStore.isTestingEnvironment else { return }
        TerminalManager.shared.refreshAppearanceForEffectiveAppearance(of: self)
    }

    /// Ensures the child PTY `TIOCSWINSZ` matches SwiftTerm's current grid dimensions.
    /// Prevents initial-layout or font-change mismatches where tools like `curl -#`
    /// read a stale `ws_col` wider than the terminal buffer and wrap every tick.
    public func syncProcessWindowSize(force: Bool = false) {
        let cols = terminal.cols
        let rows = terminal.rows
        guard cols > 0, rows > 0 else { return }
        guard force || cols != lastSyncedCols || rows != lastSyncedRows else { return }
        lastSyncedCols = cols
        lastSyncedRows = rows
        guard process.running else { return }
        sizeChanged(source: self, newCols: cols, newRows: rows)
    }

    private func setupMouseDragMonitorIfNeeded() {
        guard !PurahWorkspaceStore.isTestingEnvironment else { return }
        guard mouseMonitorToken == nil else { return }
        mouseMonitorToken = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocalDragEvent(event)
            }
            return event
        }
    }

    private func handleLocalDragEvent(_ event: NSEvent) {
        guard let win = window, event.window === win else { return }
        switch event.type {
        case .leftMouseDown:
            let localPoint = convert(event.locationInWindow, from: nil)
            let isInside = bounds.contains(localPoint)
            // SwiftTerm does not make itself first responder on click. The
            // drawer can be mounted without taking focus, so an explicit click
            // inside the terminal restores it without activating the app.
            if isInside, win.firstResponder !== self {
                win.makeFirstResponder(self)
            }
            isDragging = isInside
            stopAutoScroll()
        case .leftMouseDragged:
            guard isDragging else { return }
            let localPoint = convert(event.locationInWindow, from: nil)
            // In AppKit coordinates, y=0 is at bottom, bounds.height is at top
            if localPoint.y <= 14.0 {
                startAutoScroll(lines: 1)
            } else if localPoint.y >= bounds.height - 14.0 {
                startAutoScroll(lines: -1)
            } else {
                stopAutoScroll()
            }
        case .leftMouseUp:
            isDragging = false
            stopAutoScroll()
        default:
            break
        }
    }

    private func startAutoScroll(lines: Int) {
        if activeScrollLines == lines && autoScrollTimer != nil { return }
        stopAutoScroll()
        activeScrollLines = lines

        // 20Hz continuous scroll while mouse is held past the top or bottom viewport edge
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isDragging else { return }
                if lines > 0 {
                    self.scrollDown(lines: 1)
                } else {
                    self.scrollUp(lines: 1)
                }
                self.setNeedsDisplay(self.bounds)
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        activeScrollLines = nil
    }

    // MARK: - ⌘C / ⌘V / ⌘A / ⌘K Keyboard Shortcut Interception
    open override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == .command {
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
                return super.performKeyEquivalent(with: event)
            }
            switch chars {
            case "c":
                if selectionActive || (getSelection()?.isEmpty == false) {
                    copy(self)
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
                    return true
                }
            case "v":
                if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
                    paste(self)
                    return true
                }
            case "a":
                selectAll()
                return true
            case "k":
                TerminalManager.shared.clearScreen()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Native Context Menu
    open override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let hasSelection = selectionActive || (getSelection()?.isEmpty == false)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyAction), keyEquivalent: "c")
        copyItem.target = self
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteAction), keyEquivalent: "v")
        pasteItem.target = self
        menu.addItem(pasteItem)

        menu.addItem(NSMenuItem.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAllAction), keyEquivalent: "a")
        selectAllItem.target = self
        menu.addItem(selectAllItem)

        let clearItem = NSMenuItem(title: "Clear Buffer", action: #selector(clearBufferAction), keyEquivalent: "k")
        clearItem.target = self
        menu.addItem(clearItem)

        return menu
    }

    @objc private func copyAction() {
        copy(self)
    }

    @objc private func pasteAction() {
        paste(self)
    }

    @objc private func selectAllAction() {
        selectAll()
    }

    @objc private func clearBufferAction() {
        TerminalManager.shared.clearScreen()
    }
}

// MARK: - Curated Dark & Light Terminal Color Schemes
public enum TerminalColorSchemePalette {
    public struct Spec {
        public let foreground: NSColor
        public let caret: NSColor
        public let selectionBackground: NSColor
        public let ansi16: [SwiftTerm.Color]
    }

    private static func termColor(_ hex: UInt32) -> SwiftTerm.Color {
        let r = UInt16(((hex >> 16) & 0xFF) * 257)
        let g = UInt16(((hex >> 8) & 0xFF) * 257)
        let b = UInt16((hex & 0xFF) * 257)
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    /// Vibrant, crisp dark-glass palette (Tokyo Night / macOS inspired).
    public static var dark: Spec {
        Spec(
            foreground: NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 1.0),
            caret: NSColor(srgbRed: 0.00, green: 0.92, blue: 0.80, alpha: 1.0),
            selectionBackground: NSColor(srgbRed: 0.24, green: 0.42, blue: 0.72, alpha: 0.55),
            ansi16: [
                termColor(0x1E222A), // 0 Black
                termColor(0xF7768E), // 1 Red
                termColor(0x73DACA), // 2 Green
                termColor(0xE0AF68), // 3 Yellow
                termColor(0x7AA2F7), // 4 Blue
                termColor(0xBB9AF7), // 5 Magenta
                termColor(0x7DCFFF), // 6 Cyan
                termColor(0xC0CAF5), // 7 White
                termColor(0x6B7280), // 8 Bright Black (subtle comments / autosuggestions)
                termColor(0xFF899D), // 9 Bright Red
                termColor(0x9ECE6A), // 10 Bright Green
                termColor(0xF6C177), // 11 Bright Yellow
                termColor(0x89B4FA), // 12 Bright Blue
                termColor(0xD2A8FF), // 13 Bright Magenta
                termColor(0x89DDFF), // 14 Bright Cyan
                termColor(0xF8FAFC)  // 15 Bright White
            ]
        )
    }

    /// High-contrast Apple-crafted Light-glass palette: deep ink & darkened chroma
    /// so yellow/cyan/green/autosuggestions stay crisp on frosted light surfaces.
    public static var light: Spec {
        Spec(
            foreground: NSColor(srgbRed: 0.11, green: 0.13, blue: 0.18, alpha: 1.0),
            caret: NSColor(srgbRed: 0.00, green: 0.48, blue: 0.52, alpha: 1.0),
            selectionBackground: NSColor(srgbRed: 0.22, green: 0.52, blue: 0.96, alpha: 0.28),
            ansi16: [
                termColor(0x1E293B), // 0 Black
                termColor(0xC81E3B), // 1 Red
                termColor(0x047857), // 2 Green
                termColor(0xA16207), // 3 Yellow (deep amber-ochre, readable on light glass)
                termColor(0x1D4ED8), // 4 Blue
                termColor(0x7C3AED), // 5 Magenta
                termColor(0x0E7490), // 6 Cyan (deep teal)
                termColor(0x475569), // 7 White (slate ink for light surfaces)
                termColor(0x64748B), // 8 Bright Black (comments / autosuggestions)
                termColor(0xDC2626), // 9 Bright Red
                termColor(0x059669), // 10 Bright Green
                termColor(0xB45309), // 11 Bright Yellow
                termColor(0x2563EB), // 12 Bright Blue
                termColor(0x9333EA), // 13 Bright Magenta
                termColor(0x0284C7), // 14 Bright Cyan
                termColor(0x0F172A)  // 15 Bright White (high-contrast emphasis ink)
            ]
        )
    }

    public static func spec(isDark: Bool) -> Spec {
        isDark ? dark : light
    }
}

// MARK: - Terminal Tab Session Model
public struct TerminalTabSession: Identifiable {
    public let id: String
    public var title: String
    public let terminalView: PurahTerminalView
    public var isRunning: Bool

    public init(id: String = UUID().uuidString, title: String, terminalView: PurahTerminalView, isRunning: Bool = false) {
        self.id = id
        self.title = title
        self.terminalView = terminalView
        self.isRunning = isRunning
    }
}

// MARK: - Terminal Manager (Persistent Shell Controller)
@MainActor
public final class TerminalManager: ObservableObject {
    public static let shared = TerminalManager()
    public static let maxTabsCount: Int = 5

    @Published public private(set) var tabs: [TerminalTabSession] = []
    @Published public var activeTabId: String = ""
    @Published public var isProcessRunning: Bool = false
    @Published public var terminalTitle: String = "Terminal"
    @Published public var shellName: String = "zsh"

    /// Stable container returned to SwiftUI that never gets deallocated during drawer close/open
    public let containerView: StableTerminalContainerView = {
        let v = StableTerminalContainerView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }()

    public var terminalView: PurahTerminalView? {
        if let active = tabs.first(where: { $0.id == activeTabId }) {
            return active.terminalView
        }
        return tabs.first?.terminalView
    }

    private weak var currentDelegate: LocalProcessTerminalViewDelegate?
    private var lastAppliedFontFamily: String = ""
    private var lastAppliedFontSize: CGFloat = 0
    private var cachedResolvedFont: NSFont?
    private var lastAppliedPalette: ThemePalette = ThemePalette.palette(for: .native)
    private var lastAppliedIsDarkByView: [ObjectIdentifier: Bool] = [:]
    private var recycledViews: [PurahTerminalView] = []

    private init() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellName = URL(fileURLWithPath: shell).lastPathComponent
    }

    @discardableResult
    public func createNewTab(focus: Bool = true) -> String {
        guard tabs.count < Self.maxTabsCount else {
            return activeTabId
        }

        let fallbackFrame = PurahWorkspaceStore.isTestingEnvironment
            ? CGRect(x: 0, y: 0, width: 120, height: 80)
            : CGRect(x: 0, y: 0, width: 500, height: 360)
        let initialFrame = containerView.bounds.size.width >= 10
            ? containerView.bounds
            : fallbackFrame

        let view: PurahTerminalView
        if let recycled = recycledViews.popLast() {
            view = recycled
            view.frame = initialFrame
        } else if PurahWorkspaceStore.isTestingEnvironment, let existing = tabs.first?.terminalView {
            view = existing
        } else {
            view = PurahTerminalView(frame: initialFrame)
            view.autoresizingMask = [.width, .height]
        }
        view.processDelegate = currentDelegate
        applyAppearanceSettings(
            to: view,
            fontFamily: lastAppliedFontFamily.isEmpty ? "Auto (Nerd Font)" : lastAppliedFontFamily,
            fontSize: lastAppliedFontSize > 0 ? lastAppliedFontSize : 11.5,
            palette: lastAppliedPalette
        )

        let usedNumbers = Set(tabs.compactMap { tab -> Int? in
            let parts = tab.title.split(separator: " ")
            guard let last = parts.last else { return nil }
            return Int(last)
        })
        let nextNumber = (1...Self.maxTabsCount).first(where: { !usedNumbers.contains($0) }) ?? (tabs.count + 1)
        let tabTitle = "\(shellName) \(nextNumber)"
        let newTab = TerminalTabSession(
            id: UUID().uuidString,
            title: tabTitle,
            terminalView: view,
            isRunning: false
        )

        tabs.append(newTab)
        selectTab(id: newTab.id, focus: focus)

        if !PurahWorkspaceStore.isTestingEnvironment {
            startShellProcess(for: newTab.id)
        }

        return newTab.id
    }

    public func closeTab(id: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: idx)
        let stillReferenced = tabs.contains(where: { $0.terminalView === removed.terminalView })
        if !stillReferenced {
            removed.terminalView.terminate()
            removed.terminalView.removeFromSuperview()
            if PurahWorkspaceStore.isTestingEnvironment && recycledViews.count < 2 {
                recycledViews.append(removed.terminalView)
            }
        }

        if tabs.isEmpty {
            isProcessRunning = false
            activeTabId = ""
            createNewTab()
        } else if activeTabId == id {
            let nextIdx = min(idx, tabs.count - 1)
            selectTab(id: tabs[nextIdx].id)
        }
    }

    public func selectTab(id: String, focus: Bool = true) {
        guard let targetTab = tabs.first(where: { $0.id == id }) else { return }
        activeTabId = id
        isProcessRunning = targetTab.isRunning

        for sub in containerView.subviews where sub !== targetTab.terminalView {
            sub.removeFromSuperview()
        }

        if targetTab.terminalView.superview !== containerView {
            let initialFrame = containerView.bounds.size.width >= 10
                ? containerView.bounds.insetBy(dx: 4.0, dy: 4.0)
                : CGRect(x: 0, y: 0, width: 500, height: 360)
            targetTab.terminalView.frame = initialFrame
            containerView.addSubview(targetTab.terminalView)
        }
        targetTab.terminalView.needsDisplay = true
        if focus {
            focusTerminal()
        }
    }

    public static func shellEscapedPath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    @discardableResult
    public func cdToFrontmostFinderDirectory() -> String? {
        if tabs.isEmpty {
            createNewTab()
        }

        var resolvedPath: String? = nil
        if !PurahWorkspaceStore.isTestingEnvironment {
            let scriptSource = "tell application \"Finder\" to if (count of Finder windows) > 0 then get POSIX path of (target of front Finder window as alias)"
            if let script = NSAppleScript(source: scriptSource) {
                var errorDict: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorDict)
                if errorDict == nil, let path = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    resolvedPath = path
                }
            }
        }

        let targetPath = resolvedPath ?? NSHomeDirectory()
        guard !targetPath.isEmpty else { return nil }

        let command = "cd \(Self.shellEscapedPath(targetPath))\n"
        terminalView?.send(txt: command)
        return targetPath
    }

    public func ensureTerminalView(
        delegate: LocalProcessTerminalViewDelegate,
        fontFamily: String,
        fontSize: CGFloat,
        palette: ThemePalette,
        isDark: Bool? = nil
    ) {
        self.currentDelegate = delegate
        self.lastAppliedPalette = palette

        if tabs.isEmpty {
            createNewTab(focus: false)
        }

        if let active = terminalView {
            active.processDelegate = delegate
            applyAppearanceSettings(
                to: active,
                fontFamily: fontFamily,
                fontSize: fontSize,
                palette: palette,
                isDark: isDark
            )
            if active.superview !== containerView {
                containerView.addSubview(active)
                containerView.syncChildTerminalFrames()
            }
        }
    }

    public func startShellProcess(for tabId: String? = nil) {
        let targetId = tabId ?? activeTabId
        guard let idx = tabs.firstIndex(where: { $0.id == targetId }) else { return }
        guard !tabs[idx].isRunning else {
            if targetId == activeTabId {
                isProcessRunning = true
            }
            return
        }

        let view = tabs[idx].terminalView
        // Sync the view frame with container bounds BEFORE forkpty so the shell
        // receives the real drawer column width rather than the 500x360 fallback.
        if containerView.bounds.size.width >= 10, containerView.bounds.size.height >= 10 {
            let targetFrame = containerView.bounds.insetBy(dx: 4.0, dy: 4.0)
            if view.frame != targetFrame {
                view.frame = targetFrame
            }
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellName = URL(fileURLWithPath: shell).lastPathComponent
        let execName = "-" + (shell as NSString).lastPathComponent // Login shell convention

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        env["PURAH_TERMINAL"] = "1"
        env.removeValue(forKey: "TERM_PROGRAM")

        // `??`: hand the shell a managed ZDOTDIR and the loopback endpoint.
        // Returns false when the shell is not zsh or the feature is off, in
        // which case nothing at all is added.
        TerminalShellIntegration.prepare(environment: &env, shellPath: shell)

        // `???` reads the screen, because the shell cannot: zsh has the command
        // line and the exit status, and the reason it failed was printed to the
        // terminal. The buffer keeps the scrollback, so a long build log does
        // not push the error line out of reach.
        TerminalShellIntegration.terminalTail = { [weak self] in
            await MainActor.run { self?.terminalBufferText() }
        }

        let envArray = env.map { "\($0.key)=\($0.value)" }

        view.startProcess(
            executable: shell,
            args: [],
            environment: envArray,
            execName: execName
        )
        tabs[idx].isRunning = true
        if targetId == activeTabId {
            isProcessRunning = true
        }
        // Push one deferred TIOCSWINSZ after SwiftUI/AppKit settles the drawer layout.
        DispatchQueue.main.async { [weak view, weak containerView] in
            containerView?.syncChildTerminalFrames()
            view?.syncProcessWindowSize(force: true)
        }
    }

    public func stopProcess() {
        for tab in tabs {
            tab.terminalView.terminate()
            tab.terminalView.removeFromSuperview()
            if PurahWorkspaceStore.isTestingEnvironment && !recycledViews.contains(where: { $0 === tab.terminalView }) && recycledViews.count < 2 {
                recycledViews.append(tab.terminalView)
            }
        }
        tabs.removeAll()
        activeTabId = ""
        isProcessRunning = false
        terminalTitle = "Terminal"
    }

    public func restartShell(fontFamily: String, fontSize: CGFloat, palette: ThemePalette) {
        if let idx = tabs.firstIndex(where: { $0.id == activeTabId }) {
            let oldTitle = tabs[idx].title
            let oldId = tabs[idx].id
            tabs[idx].terminalView.terminate()
            tabs[idx].terminalView.removeFromSuperview()

            let initialFrame = containerView.bounds.size.width >= 10
                ? containerView.bounds
                : CGRect(x: 0, y: 0, width: 500, height: 360)
            let view = recycledViews.popLast() ?? PurahTerminalView(frame: initialFrame)
            view.frame = initialFrame
            view.autoresizingMask = [.width, .height]
            view.processDelegate = currentDelegate
            applyAppearanceSettings(to: view, fontFamily: fontFamily, fontSize: fontSize, palette: palette, forceFontUpdate: true)
            tabs[idx] = TerminalTabSession(id: oldId, title: oldTitle, terminalView: view, isRunning: false)
            selectTab(id: oldId)
            startShellProcess(for: oldId)
        } else if let delegate = currentDelegate {
            ensureTerminalView(delegate: delegate, fontFamily: fontFamily, fontSize: fontSize, palette: palette)
            startShellProcess()
        }
    }

    public func refreshAppearanceForEffectiveAppearance(of view: LocalProcessTerminalView) {
        let resolvedDark = Self.resolveIsDark(for: view)
        applyAppearanceSettings(
            to: view,
            fontFamily: lastAppliedFontFamily.isEmpty ? "Auto (Nerd Font)" : lastAppliedFontFamily,
            fontSize: lastAppliedFontSize > 0 ? lastAppliedFontSize : 11.5,
            palette: lastAppliedPalette,
            isDark: resolvedDark
        )
    }

    public static func resolveIsDark(for view: NSView? = nil) -> Bool {
        let appearance = view?.effectiveAppearance
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    public func applyAppearanceSettings(
        to view: LocalProcessTerminalView,
        fontFamily: String,
        fontSize: CGFloat,
        palette: ThemePalette,
        forceFontUpdate: Bool = false,
        isDark: Bool? = nil
    ) {
        // 1. Resolve Font with Starship / Nerd Font cascade list
        if forceFontUpdate || lastAppliedFontFamily != fontFamily || lastAppliedFontSize != fontSize || cachedResolvedFont == nil {
            let font = TerminalFontManager.resolveFont(family: fontFamily, size: fontSize)
            cachedResolvedFont = font
            lastAppliedFontFamily = fontFamily
            lastAppliedFontSize = fontSize
        }
        if let font = cachedResolvedFont, view.font != font {
            view.font = font
            if let purahView = view as? PurahTerminalView {
                purahView.syncProcessWindowSize(force: true)
            }
        }
        lastAppliedPalette = palette

        // 2. Terminal Colors & Translucency
        // A terminal is a panel inside the drawer, not a terminal window: clear
        // background lets the card surface through, while foreground, caret,
        // selection and the 16-color ANSI table adapt cleanly to Dark vs Light.
        let resolvedIsDark = isDark ?? Self.resolveIsDark(for: view)
        let colorSpec = TerminalColorSchemePalette.spec(isDark: resolvedIsDark)
        view.nativeBackgroundColor = .clear
        view.nativeForegroundColor = colorSpec.foreground
        view.caretColor = colorSpec.caret
        view.selectedTextBackgroundColor = colorSpec.selectionBackground
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false

        let viewKey = ObjectIdentifier(view)
        if lastAppliedIsDarkByView[viewKey] != resolvedIsDark {
            lastAppliedIsDarkByView[viewKey] = resolvedIsDark
            view.installColors(colorSpec.ansi16)
        }

        // 3. Terminal Behavior Flags
        view.getTerminal().setCursorStyle(.blinkBlock)
        view.caretViewTracksFocus = false
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.useBrightColors = true
        view.getTerminal().options.scrollback = 2000
    }

    /// The terminal's scrollback as text, newest last. `nil` when no shell has
    /// been started yet, which is also when there is nothing to explain.
    private func terminalBufferText() -> String? {
        guard let data = terminalView?.getTerminal().getBufferAsData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func markProcessTerminated(for source: TerminalView) {        if let idx = tabs.firstIndex(where: { $0.terminalView === source }) {
            tabs[idx].isRunning = false
            if tabs[idx].id == activeTabId {
                isProcessRunning = false
            }
        } else {
            isProcessRunning = false
        }
    }

    public func focusTerminal() {
        guard let view = terminalView else { return }
        guard let window = containerView.window ?? view.window else { return }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !window.isKeyWindow {
            window.makeKey()
        }
        if window.firstResponder !== view {
            window.makeFirstResponder(view)
        }
    }

    public func sendInterrupt() {
        guard let view = terminalView else { return }
        view.send(txt: "\u{03}") // Ctrl+C
    }

    /// Types `?? ` into the active shell.
    ///
    /// The drawer footer advertises the feature; clicking that advert should
    /// land the person at the prompt with the mode already entered, rather than
    /// asking them to remember two question marks.
    public func beginNaturalLanguageCommand() {
        guard let view = terminalView, isProcessRunning else { return }
        focusTerminal()
        view.send(txt: "?? ")
    }

    public func sendEOF() {
        guard let view = terminalView else { return }
        view.send(txt: "\u{04}") // Ctrl+D
    }

    public func clearScreen() {
        guard let view = terminalView else { return }
        view.send(txt: "\u{0c}") // Ctrl+L
    }
}

// MARK: - SwiftTerm Delegate Coordinator Bridge
public final class TerminalManagerCoordinator: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    public override init() {
        super.init()
    }

    public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // SwiftTerm automatically reflows terminal grid and notifies child process via SIGWINCH
    }

    public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in
            TerminalManager.shared.terminalTitle = title
        }
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Directory change notification from shell OSC 7
    }

    public func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            TerminalManager.shared.markProcessTerminated(for: source)
        }
    }
}

// MARK: - SwiftTerm Representable Bridge for SwiftUI
public struct SwiftTermRepresentable: NSViewRepresentable {
    public let fontFamily: String
    public let fontSize: Double
    public let palette: ThemePalette
    public let isDark: Bool?

    public init(fontFamily: String, fontSize: Double, palette: ThemePalette, isDark: Bool? = nil) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.palette = palette
        self.isDark = isDark
    }

    public func makeCoordinator() -> TerminalManagerCoordinator {
        TerminalManagerCoordinator()
    }

    public func makeNSView(context: Context) -> NSView {
        let manager = TerminalManager.shared
        manager.ensureTerminalView(
            delegate: context.coordinator,
            fontFamily: fontFamily,
            fontSize: CGFloat(fontSize),
            palette: palette,
            isDark: isDark
        )
        if !manager.isProcessRunning {
            manager.startShellProcess()
        }
        return manager.containerView
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        let manager = TerminalManager.shared
        manager.ensureTerminalView(
            delegate: context.coordinator,
            fontFamily: fontFamily,
            fontSize: CGFloat(fontSize),
            palette: palette,
            isDark: isDark
        )
    }
}
