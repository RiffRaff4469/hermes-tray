import Combine
import Foundation

enum ConnectionState {
    case connecting
    case connected
    case unreachable(String)
}

@MainActor
final class Store: ObservableObject {
    static let defaultBaseURL = "http://127.0.0.1:9119"
    @Published private(set) var baseURL: String
    @Published private(set) var iconBusy = false
    @Published private(set) var connectionState: ConnectionState = .connecting
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var jobs: [TrayJob] = []
    @Published private(set) var stats: SystemStats?
    @Published private(set) var status: AgentStatus?
    @Published private(set) var errorMessage: String?
    @Published private(set) var now = Date()

    private var client: APIClient
    private var pollTasks: [Task<Void, Never>] = []
    private var ticker: AnyCancellable?
    private var failures: [String: String] = [:]
    private var successes: Set<String> = []
    private var generation = UUID()

    var dashboardURL: URL {
        // baseURL is validated before storage and on startup.
        URL(string: baseURL) ?? URL(fileURLWithPath: "/")
    }

    var activeSessions: [Session] {
        sessions.filter { $0.is_active == true }
            .sorted { ($0.started_at ?? 0) > ($1.started_at ?? 0) }
    }

    var liveJobs: [TrayJob] {
        Array(jobs.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.started_at > $1.started_at
        }.prefix(12))
    }

    var anyJobRunning: Bool { jobs.contains { $0.isRunning } }

    var recentSessions: [Session] {
        Array(sessions.filter { $0.is_active != true }
            .sorted { ($0.ended_at ?? $0.last_activity_at ?? $0.started_at ?? 0)
                > ($1.ended_at ?? $1.last_activity_at ?? $1.started_at ?? 0) }.prefix(8))
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "HermesTray.baseURL") ?? Self.defaultBaseURL
        let url = (try? APIClient.validatedURL(saved))
            ?? URL(string: "http://127.0.0.1:9119/")!
        baseURL = url.absoluteString
        client = APIClient(baseURL: url)
    }

    func start() {
        guard pollTasks.isEmpty else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in self?.now = date }
        let current = generation
        for (endpoint, interval) in [("status", 4.0), ("stats", 4.0), ("sessions", 6.0), ("jobs", 5.0)] {
            pollTasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    let tick = Date()
                    await self?.poll(endpoint, generation: current)
                    guard !Task.isCancelled else { break }
                    let remaining = max(0.1, interval - Date().timeIntervalSince(tick))
                    do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                    catch { break }
                }
            })
        }
    }

    func saveBaseURL(_ input: String) throws {
        let url = try APIClient.validatedURL(input)
        guard url.absoluteString != baseURL else { return }
        pollTasks.forEach { $0.cancel() }
        pollTasks.removeAll()
        ticker = nil
        generation = UUID()
        baseURL = url.absoluteString
        UserDefaults.standard.set(baseURL, forKey: "HermesTray.baseURL")
        client = APIClient(baseURL: url)
        sessions = []
        jobs = []
        stats = nil
        status = nil
        iconBusy = false
        failures = [:]
        successes = []
        errorMessage = nil
        connectionState = .connecting
        start()
    }

    private func poll(_ endpoint: String, generation expected: UUID) async {
        let api = client
        do {
            switch endpoint {
            case "status":
                let value = try await api.status()
                guard expected == generation, !Task.isCancelled else { return }
                status = value
                iconBusy = value.isBusy
            case "stats":
                let value = try await api.systemStats()
                guard expected == generation, !Task.isCancelled else { return }
                stats = value
            case "jobs":
                let value = try await api.trayJobs()
                guard expected == generation, !Task.isCancelled else { return }
                jobs = value
            default:
                let value = try await api.sessions()
                guard expected == generation, !Task.isCancelled else { return }
                sessions = value
            }
            failures.removeValue(forKey: endpoint)
            successes.insert(endpoint)
        } catch {
            guard expected == generation, !Task.isCancelled else { return }
            failures[endpoint] = "\(endpoint): \(error.localizedDescription)"
        }
        errorMessage = failures.keys.sorted().compactMap { failures[$0] }.joined(separator: " · ")
        if failures.isEmpty { errorMessage = nil }
        // The relay's jobs endpoint does not determine dashboard connectivity.
        let dashboardEndpoints: Set<String> = ["status", "stats", "sessions"]
        let dashboardErrors = dashboardEndpoints.sorted().compactMap { failures[$0] }
        if dashboardErrors.isEmpty {
            connectionState = dashboardEndpoints.isSubset(of: successes) ? .connected : .connecting
        } else {
            connectionState = .unreachable(errorMessage ?? "Unknown error")
        }
    }
}
