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
                guard flags == .maskAlternate, code == Int64(kVK_ANSI_H) else {
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

    private func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}
