import AppKit
import Carbon
import PurahCore

private struct CarbonRefs: @unchecked Sendable {
    var hotKeyRef: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
}

@MainActor
public final class GlobalHotKeyManager: Sendable {
    public static let shared = GlobalHotKeyManager()

    private var refs = CarbonRefs()
    private var triggerAction: (() -> Void)?

    private init() {
        installCarbonEventHandler()
    }

    public func register(shortcut: HotKeyShortcut, onTrigger: @escaping () -> Void) {
        unregister()
        self.triggerAction = onTrigger

        let hotKeyID = EventHotKeyID(signature: OSType(0x50555248), id: 1) // 'PURH'
        var gMyHotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &gMyHotKeyRef
        )

        if status == noErr {
            self.refs.hotKeyRef = gMyHotKeyRef
        }
    }

    public func unregister() {
        if let ref = refs.hotKeyRef {
            UnregisterEventHotKey(ref)
            refs.hotKeyRef = nil
        }
        triggerAction = nil
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, inEvent, inUserData -> OSStatus in
            guard let inUserData = inUserData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(inUserData).takeUnretainedValue()
            Task { @MainActor in
                manager.triggerAction?()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &refs.eventHandlerRef
        )
    }

    deinit {
        if let ref = refs.hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = refs.eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}
