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

    private var hasAutoFocused = false

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
        guard let onSubmit else {
            super.insertNewline(sender)
            return
        }
        onSubmit()
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
    private let onSubmit: () -> Void

    public init(
        text: Binding<String>,
        fontSize: CGFloat = 11.5,
        focusRequest: Int = 0,
        autoFocus: Bool = false,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.fontSize = fontSize
        self.focusRequest = focusRequest
        self.autoFocus = autoFocus
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
        textView.unregisterDraggedTypes()

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? PurahAIComposerTextView else { return }

        textView.onSubmit = onSubmit

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
        }
    }
}
