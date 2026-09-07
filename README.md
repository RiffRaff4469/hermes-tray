# HermesTray

A macOS menu bar monitor for a remote Hermes agent. Requires macOS 13 or later
and Xcode 15+ or the full Xcode Command Line Tools with Swift 5.9+.
Check your installation with `swift --version`.

## Connect first

Enable the SSH server on the Windows machine running Hermes. From your Mac,
replace the destination below with your Windows SSH username and hostname:

```sh
ssh -N -L 9119:localhost:9119 WINDOWS_USER@WINDOWS_HOST
```

Keep this terminal open. Hermes must be listening on port 9119 on Windows.
Open `http://127.0.0.1:9119/` in a browser to confirm the dashboard is reachable.

## Build and run

From this project directory on your Mac:

```sh
swift build
swift run HermesTray
```

Alternatively, run `open Package.swift`, select the HermesTray executable in
Xcode, and choose Run. The pulse icon appears in the menu bar; an orange dot
means `gateway_busy` is true or `active_agents` is greater than zero. A Dock
icon is acceptable for this SwiftPM executable. Stop a terminal launch with
Control-C, or stop the executable in Xcode.

Click the pulse icon for active sessions, the eight most recent inactive
sessions, and system statistics. Session rows open the dashboard home.
Choose **Settings…**, enter the dashboard base URL, and click **Save** to
reconnect immediately. The URL persists between launches. HTTP and HTTPS
URLs, including a base path, are supported; credentials, queries, and fragments
are rejected. The default is `http://127.0.0.1:9119`.

Status and system statistics poll every four seconds; sessions poll every six.
Requests for a given endpoint never overlap. Slow requests delay the next poll.
Elapsed times refresh locally every second. Outages retain the last good data,
including the last busy state, and show endpoint errors in the header.

## Authentication and troubleshooting

- **Unreachable:** Check the tunnel, Windows SSH service, and Hermes dashboard.
  Polling retries automatically. Data remains visible but may be stale.
- **401:** The app extracts the token from the dashboard HTML and automatically
  refreshes it and retries once when a protected request returns HTTP 401.
  Persistent 401 errors indicate a server authentication or base URL problem.
- **Missing token:** Check that the URL points to the Hermes dashboard, whose
  HTML must contain `window.__HERMES_SESSION_TOKEN__`.
- Tokens are cached per base URL in Keychain. If a Keychain write fails, the
  token is stored in UserDefaults, which is not encrypted secret storage.
- Missing/null API values display as dashes or descriptive placeholders.
  Unknown session sources display as `other`. A missing title displays as
  “Untitled session”. Missing end times display an unknown elapsed duration.
- **Build tools:** Ensure `swift --version` reports Swift 5.9+ and your selected
  developer tools include the macOS SDK. This project cannot build on Windows.

## Start the tunnel at login

Edit `support/hermes-tunnel.plist`, replacing `WINDOWS_USER@WINDOWS_HOST` in
the SSH argument list. Configure SSH keys (or an SSH config Host alias) so the
connection works without interaction. Connect manually once to verify the
host key and authentication before installing the agent. Stop the manual
tunnel before starting launchd, so the port is available.

On the Mac:

```sh
mkdir -p ~/Library/LaunchAgents
cp support/hermes-tunnel.plist ~/Library/LaunchAgents/com.jaide.hermes-tunnel.plist
plutil -lint ~/Library/LaunchAgents/com.jaide.hermes-tunnel.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jaide.hermes-tunnel.plist
launchctl kickstart -k gui/$(id -u)/com.jaide.hermes-tunnel
```

The sample uses SSH keepalives and launchd restart throttling to reconnect.
Inspect it with `launchctl print gui/$(id -u)/com.jaide.hermes-tunnel`.
To remove it:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.jaide.hermes-tunnel.plist
rm ~/Library/LaunchAgents/com.jaide.hermes-tunnel.plist
```

## Interpretation and validation

The API does not enumerate successful end reasons. The checkmark uses the
explicit allowlist `cron_complete`, `complete`, `completed`, `success`, `stop`,
and `normal` (case-insensitive). Unknown reasons get no checkmark. Active means
`is_active == true`; other records appear under Recent, sorted by end time,
then last activity/start time when unavailable. Memory and disk use binary
gigabytes, labeled GB to match the brief. Connection becomes Connected after
all three endpoints succeed; any outstanding endpoint failure shows Unreachable.

Written and statically reviewed on Windows without a macOS SDK; compilation
and live UI/network validation must be performed on a Mac. Verify launch,
Settings, session links, busy/idle display, a tunnel outage/recovery, and token
refresh against your Hermes instance after building.
