import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut (⌥H by default) that works whichever app is in front.
///
/// Uses Carbon's `RegisterEventHotKey`, which needs no permissions. Since macOS
/// 15 that API refuses shortcuts whose only modifier is Option, so when it fails
/// we fall back to an event tap, which needs Accessibility access (System
/// Settings → Privacy & Security → Accessibility).
@MainActor
final class HotKey {
    enum Mode { case carbon, eventTap, needsAccessibility }

    private(set) var mode: Mode = .needsAccessibility
    private let keyCode: UInt32
    private let carbonModifiers: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var tap: CFMachPort?
    private var retryTimer: Timer?

    /// The shortcut as stored in preferences: a key code plus Carbon modifiers.
    struct Shortcut: Equatable {
        var keyCode: Int
        var carbonModifiers: Int
        static let `default` = Shortcut(keyCode: kVK_ANSI_H, carbonModifiers: optionKey)

        static let keyCodeKey = "shortcut.toggle.keyCode"
        static let modifiersKey = "shortcut.toggle.modifiers"

        /// Saved shortcut, the default, or nil when the user cleared it.
        static func load() -> Shortcut? {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: keyCodeKey) != nil else { return .default }
            let code = defaults.integer(forKey: keyCodeKey)
            return code < 0 ? nil : Shortcut(keyCode: code, carbonModifiers: defaults.integer(forKey: modifiersKey))
        }

        static func save(_ shortcut: Shortcut?) {
            UserDefaults.standard.set(shortcut?.keyCode ?? -1, forKey: keyCodeKey)
            UserDefaults.standard.set(shortcut?.carbonModifiers ?? 0, forKey: modifiersKey)
        }

        var eventFlags: CGEventFlags {
            var flags: CGEventFlags = []
            if carbonModifiers & optionKey != 0 { flags.insert(.maskAlternate) }
            if carbonModifiers & cmdKey != 0 { flags.insert(.maskCommand) }
            if carbonModifiers & controlKey != 0 { flags.insert(.maskControl) }
            if carbonModifiers & shiftKey != 0 { flags.insert(.maskShift) }
            return flags
        }
    }

    init(keyCode: Int = kVK_ANSI_H, carbonModifiers: Int = optionKey, action: @escaping () -> Void) {
        self.keyCode = UInt32(keyCode)
        self.carbonModifiers = UInt32(carbonModifiers)
        self.action = action
        if registerCarbon() {
            mode = .carbon
        } else if installEventTap(prompt: true) {
            mode = .eventTap
        } else {
            mode = .needsAccessibility
            // Pick the shortcut up as soon as the user grants Accessibility.
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.installEventTap(prompt: false) else { return }
                    self.mode = .eventTap
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                }
            }
        }
    }

    fileprivate func fire() { action() }

    // MARK: Carbon

    private func registerCarbon() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.fire() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard installed == noErr else { return false }

        let id = EventHotKeyID(signature: OSType(0x4842_4152), id: 1) // "HBAR"
        let status = RegisterEventHotKey(keyCode, carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return false
        }
        return true
    }

    // MARK: Event tap fallback

    private func installEventTap(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary // kAXTrustedCheckOptionPrompt
        guard AXIsProcessTrustedWithOptions(options) else { return false }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { hotKey.reenableTap() }
                    return Unmanaged.passUnretained(event)
                }
                let flags = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let wanted = MainActor.assumeIsolated { (hotKey.keyCode, hotKey.shortcutFlags) }
                guard flags == wanted.1, code == Int64(wanted.0) else {
                    return Unmanaged.passUnretained(event)
                }
                DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.fire() } }
                return nil // swallow it so "˙" isn't typed into the front app
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private var shortcutFlags: CGEventFlags {
        Shortcut(keyCode: Int(keyCode), carbonModifiers: Int(carbonModifiers)).eventFlags
    }

    /// Unregisters the shortcut, so a new one can replace it.
    func invalidate() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    private func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}
