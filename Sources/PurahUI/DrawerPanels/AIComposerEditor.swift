// Sources/PurahUI/DrawerPanels/AIComposerEditor.swift
import SwiftUI
import AppKit

// MARK: - Return-to-Send NSTextView

/// Multi-line composer that submits on Return and inserts a newline on Shift/Option+Return.
///
/// Two AppKit behaviours are neutralised here:
/// 1. `NSTextView.insertNewline(_:)` would always insert a newline, so it is overridden and gated on
///    `hasMarkedText()` to keep IME candidate confirmation working (CJK input methods).
/// 2. `NSTextView` registers itself for text/file drags, and AppKit resolves the *deepest* registered
///    view as the drop destination. The composer therefore swallowed every payload and then refused
///    it (`op=0` back to the source), so the card's `onDrop` never fired. Registration is blocked
///    outright — merely refusing in the dragging callbacks is not enough.
@MainActor
public final class PurahAIComposerTextView: NSTextView {
    public var onSubmit: (() -> Void)?
    public var isSlashMenuVisible: Bool = false
    public var onSlashKeyNavigate: ((Int) -> Bool)?
    public var onSlashKeyCommit: (() -> Bool)?
    public var onSlashDismiss: (() -> Void)?
    public var onTextAndCursorChange: ((String, Int) -> Void)?

    private var hasAutoFocused = false

    public override func keyDown(with event: NSEvent) {
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        if isSlashMenuVisible {
            if event.keyCode == 126 { // Up arrow
                if onSlashKeyNavigate?(-1) == true {
                    return
                }
            } else if event.keyCode == 125 { // Down arrow
                if onSlashKeyNavigate?(1) == true {
                    return
                }
            } else if event.keyCode == 36 || event.keyCode == 48 { // Return or Tab
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if !flags.contains(.shift) && !flags.contains(.option) {
                    if onSlashKeyCommit?() == true {
                        return
                    }
                }
            } else if event.keyCode == 53 { // Escape
                onSlashDismiss?()
                return
            }
        }

        super.keyDown(with: event)
    }

    public override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }
        let flags = (NSApp.currentEvent?.modifierFlags ?? []).intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) || flags.contains(.option) {
            super.insertNewline(sender)
            return
        }
        if isSlashMenuVisible, onSlashKeyCommit?() == true {
            return
        }
        guard let onSubmit else {
            super.insertNewline(sender)
            return
        }
        onSubmit()
    }

    public override func didChangeText() {
        super.didChangeText()
        let cursor = selectedRange().location
        onTextAndCursorChange?(string, cursor)
    }

    public func focusIfNeededOnMount() {
        guard !hasAutoFocused, window != nil, window?.firstResponder !== self else { return }
        hasAutoFocused = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    // MARK: Drag Refusal

    /// Keeps the view out of AppKit's drop-destination chain (see type docs above).
    public override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        super.unregisterDraggedTypes()
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {}
}

// MARK: - SwiftUI Bridge

/// SwiftUI wrapper for `PurahAIComposerTextView`.
///
/// Focus is driven imperatively through `focusRequest`: bump the value to move first responder into
/// the editor. `@FocusState` is unusable here because `NSViewRepresentable` does not participate in
/// SwiftUI focus.
public struct PurahAIComposerEditor: NSViewRepresentable {
    @Binding private var text: String
    private let fontSize: CGFloat
    private let focusRequest: Int
    private let autoFocus: Bool
    private let isSlashMenuVisible: Bool
    private let onSlashKeyNavigate: ((Int) -> Bool)?
    private let onSlashKeyCommit: (() -> Bool)?
    private let onSlashDismiss: (() -> Void)?
    private let onTextAndCursorChange: ((String, Int) -> Void)?
    private let onSubmit: () -> Void

    public init(
        text: Binding<String>,
        fontSize: CGFloat = 11.5,
        focusRequest: Int = 0,
        autoFocus: Bool = false,
        isSlashMenuVisible: Bool = false,
        onSlashKeyNavigate: ((Int) -> Bool)? = nil,
        onSlashKeyCommit: (() -> Bool)? = nil,
        onSlashDismiss: (() -> Void)? = nil,
        onTextAndCursorChange: ((String, Int) -> Void)? = nil,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.fontSize = fontSize
        self.focusRequest = focusRequest
        self.autoFocus = autoFocus
        self.isSlashMenuVisible = isSlashMenuVisible
        self.onSlashKeyNavigate = onSlashKeyNavigate
        self.onSlashKeyCommit = onSlashKeyCommit
        self.onSlashDismiss = onSlashDismiss
        self.onTextAndCursorChange = onTextAndCursorChange
        self.onSubmit = onSubmit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = PurahAIComposerTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 1, height: 2)
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white
        ]
        textView.string = text
        textView.onSubmit = onSubmit
        textView.isSlashMenuVisible = isSlashMenuVisible
        textView.onSlashKeyNavigate = onSlashKeyNavigate
        textView.onSlashKeyCommit = onSlashKeyCommit
        textView.onSlashDismiss = onSlashDismiss
        textView.onTextAndCursorChange = onTextAndCursorChange
        textView.unregisterDraggedTypes()

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? PurahAIComposerTextView else { return }

        textView.onSubmit = onSubmit
        textView.isSlashMenuVisible = isSlashMenuVisible
        textView.onSlashKeyNavigate = onSlashKeyNavigate
        textView.onSlashKeyCommit = onSlashKeyCommit
        textView.onSlashDismiss = onSlashDismiss
        textView.onTextAndCursorChange = onTextAndCursorChange

        if textView.font?.pointSize != fontSize {
            textView.font = .systemFont(ofSize: fontSize)
        }
        if textView.string != text, !textView.hasMarkedText() {
            let savedRanges = textView.selectedRanges
            textView.string = text
            let maxLen = (text as NSString).length
            let clamped = savedRanges.compactMap { value -> NSValue? in
                let range = value.rangeValue
                guard range.location != NSNotFound else { return nil }
                let location = min(range.location, maxLen)
                return NSValue(range: NSRange(location: location, length: min(range.length, maxLen - location)))
            }
            if !clamped.isEmpty {
                textView.selectedRanges = clamped
            }
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.white
            ]
        }

        // Some AppKit code paths re-register dragged types when the view becomes editable or
        // first responder; keep it permanently unregistered.
        if !textView.registeredDraggedTypes.isEmpty {
            textView.unregisterDraggedTypes()
        }

        if autoFocus {
            textView.focusIfNeededOnMount()
        }
        if focusRequest > 0, focusRequest != context.coordinator.lastHandledFocusRequest {
            context.coordinator.lastHandledFocusRequest = focusRequest
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PurahAIComposerEditor
        var lastHandledFocusRequest: Int = 0

        init(parent: PurahAIComposerEditor) {
            self.parent = parent
            // Start at zero: a composer created after a focus request (the refine bar appearing
            // inside a drop) must still take focus on its very first update.
            self.lastHandledFocusRequest = 0
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            let cursor = textView.selectedRange().location
            parent.onTextAndCursorChange?(textView.string, cursor)
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let cursor = textView.selectedRange().location
            parent.onTextAndCursorChange?(textView.string, cursor)
        }
    }
}
