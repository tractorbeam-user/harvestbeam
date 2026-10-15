# Harvest Bar

A small, native Harvest timer for the Mac menu bar, with the same app on iPhone and iPad. Unofficial: it talks to the [Harvest API v2](https://help.getharvest.com/api-v2/) using your own personal access token.

- **⌥H anywhere** shows or hides the window with the search field focused. Type, use the arrow keys to move between tiles, and press Return to start. Esc clears the search, then hides the window.
- **A real window**: it opens below the menu bar icon the first time. After that you can drag it anywhere and resize it, and it remembers where you left it. The gear menu has **Keep on Top** and **Move Below Menu Bar Icon**.
- **Pause and resume**: the running timer has a big Pause button (⌘.), and when nothing is running, today's last entry shows a Resume button.
- **Days and weeks**, like Harvest's own app: a week strip with each day's total, ‹ › to page weeks, ⌘[ / ⌘] for the previous or next day, and ⌘T for today. Each day lists its entries, and clicking one restarts it. Older weeks load from Harvest as you page back.
- **Sidebar** (⌃⌘S or the sidebar button): Everything, Favorites, your own folders, and every client. Drag a tile onto a folder, or right-click a task and choose Move to Folder.
- **Menu bar text**: shows what you're working on next to the timer. Gear → Menu Bar picks what appears (time, task, task and project, or notes), how long it can get, and whether it cuts off the end or the middle.
- **Search** sits in the bottom bar, and results are a compact list grouped by client, with `[CODE] Project · Task` on each line. ⌘A, ⌘C and ⌘V work in every field.
- **Tiles**: Favorites, Recent and Suggested are large click and tap targets in a grid that adds columns as the window gets wider.
- **Favorites**: star any task to pin it. Favorites sync between devices through iCloud when the app is signed (see below).
- **Recent**: your last few distinct tasks, taken from your Harvest history, so they're the same on every device.
- **Suggested**: tasks you use most over the last 60 days. Each entry's weight halves every two weeks, and tasks you tend to track on the same weekday get a bump.
- **Search** across task, project, project code and client. Every word has to match, prefix matches rank first, and accents and case are ignored. Task names are indexed once when they load, so typing stays instant even with thousands of tasks.
- **Menu bar**: an orange dot and the elapsed time while a timer runs. Starting a task you've already tracked today restarts that entry, the same way Harvest's own timer works.
- Your token is stored in the Keychain, never in preferences.

## Run it on your Mac

```bash
scripts/build-app.sh --install
```

This builds `Harvest Bar.app`, copies it to `/Applications` and launches it. Click the timer icon in the menu bar, follow the link to create a token at [id.getharvest.com/developers](https://id.getharvest.com/developers), and paste it in. If the token can reach more than one Harvest account, you'll be asked to pick one. You can turn on **Open at Login** from the gear menu.

To try the UI without an account: `open "build/Harvest Bar.app" --args --demo`.

Only the Xcode Command Line Tools are needed. The build script automatically uses the macOS 26.5 SDK, because the newest SDK expects SwiftUI macro plugins that ship only with full Xcode.

### About ⌥H

The shortcut is registered with Carbon's hotkey API, which needs no permissions. If a future macOS rejects Option-only shortcuts there, the app falls back to a keyboard event tap and asks for **Accessibility** access (System Settings → Privacy & Security → Accessibility). After a rebuild, the ad-hoc signature changes, so you may need to toggle it again.

## iPhone and iPad

The Mac and iOS apps share everything except the menu bar shell (`Sources/HarvestBar`). On iPhone and iPad you get the same timer card, day view and large tiles, sized for touch, plus a native search bar and pull to refresh.

Building for iOS needs full Xcode:

```bash
brew install xcodegen
xcodegen            # generates HarvestBar.xcodeproj from project.yml
open HarvestBar.xcodeproj
```

Pick your team under Signing for both targets, then run **HarvestBar-iOS** on your phone. Signing also turns on the iCloud key-value entitlement, which is what syncs favorites between devices.

## Layout

| Path                    | What's there                                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `Sources/HarvestKit`    | Models, Harvest API client, Keychain, favorites, ranking (recent/suggested/search), `TimeTracker` state, demo data |
| `Sources/HarvestUI`     | SwiftUI views shared by macOS and iOS                                                                              |
| `Sources/HarvestBar`    | Mac menu bar app: status item, popover, ⌥H                                                                         |
| `iOS`                   | iPhone/iPad app entry point                                                                                        |
| `Tests/HarvestKitTests` | Ranking, search and decoding tests (run in Xcode, or with `swift test` once Xcode is installed)                    |

Debug builds can render the panel to PNGs with demo data, in light and dark mode: `swift build && .build/debug/HarvestBar --snapshots /tmp/harvest-snaps`.
