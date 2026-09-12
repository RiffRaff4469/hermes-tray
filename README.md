# HermesTray

A macOS menu bar monitor for your own self-hosted [Hermes](https://hermes-agent.nousresearch.com/docs)
agent. It polls your backend and shows, at a glance, whether the agent is busy,
what it is working on, and how the host it runs on is doing.

- Menu bar icon (`waveform.path.ecg`) with an orange dot when the agent is busy or a job is running.
- Header: connection state, host, Hermes version, counts.
- **JOBS** — named long-running jobs with a liveness heartbeat (only when your backend serves the jobs endpoint).
- **ACTIVE** / **RECENT** — live sessions with elapsed time, tool-call count and model; finished sessions with a ✓ for clean ends.
- System stats footer: CPU, RAM, disk free, uptime.
- Footer: Open Dashboard, Settings…, Restart… (bundled builds only) and Quit.

## Requirements

- macOS 13.0 or later (SwiftUI `MenuBarExtra`).
- Xcode 15 or later, or the full Xcode Command Line Tools (`xcode-select --install`, then `swift --version`).
- No third-party dependencies — SwiftPM, SwiftUI, Foundation, Security only.

## Status — read this before you build

Verified on 2026-09-12 against a stock Hermes **0.20.0** backend (release build
2026-08-03) at a VPN-reachable address. HermesTray was written against an older
backend, and one part of it no longer matches the backend it talks to.

**What works.** `GET /api/status` is on the backend's credential-free allowlist,
so the icon's busy badge, the agent version in the header, and Open Dashboard /
Quit / Restart all work against a current backend. (The hostname shown next to
the version comes from the gated stats endpoint, so it reads `Unknown host`.)

**What is stale — the session-token bootstrap.** The ACTIVE, RECENT and stats
sections need a session token, and the app obtains one by scraping
`window.__HERMES_SESSION_TOKEN__` out of the HTML of `GET /`. A current backend
does not serve that token: `GET /` answers `302` to `/login?next=/`, and the
sign-in page contains no session token at all. Those sections therefore stay
empty, and because the app re-scrapes on every 401 they keep failing — the header
shows **Unreachable** with `The dashboard HTML did not contain a session token.`
even though `/api/status` itself is answering fine.

The real auth on a current backend is a browser-style sign-in, and both available
forms need a flow HermesTray does not implement:

| Endpoint | Credentials required |
| --- | --- |
| `GET /api/status` | none — on the backend's credential-free allowlist |
| `GET /api/sessions` | session cookie, or `Authorization: Bearer <session token>` |
| `GET /api/system/stats` | session cookie, or `Authorization: Bearer <session token>` |
| `GET /api/tray/jobs` | not a stock Hermes route — see below |

- Sign-in form: `GET /login` (fields `username`, `password`, `next`) sets a session cookie. `GET /` redirects there.
- Bearer: the backend also accepts the session token as `Authorization: Bearer …` (its native-app path), refreshed via `/auth/native/refresh`.
- Unauthenticated gated requests answer `401` with `{"error":"unauthenticated","reason":"no_cookie","login_url":"/login"}`; a rejected token answers with `{"reason":"invalid_or_expired_session"}`.

**What is stale — the JOBS section.** `/api/tray/jobs` is not a Hermes route. The
app expects a small companion endpoint in front of the dashboard that returns
`{"jobs":[{...,"alive":true,"heartbeat_age":4.2}]}`. Pointed straight at a stock
backend it gets `401 login_url:/login`, so the JOBS section stays hidden.

Neither stale path is fixed here: matching the new auth model is a separate piece
of work. Until then, treat this as a monitor for the agent's status and busy
state, not for session or host detail.

## Build and run

```sh
git clone https://github.com/RiffRaff4469/hermes-tray.git
cd hermes-tray
swift run
```

The menu bar icon appears; there is no Dock icon in bundled builds. You can also
`open Package.swift` in Xcode and press Run.

## Run as a real app

```sh
./scripts/make_app.sh          # builds, assembles and ad-hoc signs HermesTray.app
cp -R HermesTray.app /Applications/
open /Applications/HermesTray.app
```

Then Settings… → **Launch at login** if you want it to start automatically.
Restart… and Quit live in the dropdown footer. Stop any Xcode-launched instance
first (`pkill -f HermesTray`).

`SMAppService` (launch at login) keys off the bundle identifier
`dev.hermes-tray.HermesTray`, so if you change that identifier, or upgrade from a
build that used a different one, re-toggle the setting — otherwise an old login
item is left behind in System Settings → General → Login Items.

## Point it at your backend

Settings… → **Base URL** → your own dashboard address → Save.

- The app ships **no real address**. The field starts pre-filled with the
  placeholder `http://your-hermes-host:9119`, and until you replace it and save,
  the app polls that placeholder host and reports Unreachable.
- Accepted: `http` or `https`, a host (and optional port), no credentials, query or fragment.
- The Mac must be able to reach the host: same LAN, a VPN such as WireGuard or
  Tailscale, or an SSH tunnel. `http://127.0.0.1:9119` works if you forward the port to your own machine.

**Cleartext HTTP and App Transport Security.** `support/Info.plist` sets
`NSAppTransportSecurity → NSAllowsArbitraryLoads = true`. A bundled app otherwise
blocks plain-HTTP requests to anything that is not loopback, which would break a
dashboard served over `http://` on a LAN or VPN address — that is why the key is
there. What it means: inside this app, ATS is off for **every** host, so the app
would also accept cleartext HTTP elsewhere if it ever talked elsewhere. It does
not: every request goes to the single base URL you configure. Serve your backend
over `https` if you can, and drop the ATS key entirely if you only ever use
loopback.

## Data — what leaves the machine

One line each:

- **Requests:** `GET /api/status` and `/api/system/stats` every 4s, `/api/sessions` every 6s, `/api/tray/jobs` every 5s — all to the base URL you configure. No other host, no analytics, no update or phone-home requests.
- **Sent:** no request bodies, no query parameters. An `Authorization: Bearer <token>` header on `/api/sessions` and `/api/system/stats` when a token is stored. Nothing else.
- **Stored locally:** the base URL in `UserDefaults` (`HermesTray.baseURL`); the session token in the macOS Keychain (service `dev.hermes-tray.HermesTray.session-token`), falling back to `UserDefaults` — unencrypted — only if the Keychain write fails.
- **Received, then rendered locally and never uploaded:** agent status and version, session metadata (titles, models, tool and token counts, cost estimates) and host stats (CPU, RAM, disk, uptime).

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Unreachable, connection refused or timed out | Wrong base URL, backend not running, or the Mac cannot reach the host (LAN/VPN/tunnel). Check the URL in a browser on the Mac first. |
| `The dashboard HTML did not contain a session token.` | Expected on a current backend — see Status. Not a configuration problem. |
| `HTTP 401` from the jobs endpoint | The JOBS section needs a companion endpoint that serves `/api/tray/jobs`. |
| No Dock icon, no window | By design — `LSUIElement` is true; the app lives in the menu bar. |
| `swift: command not found` | Install Xcode 15+ or the full Command Line Tools, then `swift --version`. |
| Launch at login does nothing | Relaunch from `/Applications` once; the bundle must sit in a stable location, and you may need to approve it in System Settings → General → Login Items. |

## Repository layout

```
Package.swift                     SwiftPM manifest (macOS 13+, executable target)
Sources/HermesTray/
  HermesTrayApp.swift             @main app, MenuBarExtra + Settings window
  APIClient.swift                 URLSession client, token bootstrap, /api/* endpoints
  Models.swift                    Codable models for the API payloads
  Store.swift                     @MainActor polling store and UI state
  TokenStore.swift                Keychain storage with a UserDefaults fallback
  Views.swift                     menu bar content, rows, stats footer, settings
  Formatting.swift                display formatting helpers
support/Info.plist                bundle metadata + the ATS key explained above
support/hermes-tunnel.plist       legacy, unreferenced sample SSH-tunnel LaunchAgent
support/icon/AppIcon.iconset/     icon source (converted to .icns by make_app.sh)
scripts/make_app.sh               build + assemble + ad-hoc sign the .app
```

`support/hermes-tunnel.plist` is not referenced by the app or this README; keep it
as a sample or delete it.

## Licence

MIT — see [LICENSE](LICENSE).
