# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See `AGENTS.md` for full architecture, gotchas, and distribution notes. This file covers the essentials plus what AGENTS.md omits.

## Build

```bash
xcodebuild -project SimpleScreen.xcodeproj -scheme SimpleScreen -configuration Debug build
```

No tests, no CI, no lint/typecheck commands. Open `SimpleScreen.xcodeproj` in Xcode for development.

## Quick architecture

Single-target macOS status-bar screenshot app. No third-party dependencies.

- `SimpleScreenApp.swift` — `@main` entry point, sets `.accessory` activation policy (no Dock icon)
- `AppDelegate.swift` — bootstraps all services in `applicationDidFinishLaunching`
- `AppSettings.swift` — `@Observable` single source of truth; all `UserDefaults` keys are `ss_`-prefixed
- `CaptureEngine.swift` — `@Observable`; wraps `SCScreenshotManager`; handles save-to-file, copy-to-clipboard, or both
- `AreaSelectionWindow.swift` — `CropWindow` (`NSWindow` at `.floating`) that displays a captured full-screen image for drag-to-crop
- `HotKeyManager.swift` — Carbon `RegisterEventHotKey` (Cmd+Shift+3 = full, Cmd+Shift+4 = area)
- `StatusBarController.swift` — owns `NSStatusItem` and menu; reactively updates key equivalents
- `PreferencesView.swift` — SwiftUI `Form` in a floating `NSPanel`
- `NotificationManager.swift` — `UNUserNotificationCenter` banners post-capture

**Data flow**: `AppSettings` → observed by `CaptureEngine`, `StatusBarController`, `PreferencesView`. Nothing else touches `UserDefaults` or `SCScreenshotManager` directly.

**Swift Concurrency**: Build sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. New types are `MainActor`-isolated by default.

## Key constraints

- **Sandbox disabled** — `com.apple.security.app-sandbox = false`. Do not enable without rewriting persistence and launch-at-login.
- **Dock hidden** — `.accessory` policy + `LSUIElement = true`.
- **Capture guard** — `isCapturing` flag silently drops concurrent captures.

## Frameworks

Carbon, ScreenCaptureKit, ServiceManagement, UserNotifications.

## Debug log

`CaptureEngine` and `AreaSelectionWindow` write to `/tmp/simplescreenlog.txt`. Always on.
