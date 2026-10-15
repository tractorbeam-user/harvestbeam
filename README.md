# Harvestbeam

A small, native Harvest timer for the Mac menu bar, with the same app on iPhone and iPad. Unofficial: it talks to the [Harvest API v2](https://help.getharvest.com/api-v2/) using your own personal access token.

- **Menu bar, like Harvest's own**: an orange square with pause while a timer runs, gray with play when paused, then the time and what you're working on. Click the square to pause or resume; click the rest to show or hide the window. Gear → Menu Bar picks what text appears and how long it can get.
- **⌥H anywhere** shows or hides the window with the search field focused. Type, use the arrow keys, and press Return.
- **Orange title bar** with the selected day and the week's total. The calendar button (⌘T) jumps to today, and the info button opens a Time Summary: hours today, yesterday, this week and this month.
- **Days**: a week strip with each day's total. ‹ › and ⌘[ / ⌘] move a day at a time. Each day lists its entries with play/pause. Double-click an entry to edit its project, task, notes or hours. Deleting asks nothing and offers Undo (⌘Z) instead.
- **New entries**: + in the bottom bar (⌘N), or New Entry on an empty day, opens a Harvest-style popover: project, then task, notes and hours. On today, leave hours empty to start a timer; on other days it logs the hours.
- **Search** in two steps: matching projects first, grouped by client, then the picked project's tasks. Every word has to match across task, project, code and client, and favorites and frequently used tasks rank higher.
- **Favorites, Recent and Suggested** as compact tiles: project, then task, with a bracketed code like `[LP-DP-01]` on its own line. Star any task to pin it; favorites sync through iCloud when the app is signed.
- **Stays in sync** with Harvest's own apps: it checks every minute, and if a timer changed elsewhere it reloads instead of erroring. Times round to the nearest minute, as Harvest's do.
- **A real window**: drag it anywhere and resize it. Gear menu: Keep on Top, Move Below Menu Bar Icon, Reset Window Size (⌘0, or the green button).
- Your token is stored in the Keychain, never in preferences.

## Install

Download the latest `Harvestbeam-x.y.z.zip` from [Releases](https://github.com/tractorbeam-user/harvest-bar/releases), unzip it and drag **Harvestbeam** to Applications.

The first time, **right-click it and choose Open**. The app isn't signed with an Apple Developer ID, so macOS asks once. If macOS says it's damaged, run `xattr -dr com.apple.quarantine "/Applications/Harvestbeam.app"` in Terminal and open it again.

Click the timer icon in the menu bar, create a personal access token at [id.getharvest.com/developers](https://id.getharvest.com/developers), and paste it in.

## Releasing

```bash
scripts/release.sh 1.1.0
```

From a clean `main`, this pushes, builds the app with that version, zips it and publishes a GitHub Release with install notes. It needs the GitHub CLI (`gh`) signed in.

## Build it yourself

```bash
scripts/build-app.sh --install
```

This builds `Harvestbeam.app`, copies it to `/Applications` and launches it. Click the timer icon in the menu bar, follow the link to create a token at [id.getharvest.com/developers](https://id.getharvest.com/developers), and paste it in. If the token can reach more than one Harvest account, you'll be asked to pick one. You can turn on **Open at Login** from the gear menu.

To try the UI without an account: `open "build/Harvestbeam.app" --args --demo`.

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
| `Sources/HarvestBar`    | Mac menu bar app: status item, window, ⌥H                                                                          |
| `iOS`                   | iPhone/iPad app entry point                                                                                        |
| `Tests/HarvestKitTests` | Ranking, search and decoding tests (run in Xcode, or with `swift test` once Xcode is installed)                    |

Debug builds can render the panel to PNGs with demo data, in light and dark mode: `swift build && .build/debug/HarvestBar --snapshots ~/Desktop/harvest-snaps`.
