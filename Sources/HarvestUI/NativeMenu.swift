import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One item in a menu that's built once and shown both as a ⋯ menu and on
/// right-click.
struct MenuAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void
}

#if os(macOS)
/// Pops a native menu where the click that asked for it landed. SwiftUI's
/// Menu with a plain custom label only opens when the click hits a drawn
/// pixel of the label, and it can lose the click in the floating panel, so a
/// plain Button (which always takes the click) opens this instead.
enum NativeMenu {
    static func popUp(_ actions: [MenuAction]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = Target(actions)
        for (index, item) in actions.enumerated() {
            let menuItem = NSMenuItem(title: item.title, action: #selector(Target.fire(_:)), keyEquivalent: "")
            menuItem.target = target
            menuItem.tag = index
            menuItem.isEnabled = item.isEnabled
            menuItem.image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil)
            menu.addItem(menuItem)
        }
        // popUp tracks the menu until it closes, so `target` lives long enough.
        if let event = NSApp.currentEvent, let view = event.window?.contentView {
            let point = view.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: point, in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        withExtendedLifetime(target) {}
    }

    private final class Target: NSObject {
        let actions: [MenuAction]
        init(_ actions: [MenuAction]) { self.actions = actions }
        @objc func fire(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag].action()
        }
    }
}
#endif

/// The same actions as SwiftUI buttons, for right-click menus (and the ⋯
/// menu on iPhone and iPad).
struct MenuActionButtons: View {
    let actions: [MenuAction]
    var body: some View {
        ForEach(actions) { item in
            Button(item.title, systemImage: item.systemImage, action: item.action)
                .disabled(!item.isEnabled)
        }
    }
}
