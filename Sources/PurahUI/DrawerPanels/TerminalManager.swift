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
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        setupMouseDragMonitorIfNeeded()
    }

    private func setupMouseDragMonitorIfNeeded() {
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

// MARK: - Terminal Manager (Persistent Shell Controller)
@MainActor
public final class TerminalManager: ObservableObject {
    public static let shared = TerminalManager()

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

    public private(set) var terminalView: PurahTerminalView?
    private weak var currentDelegate: LocalProcessTerminalViewDelegate?
    private var lastAppliedFontFamily: String = ""
    private var lastAppliedFontSize: CGFloat = 0

    private init() {}

    public func ensureTerminalView(
        delegate: LocalProcessTerminalViewDelegate,
        fontFamily: String,
        fontSize: CGFloat,
        palette: ThemePalette
    ) {
        self.currentDelegate = delegate
        if let existing = terminalView, existing.superview === containerView {
            existing.processDelegate = delegate
            applyAppearanceSettings(to: existing, fontFamily: fontFamily, fontSize: fontSize, palette: palette)
            return
        }

        let initialFrame = containerView.bounds.size.width >= 10
            ? containerView.bounds
            : CGRect(x: 0, y: 0, width: 500, height: 360)

        terminalView?.removeFromSuperview()

        let view = PurahTerminalView(frame: initialFrame)
        view.autoresizingMask = [.width, .height]
        view.processDelegate = delegate

        applyAppearanceSettings(to: view, fontFamily: fontFamily, fontSize: fontSize, palette: palette)

        containerView.addSubview(view)
        terminalView = view
    }

    public func startShellProcess() {
        guard let view = terminalView, !isProcessRunning else { return }

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
        isProcessRunning = true
    }

    public func stopProcess() {
        terminalView?.terminate()
        terminalView?.removeFromSuperview()
        terminalView = nil
        isProcessRunning = false
        terminalTitle = "Terminal"
    }

    public func restartShell(fontFamily: String, fontSize: CGFloat, palette: ThemePalette) {
        terminalView?.terminate()
        terminalView?.removeFromSuperview()
        terminalView = nil
        isProcessRunning = false
        terminalTitle = "Terminal"

        if let delegate = currentDelegate {
            ensureTerminalView(delegate: delegate, fontFamily: fontFamily, fontSize: fontSize, palette: palette)
            startShellProcess()
        }
    }

    public func applyAppearanceSettings(
        to view: LocalProcessTerminalView,
        fontFamily: String,
        fontSize: CGFloat,
        palette: ThemePalette
    ) {
        // 1. Resolve Font with Starship / Nerd Font cascade list
        if lastAppliedFontFamily != fontFamily || lastAppliedFontSize != fontSize {
            let font = TerminalFontManager.resolveFont(family: fontFamily, size: fontSize)
            view.font = font
            lastAppliedFontFamily = fontFamily
            lastAppliedFontSize = fontSize
        }

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
            TerminalManager.shared.isProcessRunning = false
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
