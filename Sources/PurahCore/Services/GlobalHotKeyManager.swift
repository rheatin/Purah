import AppKit
import Carbon

private struct CarbonRefs: @unchecked Sendable {
    var hotKeyRef: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
}

@MainActor
public final class GlobalHotKeyManager: Sendable {
    public static let shared = GlobalHotKeyManager()

    private var refs = CarbonRefs()
    private var triggerAction: (@MainActor () -> Void)?
    public private(set) var currentShortcut: HotKeyShortcut?

    public static var isTestingEnvironment: Bool {
        NSClassFromString("XCTest") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") })
    }

    private init() {
        if !Self.isTestingEnvironment {
            installCarbonEventHandler()
        }
    }

    public func register(shortcut: HotKeyShortcut, onTrigger: (@MainActor () -> Void)? = nil) {
        let action = onTrigger ?? self.triggerAction
        unregister()
        self.triggerAction = action
        self.currentShortcut = shortcut

        guard !Self.isTestingEnvironment else { return }

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
        currentShortcut = nil
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, inEvent, inUserData -> OSStatus in
            guard let inUserData = inUserData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(inUserData).takeUnretainedValue()
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    manager.triggerAction?()
                }
            } else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        manager.triggerAction?()
                    }
                }
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
