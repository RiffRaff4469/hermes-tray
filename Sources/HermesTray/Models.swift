import Foundation

struct AgentStatus: Codable, Sendable {
    var version: String?
    var gateway_running: Bool?
    var gateway_state: String?
    var gateway_platforms: [String: PlatformState]?
    var active_agents: Int?
    var gateway_busy: Bool?
    var active_sessions: Int?
    var components: [String: ComponentState]?
    var overall: String?
    var profiles: [String]?

    var isBusy: Bool { gateway_busy == true || (active_agents ?? 0) > 0 }
}

struct PlatformState: Codable, Sendable { var state: String? }
struct ComponentState: Codable, Sendable { var status: String? }
struct SessionsResponse: Codable, Sendable { var sessions: [Session]? }
struct TrayJobsResponse: Codable, Sendable { var jobs: [TrayJob]? }

struct TrayJob: Codable, Sendable {
    var id: String
    var name: String
    var stage: String?
    var detail: String?
    var status: String
    var started_at: Double
    var heartbeat_at: Double?
    var alive: Bool?
    var heartbeat_age: Double?

    var isRunning: Bool { status == "running" }
    var isDone: Bool { status == "done" }
    var isFailed: Bool { status == "failed" }
    var isStale: Bool { isRunning && alive == false }
}

struct Session: Codable, Sendable {
    var id: String?
    var source: String?
    var chat_id: StringOrNumber?
    var thread_id: StringOrNumber?
    var display_name: String?
    var model: String?
    var started_at: Double?
    var ended_at: Double?
    var end_reason: String?
    var message_count: Int?
    var tool_call_count: Int?
    var input_tokens: Int?
    var output_tokens: Int?
    var cache_read_tokens: Int?
    var estimated_cost_usd: Double?
    var title: String?
    var title_source: String?
    var last_activity_at: Double?
    var last_activity_description: String?
    var unread: Bool?
    var is_active: Bool?
    var preview: String?
    var profile: String?

    var hasSuccessfulEnd: Bool {
        guard let reason = end_reason?.lowercased() else { return false }
        return ["cron_complete", "complete", "completed", "success", "stop", "normal"].contains(reason)
    }

    var rowTitle: String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Untitled session"
        }
        return title
    }

    var sourceBadge: String {
        guard let source, ["cron", "telegram", "cli", "web"].contains(source) else { return "other" }
        return source
    }
}

// These identifiers may be either strings or numeric IDs across gateways.
enum StringOrNumber: Codable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else { self = .number(try container.decode(Double.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        }
    }
}

struct SystemStats: Codable, Sendable {
    var os: String?
    var hostname: String?
    var cpu_count: Int?
    var memory: MemoryStats?
    var disk: DiskStats?
    var cpu_percent: Double?
    var uptime_seconds: Double?
    var process: ProcessStats?
    var psutil: Bool?
}

struct MemoryStats: Codable, Sendable {
    var total: Double?
    var available: Double?
    var used: Double?
    var percent: Double?
}

struct DiskStats: Codable, Sendable {
    var total: Double?
    var used: Double?
    var free: Double?
    var percent: Double?
}

struct ProcessStats: Codable, Sendable {
    var pid: Int?
    var rss: Double?
    var num_threads: Int?
}
