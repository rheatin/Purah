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
        let size = bounds.size
        // Block degenerate sizes (e.g. 0x0) that would collapse the terminal to 2x1
        guard size.width >= 10, size.height >= 10 else { return }

        let inset: CGFloat = 4.0
        let terminalFrame = bounds.insetBy(dx: inset, dy: inset)
        for child in subviews {
            if child is LocalProcessTerminalView {
                child.frame = terminalFrame
            } else {
                child.frame = bounds
            }
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // When reopened on rail expansion, force redraw so SwiftTerm refreshes the terminal screen
        for child in subviews {
            child.needsDisplay = true
        }
        TerminalManager.shared.focusTerminal()
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

    open override func viewDidMoveToWindow() {
        guard !PurahWorkspaceStore.isTestingEnvironment else { return }
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        setupMouseDragMonitorIfNeeded()
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
            isDragging = bounds.contains(localPoint)
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
    private var recycledViews: [PurahTerminalView] = []

    private init() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellName = URL(fileURLWithPath: shell).lastPathComponent
    }

    @discardableResult
    public func createNewTab() -> String {
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
        selectTab(id: newTab.id)

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

    public func selectTab(id: String) {
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
        focusTerminal()
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
        palette: ThemePalette
    ) {
        self.currentDelegate = delegate
        self.lastAppliedPalette = palette

        if tabs.isEmpty {
            createNewTab()
        }

        if let active = terminalView {
            active.processDelegate = delegate
            applyAppearanceSettings(
                to: active,
                fontFamily: fontFamily,
                fontSize: fontSize,
                palette: palette
            )
            if active.superview !== containerView {
                containerView.addSubview(active)
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

    public func applyAppearanceSettings(
        to view: LocalProcessTerminalView,
        fontFamily: String,
        fontSize: CGFloat,
        palette: ThemePalette,
        forceFontUpdate: Bool = false
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
        }
        lastAppliedPalette = palette

        // 2. Terminal Colors & Translucency
        let isDark = palette.style != .native
        view.nativeBackgroundColor = isDark ? NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.92) : NSColor.textBackgroundColor.withAlphaComponent(0.92)
        view.nativeForegroundColor = isDark ? NSColor(white: 0.94, alpha: 1.0) : NSColor.labelColor
        view.caretColor = isDark ? NSColor(red: 0.0, green: 0.96, blue: 0.83, alpha: 1.0) : NSColor.controlAccentColor
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false

        // 3. Terminal Behavior Flags
        view.getTerminal().setCursorStyle(.blinkBlock)
        view.caretViewTracksFocus = false
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.useBrightColors = true
        view.getTerminal().options.scrollback = 2000
    }

    public func markProcessTerminated(for source: TerminalView) {
        if let idx = tabs.firstIndex(where: { $0.terminalView === source }) {
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

    public init(fontFamily: String, fontSize: Double, palette: ThemePalette) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.palette = palette
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
            palette: palette
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
            palette: palette
        )
        if !manager.isProcessRunning {
            manager.startShellProcess()
        }
    }
}
