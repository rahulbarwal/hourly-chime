# HourlyChime

A minimal macOS menu bar app that shows the current time and plays a soft chime at the top of every hour.

## Features

- Displays current time in the menu bar (e.g. `10:00 AM`), updated every 30 seconds
- Plays a short system sound exactly at each hour boundary (no catch-up on wake)
- Configurable sound: Tink, Ping, Pop, Glass, Purr (default: Tink)
- Configurable volume: Quiet (0.3), Medium (0.6), Loud (1.0) (default: Quiet)
- Launch at Login toggle via `SMAppService`
- No Dock icon (`LSUIElement = YES` in Info.plist)
- No Accessibility permission required

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (for the `.xcodeproj` build path)
- Alternatively: `swiftc` from Xcode Command Line Tools (for `build.sh`)

## How to open in Xcode and run

1. Open `HourlyChime.xcodeproj` in Xcode.
2. Select the `HourlyChime` scheme and your Mac as the destination.
3. Press `Cmd+R` to build and run.
4. The app appears only in the menu bar — no Dock icon or main window.

To code-sign with your own identity, Xcode will handle this automatically with `CODE_SIGN_STYLE = Automatic` when you are signed in to your Apple ID in Xcode Preferences.

## Alternative: build with build.sh

If you prefer not to use Xcode, build the standalone binary directly:

```bash
cd /Users/rahulbarwal/Documents/personal-tech/hourly-chime
chmod +x build.sh
./build.sh
open HourlyChime.app
```

This compiles with `swiftc` targeting `arm64-apple-macosx13.0` and creates a minimal `.app` bundle. Note that the binary will not be code-signed, so macOS Gatekeeper may block it on first launch — right-click the app and choose Open to bypass this once.

**Note: `build.sh` produces an Apple Silicon (arm64) binary only.** If you are running on an Intel Mac, open the project in Xcode instead — Xcode auto-detects the host architecture and builds a native binary for it.

## Permissions

- No Accessibility permission required.
- No microphone, camera, or network access requested.
- Sandbox is disabled (`com.apple.security.app-sandbox = false`) to allow `SMAppService` to register the launch item without additional entitlements.

## Project structure

```
HourlyChime/
    AppDelegate.swift       -- all application logic (~150 lines)
    Info.plist              -- LSUIElement = YES hides Dock icon
    HourlyChime.entitlements
HourlyChime.xcodeproj/
    project.pbxproj
build.sh                    -- swiftc build script (no Xcode needed)
README.md
```
