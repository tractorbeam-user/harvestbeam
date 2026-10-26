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

Download the latest `Harvestbeam-x.y.z.dmg` from [Releases](https://github.com/tractorbeam-user/harvestbeam/releases), open it and drag **Harvestbeam** into Applications.

The app isn't signed with an Apple Developer ID, so macOS blocks it the first time:

1. Open Harvestbeam. macOS says it can't verify it. Click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down to Security and click **Open Anyway** next to Harvestbeam.
3. Confirm with your password (or Touch ID) and click **Open**.

You only do this once. Updates install and open normally. If macOS ever says the app is damaged instead, run `xattr -dr com.apple.quarantine "/Applications/Harvestbeam.app"` in Terminal and open it again.

The first launch opens a short welcome: where the timer lives, the ⌥H shortcut (try it right there), and connecting Harvest with a personal access token from [id.getharvest.com/developers](https://id.getharvest.com/developers). To see it again: `open /Applications/Harvestbeam.app --args --onboarding`.

## Releasing

```bash
scripts/release.sh 1.1.0 "**New:** Start Again Today from any entry.
- Fixed a crash when a project had no tasks."
```

A beta goes out on its own channel, with the beta features (Sources/HarvestUI/Beta.swift) switched on:

```bash
CHANNEL=beta scripts/release.sh 1.4.0-beta.1 "**Beta:** automatic tracking."
```

It's a GitHub pre-release, so the site's "latest" download stays the regular version, and its appcast item is marked `<sparkle:channel>beta</sparkle:channel>`, so only beta builds are offered it. Beta builds still take regular releases.

From a clean `main`, this pushes, builds the app with that version, wraps it in a branded disk image (`scripts/make-dmg.sh`) and publishes a GitHub Release with install notes. Then it signs the disk image with Sparkle's `sign_update`, adds the release to [`appcast.xml`](appcast.xml) and commits and pushes that to `main`. It needs the GitHub CLI (`gh`) signed in and the update signing key (below).

### Updates

The Mac app updates itself with [Sparkle](https://sparkle-project.org). It checks `appcast.xml` on `main` (raw.githubusercontent.com) once a day, and **Check for Updates…** in the app menu or Preferences → General checks right away. Harvestbeam draws the update window itself (`Sources/HarvestBar/UpdatePrompt.swift`), with the release notes from the second argument to `release.sh` (light Markdown, optional). The repo has to be public for other people's copies to reach the feed and the downloads. The feed URL and public key are set in `scripts/build-app.sh`; the build number, which only goes up (it's the commit count), is what Sparkle compares.

Sparkle only installs updates signed with the private EdDSA key. It lives in the login Keychain of the Mac that ran `generate_keys` (a password item for `https://sparkle-project.org`, account `ed25519`), never in git, and `sign_update` reads it from there, so macOS may ask to allow access the first time. Keep a backup somewhere safe, like a password manager: without it, installed copies can never be updated again.

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key   # export
.build/artifacts/sparkle/Sparkle/bin/generate_keys -f sparkle-private-key   # import on another Mac
```

`SPARKLE_KEY_FILE=path scripts/release.sh 1.1.0` signs with an exported key file instead of the Keychain.

The app is signed ad hoc, not with a Developer ID, which matters only for the first download: Gatekeeper quarantines the download, so people allow it once with **Open Anyway** in System Settings → Privacy & Security (right-click → Open no longer works for this since macOS 15). Updates installed by Sparkle aren't quarantined, so they open without that prompt. Sparkle trusts an update because of its EdDSA signature, not its code signature, which changes with every ad hoc build. That makes the private key the one thing that has to stay secret. Notarizing would need an Apple Developer account and a Developer ID certificate.

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
| `Sources/HarvestBar`    | Mac menu bar app: status item, window, ⌥H, Sparkle updates                                                         |
| `iOS`                   | iPhone/iPad app entry point                                                                                        |
| `Tests/HarvestKitTests` | Ranking, search and decoding tests (run in Xcode, or with `swift test` once Xcode is installed)                    |

Debug builds can render the panel to PNGs with demo data, in light and dark mode: `swift build && .build/debug/HarvestBar --snapshots ~/Desktop/harvest-snaps`.
