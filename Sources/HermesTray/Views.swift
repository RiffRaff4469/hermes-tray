import AppKit
import ServiceManagement
import SwiftUI

struct TrayContentView: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @State private var restartPending = false
    @State private var restartError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !store.liveJobs.isEmpty {
                        jobSection
                        Divider()
                    }
                    sessionSection("ACTIVE", sessions: store.activeSessions, empty: "No active sessions")
                    Divider()
                    sessionSection("RECENT", sessions: store.recentSessions, empty: "No recent sessions")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // MenuBarExtra windows auto-size and collapse greedy ScrollViews to
            // zero height — give the list a fixed frame so rows always render.
            .frame(height: 360)
            Divider()
            StatsFooterView(stats: store.stats)
            Divider()
            HStack {
                Button("Open Dashboard") { openURL(store.dashboardURL) }
                Spacer()
                Button("Settings…") { openWindow(id: "settings") }
                Spacer(minLength: 4)
                if Bundle.main.bundleIdentifier != nil {
                    Button("Restart…", action: restart)
                        .disabled(restartPending)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
            if let restartError {
                Text(restartError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear { store.start() }
    }

    private func restart() {
        guard Bundle.main.bundleIdentifier != nil, !restartPending else { return }
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Without -n, open would only activate this still-running instance.
        launcher.arguments = ["-n", Bundle.main.bundleURL.path]
        restartError = nil
        do {
            try launcher.run()
            restartPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !launcher.isRunning && launcher.terminationStatus != 0 {
                    restartPending = false
                    restartError = "Could not reopen HermesTray. Please relaunch it from /Applications."
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        } catch {
            restartError = "Could not restart: \(error.localizedDescription)"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("HermesTray").font(.headline)
                Spacer()
                switch store.connectionState {
                case .connecting: Label("Connecting…", systemImage: "circle.dotted").foregroundStyle(.secondary)
                case .connected: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .unreachable: Label("Unreachable", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                }
            }
            Text("\(store.stats?.hostname ?? "Unknown host") · Hermes \(store.status?.version ?? "—")")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(store.liveJobs.count) jobs · \(store.sessions.count) sessions · \(store.activeSessions.count) active")
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            if case .unreachable(let error) = store.connectionState {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var jobSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JOBS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(store.liveJobs, id: \.id) { job in
                JobRowView(job: job, now: store.now)
            }
        }
    }

    private func sessionSection(_ title: String, sessions: [Session], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if sessions.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.secondary).padding(.vertical, 5)
            }
            // Index identity also accommodates records whose API id is null or duplicated.
            ForEach(Array(sessions.enumerated()), id: \.offset) { entry in
                Button { openURL(store.dashboardURL) } label: {
                    SessionRowView(session: entry.element, now: store.now)
                }
                .buttonStyle(.plain)
                .help("Open the Hermes dashboard")
            }
        }
    }
}

struct JobRowView: View {
    let job: TrayJob
    let now: Date

    private var subtitle: String {
        [job.stage, job.detail].compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.joined(separator: " · ")
    }

    private var elapsed: String {
        if job.isRunning { return DisplayFormat.jobElapsed(start: job.started_at, now: now) }
        // The API has no ended_at; use the final heartbeat as the duration endpoint.
        guard let end = job.heartbeat_at else { return "—" }
        return DisplayFormat.jobElapsed(start: job.started_at, now: Date(timeIntervalSince1970: end))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(job.name).font(.callout.weight(.medium)).lineLimit(2)
                Spacer(minLength: 8)
                statusGlyph
                Text(elapsed).monospacedDigit().font(.caption)
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private var statusGlyph: some View {
        if job.isStale {
            Image(systemName: "circle.fill").foregroundStyle(.orange)
                .help("no signal \(DisplayFormat.heartbeatAge(job.heartbeat_age))")
                .accessibilityLabel("no signal \(DisplayFormat.heartbeatAge(job.heartbeat_age))")
        } else if job.isRunning && job.alive == true {
            if #available(macOS 14, *) {
                Image(systemName: "circle.fill").foregroundStyle(.green)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityLabel("Running")
            } else {
                Image(systemName: "circle.fill").foregroundStyle(.green)
                    .accessibilityLabel("Running")
            }
        } else if job.isDone {
            Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel("Done")
        } else if job.isFailed {
            Image(systemName: "xmark").foregroundStyle(.red).accessibilityLabel("Failed")
        } else {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .help("Job status or liveness is unknown")
                .accessibilityLabel("Job status or liveness is unknown")
        }
    }
}

struct SessionRowView: View {
    let session: Session
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(session.rowTitle).font(.callout.weight(.medium)).lineLimit(2)
                Spacer(minLength: 8)
                if session.is_active != true && session.hasSuccessfulEnd {
                    Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel("Successful")
                }
                Text(DisplayFormat.elapsed(session, now: now)).monospacedDigit().font(.caption)
            }
            HStack(spacing: 8) {
                Text(session.sourceBadge.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Label(session.tool_call_count.map { String($0) } ?? "—", systemImage: "wrench.and.screwdriver")
                Text(session.model ?? "Unknown model").lineLimit(1).truncationMode(.middle)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}

struct StatsFooterView: View {
    let stats: SystemStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CPU \(DisplayFormat.decimal(stats?.cpu_percent, digits: 0))%")
                Spacer()
                Text("Uptime \(DisplayFormat.uptime(stats?.uptime_seconds))")
            }
            Text("RAM \(DisplayFormat.gigabytes(stats?.memory?.used)) / \(DisplayFormat.gigabytes(stats?.memory?.total)) GB (\(DisplayFormat.decimal(stats?.memory?.percent, digits: 0))%)")
            Text("Disk \(DisplayFormat.gigabytes(stats?.disk?.free)) GB free")
        }
        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var draft = ""
    @State private var validationError: String?
    @State private var saved = false
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dashboard connection").font(.headline)
            TextField("Base URL", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
                .onChange(of: draft) { _ in saved = false; validationError = nil }
            Text("Default: \(Store.defaultBaseURL) — connect to Tailscale first.")
                .font(.caption).foregroundStyle(.secondary)
            if Bundle.main.bundleIdentifier != nil {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                Text("Relaunch the app from /Applications once for this to take effect.")
                    .font(.caption).foregroundStyle(.secondary)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            if let validationError {
                Text(validationError).foregroundStyle(.red).font(.caption)
            }
            HStack {
                if saved { Text("Saved").foregroundStyle(.secondary).font(.caption) }
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
        .onAppear {
            draft = store.baseURL
            if Bundle.main.bundleIdentifier != nil {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let previous = launchAtLogin
        launchAtLogin = enabled
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && SMAppService.mainApp.status == .requiresApproval {
                loginError = "Allow HermesTray in System Settings → General → Login Items."
            }
        } catch {
            // A custom binding keeps this rollback from invoking the service again.
            launchAtLogin = previous
            loginError = "Could not update launch at login: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try store.saveBaseURL(draft)
            validationError = nil
            saved = true
        } catch { validationError = error.localizedDescription }
    }
}
