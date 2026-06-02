# SimpleScreen — Agent Notes

## Build

- Xcode-only project (no SPM, no Makefile, no CLI build scripts). Build from Xcode: open `SimpleScreen.xcodeproj`, scheme `SimpleScreen`, destination My Mac.
- Command-line build: `xcodebuild -project SimpleScreen.xcodeproj -scheme SimpleScreen -configuration Debug build`
- No tests, no CI, no lint/typecheck commands.

## Architecture

- Single-target macOS app. All source is under `SimpleScreen/`, grouped by responsibility:
  - `SimpleScreenApp.swift` — `@main` entry; sets `.accessory` activation policy (no Dock icon).
  - `AppDelegate.swift` — bootstraps all services in `applicationDidFinishLaunching`.
  - `Capture/CaptureEngine.swift` — `@Observable`; wraps `SCScreenshotManager`; save-to-file, copy-to-clipboard, or both.
  - `Capture/AreaSelectionWindow.swift` — `CropWindow` (`NSWindow` at `.floating`) showing a captured full-screen image for drag-to-crop.
  - `HotKeys/HotKeyManager.swift` — Carbon `RegisterEventHotKey` (default Cmd+Shift+3 = full, Cmd+Shift+4 = area).
  - `Menu/StatusBarController.swift` — owns `NSStatusItem` and menu; reactively updates key equivalents; performs the crop.
  - `Notifications/NotificationManager.swift` — `UNUserNotificationCenter` banners post-capture.
  - `Preferences/AppSettings.swift` — `@Observable` single source of truth; all `UserDefaults` keys are `ss_`-prefixed.
  - `Preferences/PreferencesView.swift` — SwiftUI `Form` in a floating `NSPanel`.
- **Data flow**: `AppSettings` (single `@Observable` truth) → observed by `CaptureEngine`, `StatusBarController`, `PreferencesView`. No other file touches `UserDefaults` or `SCScreenshotManager` directly.
- Hotkeys use Carbon `RegisterEventHotKey` (not NSEvent global monitors). Hotkey IDs: `1` = full screen, `2` = area select. Signature: `0x5353_4353`.

## Key Gotchas

- **App is sandbox-disabled** (`com.apple.security.app-sandbox = false` in entitlements). It accesses `UserDefaults`, filesystem, `SMAppService` — do not enable sandbox without rewriting persistence and launch-at-login.
- **Dock-hidden**: `NSApp.setActivationPolicy(.accessory)` + `LSUIElement = true` in Info.plist. No Dock icon.
- **Area selection**: captures the full screen first via `SCScreenshotManager.captureImage`, then presents the image in a borderless `NSWindow` at `.floating` level for drag-to-crop. No compositor delay or coordinate conversion needed.
- **Capture guard**: `isCapturing` flag silently drops a second capture if one is already in progress.
- **Retina capture**: `SCDisplay.width/height` are in logical points. `SCStreamConfiguration.width/height` must be multiplied by `NSScreen.backingScaleFactor` to get a native-resolution capture; otherwise the image is half-res. `StatusBarController` then converts the points-based selection rect to pixels with the same scale factor before `CGImage.cropping(to:)`.
- **`CropWindow.isReleasedWhenClosed = false`**: required. `StatusBarController` keeps a strong reference in `cropWindow` and nils it after `cropCompletion`. With the default `true`, `close()` releases the window, then the later `cropWindow = nil` over-releases and crashes in `objc_release`.
- **UserDefaults keys** are `ss_`-prefixed (e.g. `ss_postCaptureAction`, `ss_saveLocationPath`).
- **TCC string**: `Info.plist` declares `NSScreenCaptureUsageDescription`. Required — without it the app cannot obtain Screen Recording permission and capture silently fails.

## Frameworks

Carbon, ScreenCaptureKit, ServiceManagement, UserNotifications. No third-party dependencies.

## Runtime Debug Log

`CaptureEngine` and `AreaSelectionWindow` write to `/tmp/simplescreenlog.txt`. Not conditional — always on.

## Distribution

Archive in Xcode → Developer ID → Notarize → `xcrun stapler staple` → `ditto -c -k --keepParent` for zip.

## Swift Concurrency

Build sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. New types are `MainActor`-isolated by default; use `nonisolated` or explicit isolation if needed.
