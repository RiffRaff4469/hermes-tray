# HermesTray v3 — real .app bundle, login autostart, Quit/Restart

Repo: C:/Users/jaide/projects/hermes-tray (SwiftPM executable, macOS 13+, SwiftUI MenuBarExtra). Windows host — no macOS SDK; self-review hard. Do NOT run git.

Goal: turn the SwiftPM executable into a proper macOS .app so Jaiden can run it from /Applications instead of Xcode, with login autostart and Quit/Restart in the dropdown.

## Existing files (do not break)
Package.swift, HermesTrayApp.swift (MenuBarExtra + Settings Window scene), Store.swift (polling, base URL default http://100.70.40.46:9119), APIClient.swift (token bootstrap + /api/* + /api/tray/jobs), Models.swift, Views.swift (TrayContentView: header, JOBS/ACTIVE/RECENT ScrollView fixed height 360, StatsFooterView, footer HStack with "Open Dashboard" + "Settings…" buttons), TokenStore.swift, Formatting.swift, support/hermes-tunnel.plist (unused legacy), README.md.

## 1. App bundle support files
- `support/Info.plist` (new, checked in): CFBundleIdentifier `com.jaide.HermesTray`, CFBundleName HermesTray, CFBundleDisplayName HermesTray, CFBundleExecutable HermesTray, CFBundlePackageType APPL, CFBundleShortVersionString 3.0.0, CFBundleVersion 3, LSMinimumSystemVersion 13.0, LSUIElement true (menu-bar only, no Dock icon), NSHighResolutionCapable true, NSHumanReadableCopyright "© 2026 jaide".
  - **CRITICAL — ATS**: the app talks plain HTTP to http://100.70.40.46:9119 (a Tailscale/CGNAT IP, NOT loopback). A bundled app with an Info.plist enforces ATS, which blocks cleartext HTTP to non-loopback hosts. Include `NSAppTransportSecurity` → `NSAllowsArbitraryLoads` = true (personal tool talking to own PC over WireGuard). Without this the .app will silently fail to connect while the bare Xcode run worked.
- `scripts/make_app.sh` (new, checked in): builds + assembles + signs the .app.
  - `#!/usr/bin/env bash`, `set -euo pipefail`; run from repo root regardless of cwd (cd "$(dirname "$0")/..").
  - `swift build -c release` (macOS 13+ / Xcode present).
  - Assemble `HermesTray.app`: mkdir -p Contents/MacOS Contents/Resources; cp `.build/release/HermesTray` → Contents/MacOS/; cp `support/Info.plist` → Contents/.
  - Ad-hoc codesign (required on Apple Silicon): `codesign --force --deep -s - HermesTray.app`.
  - Print the app path + "drag to /Applications" hint. Exit non-zero on any failure. Must be runnable as `./scripts/make_app.sh` from the cloned repo on Jaiden's Mac.

## 2. Quit + Restart in the dropdown
In TrayContentView's footer HStack (Views.swift), alongside Open Dashboard / Settings…, add a Spacer-separated "Restart…" and a "Quit" control. `import AppKit` at top of Views.swift.
- Quit: `NSApplication.shared.terminate(nil)`.
- Restart: only meaningful from a bundled .app. Guard on `Bundle.main.bundleIdentifier != nil`. Implementation: spawn `/usr/bin/open` with `Bundle.main.bundleURL.path` (the .app), then `NSApplication.shared.terminate(nil)` ~0.4s later (DispatchQueue.main.asyncAfter). When running as a bare SwiftPM executable (no bundle id) either hide Restart or disable it with a tooltip.
- Keep the footer compact; font .caption consistent with existing buttons.

## 3. Settings window: "Launch at login" toggle
In SettingsView (Views.swift), below the base-URL field, add a `Toggle("Launch at login", isOn:)` backed by macOS 13+ `SMAppService`:
- `import ServiceManagement` (available macOS 13+; min target is already 13.0).
- State: on appear, `if Bundle.main.bundleIdentifier != nil { isOn = SMAppService.mainApp.status == .enabled }` (guard — bare-executable Xcode runs have no bundle and SMAppService.mainApp would throw).
- On change: try `SMAppService.mainApp.register()` / `try SMAppService.mainApp.unregister()`; on error set a small red caption and revert the toggle. Note: when the app is running from a bare executable (no bundle), hide the toggle entirely (`.hidden()` or conditional) with no crash.
- Under the toggle add `.font(.caption)` helper text: "Relaunch the app from /Applications once for this to take effect." (SMAppService.mainApp requires the bundle in a stable location like /Applications.)

## 4. README update
New "Run as a real app" section: `./scripts/make_app.sh` → `cp -R HermesTray.app /Applications/` → `open /Applications/HermesTray.app` → Settings → Launch at login. Note: stop the Xcode instance first (`pkill -f HermesTray`), and that Quit/Restart are in the dropdown footer. Keep existing sections accurate (default URL line already says Tailscale IP — fine).

## Constraints
- macOS 13 compatibility everywhere (SMAppService + MenuBarExtra + symbolEffect guarded as today).
- No third-party deps. Files stay reasonably sized. Do not touch Store/APIClient/Models polling or decode logic. Do not run git.
- Self-review: ATS keys spelling in Info.plist, SMAppService API misuse, bundle-path handling, codesign flag correctness for Apple Silicon.
- When done print: every file created/changed + the exact two commands Jaiden runs on the Mac to install and launch the .app.
