# SimpleScreen

A macOS status bar screenshot app.

## Codebase Overview

**Entry point**
- `SimpleScreenApp.swift` — `@main` SwiftUI App, wires `AppDelegate`, suppresses Dock via `.accessory` policy
- `AppDelegate.swift` — bootstraps all services, checks screen recording permission on launch, polls for grant

**Core services**
- `Preferences/AppSettings.swift` — `@Observable` single source of truth for all user settings; reads/writes `UserDefaults` using `ss_`-prefixed keys
- `HotKeys/HotKeyManager.swift` — wraps Carbon `RegisterEventHotKey`; manages Cmd+Shift+3 (full screen) and Cmd+Shift+4 (area select)
- `Notifications/NotificationManager.swift` — wraps `UNUserNotificationCenter`; fires banners after each capture

**Capture**
- `Capture/CaptureEngine.swift` — `@Observable`; uses `SCScreenshotManager` (ScreenCaptureKit) for both full-screen and region captures; dispatches to save-to-file, copy-to-clipboard, or both per `AppSettings.postCaptureAction`; falls back to Desktop if save fails
- `Capture/AreaSelectionWindow.swift` — borderless `NSWindow` at `.screenSaver` level covering the primary display; `SelectionView` handles drag-to-select with live pixel dimensions, Escape to cancel, and a 10×10 minimum size guard

**UI**
- `Menu/StatusBarController.swift` — owns the `NSStatusItem` (camera icon); builds and owns the dropdown menu; reactively updates key equivalents via `withObservationTracking`
- `Preferences/PreferencesView.swift` — SwiftUI `Form` hosted in a floating `NSPanel`; configures post-capture action, save folder, keyboard shortcuts (with conflict detection), and launch-at-login

**Data flow**: `AppSettings` → observed by `CaptureEngine`, `StatusBarController`, and `PreferencesView`. All capture goes through `CaptureEngine`. All hotkeys go through `HotKeyManager`. All notifications go through `NotificationManager`. Nothing else touches `UserDefaults` or `SCScreenshotManager` directly.

## Requirements

- Xcode 16+
- macOS 15.6+
- Apple Developer account (for signing; local builds can use Personal Team)

## Build & Run

1. Open `SimpleScreen.xcodeproj` in Xcode
2. Select the `SimpleScreen` scheme and your Mac as the run destination
3. Press **⌘R**

The app appears in the macOS status bar (camera icon). No Dock icon appears.

### First-run permissions

On first launch the app checks for Screen Recording permission:

- If already granted, the app is ready immediately.
- If not granted, an alert appears with an **Open System Settings** button. Grant access under **System Settings → Privacy & Security → Screen Recording**.
- The app polls every second — capture is re-enabled automatically once permission is granted, no relaunch needed.

## Usage

### Capturing

| Action | Menu item | Default shortcut |
|--------|-----------|-----------------|
| Capture full screen | Camera icon → Capture Full Screen | **⌘⇧3** |
| Capture selected area | Camera icon → Capture Selected Area | **⌘⇧4** |

**Area select**: a crosshair overlay appears over the primary display. Drag to draw a rectangle — live pixel dimensions are shown next to the cursor. Release to capture. Press **Escape** to cancel. Selections smaller than 10×10 px are rejected with an alert.

A second capture triggered while one is already in progress is silently ignored.

### Post-capture actions

Configured in Preferences. Three modes:

| Mode | Effect |
|------|--------|
| Save to File | PNG written to the configured save folder |
| Copy to Clipboard | Image placed on the clipboard |
| Save & Copy (default) | Both of the above |

A notification banner confirms the result after every capture. Files are named `Screenshot YYYY-MM-DD at HH.MM.SS.png`. If the save folder is unavailable the app falls back to `~/Desktop` and shows an alert.

### Preferences

Open via **Camera icon → Preferences…**

- **Post-Capture Action** — choose Save, Copy, or both
- **Save Location** — click **Choose…** to pick any folder; defaults to `~/Pictures/Screenshot/`
- **Keyboard Shortcuts** — click **Record** next to Full Screen or Area Select, then press your desired shortcut; conflicts with system shortcuts are detected and reported inline
- **Launch at Login** — toggle to register/unregister the app with `SMAppService`

All settings persist across restarts.

## Logs

SimpleScreen writes diagnostics through macOS unified logging (`os.Logger`) — no files are created in `/tmp` or your home directory. macOS rotates and ages out the log automatically.

**Where to look**

- **Console.app**: open it, then type `subsystem:com.simplescreenapp.SimpleScreen` in the search field.
- **Terminal**: `log show --predicate 'subsystem == "com.simplescreenapp.SimpleScreen"' --debug --last 1h`

**What's logged**

- Category `capture` — screen-capture events: save folder, image dimensions, successful file/clipboard writes, and failures.
- Category `areaSelect` — area-selection window events: open/close, mouse drag, Escape cancellation, selection-too-small.

**Levels**

By default macOS shows `info` and `error` entries only. For verbose diagnostics, pass `--debug` to `log show` or enable **Action → Include Debug Messages** in Console.app.

## Distribution (Notarization)

1. Archive in Xcode: **Product → Archive**
2. Distribute → Developer ID → Notarize
3. Staple the ticket: `xcrun stapler staple SimpleScreen.app`
4. Compress for distribution: `ditto -c -k --keepParent SimpleScreen.app SimpleScreen.zip`
