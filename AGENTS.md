# SimpleScreen — Agent Notes

## Build

- Xcode-only project (no SPM, no Makefile, no CLI build scripts). Build from Xcode: open `SimpleScreen.xcodeproj`, scheme `SimpleScreen`, destination My Mac.
- Command-line build: `xcodebuild -project SimpleScreen.xcodeproj -scheme SimpleScreen -configuration Debug build`
- No tests, no CI, no lint/typecheck commands.

## Architecture

- Single-target macOS app. All source is under `SimpleScreen/`.
- `@main` entry: `SimpleScreenApp.swift` → `AppDelegate` bootstraps all services in `applicationDidFinishLaunching`.
- **Data flow**: `AppSettings` (single `@Observable` truth) → observed by `CaptureEngine`, `StatusBarController`, `PreferencesView`. No other file touches `UserDefaults` or `SCScreenshotManager` directly.
- Hotkeys use Carbon `RegisterEventHotKey` (not NSEvent global monitors). Hotkey IDs: `1` = full screen, `2` = area select. Signature: `0x5353_4353`.

## Key Gotchas

- **App is sandbox-disabled** (`com.apple.security.app-sandbox = false` in entitlements). It accesses `UserDefaults`, filesystem, `SMAppService` — do not enable sandbox without rewriting persistence and launch-at-login.
- **Dock-hidden**: `NSApp.setActivationPolicy(.accessory)` + `LSUIElement = true` in Info.plist. No Dock icon.
- **Area selection overlay** is a borderless `NSPanel` at `.screenSaver` level. `isReleasedWhenClosed = false` is critical — AppKit over-releases it otherwise. Do not call `NSApp.activate` before showing the overlay (causes `EXC_BAD_ACCESS` on macOS 26).
- **Coordinate flip**: `CaptureEngine.captureArea(rect:)` flips the y-axis from AppKit (bottom-left) to ScreenCaptureKit (top-left) when building `sourceRect`.
- **150 ms sleep** before area capture — lets the selection overlay clear from the compositor.
- **Capture guard**: `isCapturing` flag silently drops a second capture if one is already in progress.
- **UserDefaults keys** are `ss_`-prefixed (e.g. `ss_postCaptureAction`, `ss_saveLocationPath`).

## Frameworks

Carbon, ScreenCaptureKit, ServiceManagement, UserNotifications. No third-party dependencies.

## Runtime Debug Log

`CaptureEngine` and `AreaSelectionWindow` write to `/tmp/simplescreenlog.txt`. Not conditional — always on.

## Distribution

Archive in Xcode → Developer ID → Notarize → `xcrun stapler staple` → `ditto -c -k --keepParent` for zip.

## Swift Concurrency

Build sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. New types are `MainActor`-isolated by default; use `nonisolated` or explicit isolation if needed.
