# HermesTray — macOS menu bar monitor for a remote Hermes agent

You are building a complete, production-quality Swift project. Read this whole file first, then implement exactly what it specifies. Do NOT run `git` commands. Write all files into the directory this file lives in. You cannot compile here (Windows host, no macOS SDK) — so self-review hard for compile correctness, API misuse, and missing imports. Keep every file under ~450 lines; split cleanly.

## Product
A menu-bar-only macOS app (tray widget) that shows, at a glance, what a remote "Hermes" AI agent is doing right now. Hermes runs on a Windows PC; the dashboard API listens on `127.0.0.1:9119` on that PC. The Mac reaches it through an SSH tunnel (`ssh -N -L 9119:localhost:9119`), so from the app's perspective the API is at `http://127.0.0.1:9119` on localhost. Base URL must be user-configurable in a Settings view (default `http://127.0.0.1:9119`).

## What the menu bar shows
1. MenuBarExtra icon (SwiftUI `MenuBarExtra`). Icon: a simple "pulse" glyph (use SF Symbol `waveform.path.ecg` or similar). When the agent reports active/busy (see status endpoint) show a red/orange dot overlay or badge; idle = plain icon. Polled every 4s.
2. Dropdown content:
   - Header: connection state (Connected / Unreachable + last error), agent version, hostname.
   - "ACTIVE" section: session rows currently running (live). Row shows: title (fallback "Untitled session"), source badge (cron / telegram / cli / web / other), elapsed time ticking up live (from `started_at`, formatted mm:ss, then hh:mm:ss after an hour), tool-call count, model.
   - "RECENT" section: last ~8 finished sessions (idle), with elapsed total and a ✓ for successful end_reason.
   - System stats footer: CPU %, RAM used/total + %, disk free, uptime (from /api/system/stats).
   - Clicking a session row opens the Hermes dashboard home in the default browser.
3. Poll cadence: status + system stats every 4s; full sessions list every 6s. Local elapsed-time ticker updates every 1s without refetching.

## API contract (verified live — copy field names EXACTLY)

### Token bootstrap (required for /api/sessions and /api/system/stats)
`GET {base}/` returns HTML containing: `window.__HERMES_SESSION_TOKEN__="<token>"`. Regex it out, then send header `Authorization: Bearer <token>` on protected calls. On HTTP 401, re-bootstrap and retry once. Token may be cached in Keychain.

### GET /api/status — NO auth needed
```json
{"version":"0.20.0","gateway_running":true,"gateway_state":"running",
 "gateway_platforms":{"telegram":{"state":"connected"}},
 "active_agents":1,"gateway_busy":true,"active_sessions":0,
 "components":{"gateway":{"status":"ok"}},"overall":"ok","profiles":["default"]}
```
Busy indicator = `gateway_busy == true || active_agents > 0`.

### GET /api/sessions — Bearer token. Array under key "sessions".
```json
{"sessions":[{"id":"cron_aefe899a6fee_20260906_203019","source":"cron","chat_id":null,"thread_id":null,"display_name":null,
 "model":"deepseek-v4-flash","started_at":1788741020.63,"ended_at":1788741092.61,"end_reason":"cron_complete",
 "message_count":10,"tool_call_count":4,"input_tokens":11242,"output_tokens":8808,"cache_read_tokens":70144,
 "estimated_cost_usd":0.0,"title":"Orbit Daily Plan Draft (8:30pm, for next day) · Sep 06 20:31","title_source":"user",
 "last_activity_at":1788741087.96,"last_activity_description":"","unread":false,"is_active":false,
 "preview":"/orbit-daily-timeline-planner","profile":"default"}]}
```
Notes: timestamps are UNIX seconds (Double, may be fractional; some fields may be null). `is_active:true` = running right now. `source` ∈ cron|telegram|cli|web|… . `end_reason` null while active. Treat unknown/null defensively — decode everything as optional.

### GET /api/system/stats — Bearer token
```json
{"os":"Windows","hostname":"JDLaptop","cpu_count":16,"memory":{"total":16312729600,"available":1939836928,"used":14372892672,"percent":88.1},
 "disk":{"total":510745636864,"used":444124471296,"free":66621165568,"percent":87.0},"cpu_percent":14.0,"uptime_seconds":77187,
 "process":{"pid":6880,"rss":159072256,"num_threads":26},"psutil":true}
```
Formats: RAM "13.4 / 15.2 GB (88%)", disk free "62.1 GB free", uptime "21h 26m".

## Technical requirements
- Swift Package Manager executable package (NOT an xcodeproj). Layout:
  ```
  Package.swift          (swift-tools-version 5.9, platforms [.macOS(.v13)], executable target "HermesTray")
  Sources/HermesTray/HermesTrayApp.swift   (@main App, MenuBarExtra scene)
  Sources/HermesTray/APIClient.swift       (URLSession async client: bootstrap token, status(), sessions(), systemStats(); endpoint enum; errors)
  Sources/HermesTray/Models.swift          (Codable structs matching JSON above, all optional fields)
  Sources/HermesTray/Store.swift           (@MainActor ObservableObject: poll loops, published state: iconBusy, connectionState, sessions, stats, errorMessage)
  Sources/HermesTray/TokenStore.swift      (Keychain via Security framework; fallback to UserDefaults if keychain write fails)
  Sources/HermesTray/Views.swift           (MenuBarExtra content, SessionRowView, StatsFooterView, SettingsView as .settings scene? NO — settings as a small popover/window via Settings scene is fine on macOS 13; simpler: SettingsView as a window opened by menu command "Settings…")
  README.md
  .gitignore
  support/hermes-tunnel.plist   (launchd LaunchAgent sample for the ssh tunnel; LABEL com.jaide.hermes-tunnel; note user must edit the ssh command)
  ```
- macOS 13.0+ (MenuBarExtra requires it). Swift concurrency: async/await + `Timer`/`Task` polling; mark store @MainActor. No third-party dependencies, no network libs — URLSession only. AppKit only via implicit SwiftUI needs.
- Elapsed ticking: store `now` published every 1s from a Timer in the Store; rows compute elapsed from that.
- Robustness: if a poll fails (connection refused etc.) keep last good data, set connectionState = .unreachable(error), show it in header; never crash; auto-retry next tick. Handle both JSON field types where server may send int or null (use Int? and Double? with `decodeIfPresent`).
- The app must build clean with `swift build` on macOS 13+ with zero warnings you can avoid, and run with `swift run` (menu bar item appears; a Dock icon appearing is acceptable for v1 — do NOT add LSUIElement hacks in SwiftPM).
- README.md: prerequisites (macOS 13+, Xcode 15+ OR full Xcode Command Line Tools; `swift --version` check), build & run steps (`git clone … && cd hermes-tray && swift run` OR `open Package.swift` in Xcode → Run), the SSH tunnel command to set up first, how to set base URL if not default, troubleshooting (401 → token auto-refresh note; tunnel down → "Unreachable"), and how to install the launchd tunnel agent from support/hermes-tunnel.plist.

## Style
Clean, idiomatic Swift, modern concurrency, small types, comments only where non-obvious (e.g. the token regex bootstrap). Enum-driven UI states. Prefer `FormatStyle`/`Text` formatting over manual string math where natural.
