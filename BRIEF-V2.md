# HermesTray v2 — add a JOBS section (named long-running jobs)

You previously built HermesTray (macOS 13+ SwiftPM executable, SwiftUI MenuBarExtra) in this directory: `C:/Users/jaide/projects/hermes-tray/`. All files currently compile and run (verified on the user's Mac). Your job now: add a "JOBS" section showing NAMED long-running jobs (e.g. "ROM build — mka bacon — alive 34m"), NOT raw processes.

Read the existing sources first (Package.swift, HermesTrayApp.swift, APIClient.swift, Models.swift, Store.swift, Views.swift, TokenStore.swift, Formatting.swift) and match their style exactly.

## New backend endpoint (already live, do not build it)
`GET <baseURL>/api/tray/jobs` — no auth, served by the Tailscale relay (path never reaches the dashboard). Real response (trimmed):

```json
{"jobs": [{
  "id": "hermes-tray-v2",
  "name": "HermesTray v2 (Codex)",
  "stage": "writing JOBS section UI",
  "detail": "codex dispatched",
  "status": "running",
  "started_at": 1788748671.57,
  "heartbeat_at": 1788748671.57,
  "alive": true,
  "heartbeat_age": 4.2
}]}
```

Fields: `status` ∈ running|done|failed. `alive` is server-computed: status==running AND heartbeat within last 120s. `heartbeat_age` = seconds since last heartbeat. `started_at`/`heartbeat_at` are unix epoch doubles. Jobs array sorted: running first, then by started_at desc. When nothing is registered the response is `{"jobs": []}`.

## Changes

1. **Models.swift** — add `struct TrayJob: Codable, Sendable` mirroring the JSON above (all fields optional except id/name/status/started_at). Add `struct TrayJobsResponse: Codable, Sendable { var jobs: [TrayJob]? }`. Add computed helpers: `isRunning` (status=="running"), `isDone`, `isFailed`, `isStale` (running && alive==false).

2. **APIClient.swift** — add `func trayJobs() async throws -> [TrayJob]` hitting the new endpoint (unauthenticated, like `status()`). Add `case trayJobs = "api/tray/jobs"` to the Endpoint enum.

3. **Store.swift** — add `@Published private(set) var jobs: [TrayJob] = []`. In `start()`, add a 4th poll loop `("jobs", 5.0)` using the same pattern (generation guard, per-endpoint failure bookkeeping so connectionState logic is unaffected — jobs failures should NOT flip overall state to unreachable if the other three succeed; follow the existing failures/successes mechanics, and if that is awkward, treat jobs like status/stats/sessions with identical semantics). Add `var liveJobs: [TrayJob]` (running first: running jobs sorted by started_at desc, then done/failed, cap at 12) and `var anyJobRunning: Bool`. In `saveBaseURL(_:)` reset `jobs = []` alongside the other resets. Add `liveJobs`/`anyJobRunning` exposure for the label badge.

4. **HermesTrayApp.swift** — when `store.iconBusy || store.anyJobRunning`, show the orange badge dot. (Busy icon semantics unchanged otherwise.)

5. **Views.swift** — in `TrayContentView`, add a JOBS section ABOVE the ACTIVE section, only when `!store.liveJobs.isEmpty`: header "JOBS" (same .caption style) then a `JobRowView` per job inside the existing ScrollView. JobRowView shows:
   - name (`.callout.weight(.medium)`, lineLimit 2)
   - second line: stage · detail (both optional; omit empty) in `.caption` secondary
   - trailing: elapsed since `started_at` using the existing 1s `store.now` ticker (reuse `DisplayFormat.elapsed`-style formatting — add a `DisplayFormat.jobElapsed(start:now:)` helper in Formatting.swift returning hh:mm:ss or mm:ss like the session one; for done/failed show total duration)
   - status glyph: running+alive → pulsing green dot (`Image(systemName: "circle.fill").foregroundStyle(.green)` — pulse via `.symbolEffect(.pulse, options: .repeating)` guarded `if #available(macOS 14, *)`; macOS 13 fallback = static green dot); running+stale → orange dot with "no signal Xm" (heartbeat_age) tooltip/text; done → green checkmark (like sessions); failed → red xmark.
   - rows are NOT buttons (no navigation target); style container like SessionRowView (.padding(8), background rounded rect).
   The section header/empty handling mirrors `sessionSection`. Keep frame width 420 and maxHeight behavior; the menu may get taller — fine.

6. **Formatting.swift** — add the job elapsed + a `DisplayFormat.heartbeatAge(_ seconds: Double?) -> String` ("now", "1m", "12m") helper.

7. **README.md** — add a short "Jobs" paragraph: what the section shows, that jobs are registered by agents/scripts via `hermes-job.py` on the PC, heartbeat = 120s liveness window, staleness meaning.

## Constraints
- macOS 13+ (Swift 5.9), zero third-party dependencies, pure SwiftUI/Foundation.
- This is a Windows host with no macOS SDK: self-review hard for compile correctness, imports, missing `#available` guards, and exact JSON field names.
- Do NOT touch TokenStore.swift or the polling intervals of existing endpoints. Do NOT run git.
- Keep files < 400 lines. Print a summary of every file changed and any ambiguity resolved.
