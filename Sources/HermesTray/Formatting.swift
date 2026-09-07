import Foundation

enum DisplayFormat {
    static func elapsed(_ session: Session, now: Date) -> String {
        guard let start = session.started_at else { return "—" }
        let end: Double
        if session.is_active == true { end = now.timeIntervalSince1970 }
        else if let ended = session.ended_at { end = ended }
        else { return "—" }
        guard start.isFinite, end.isFinite else { return "—" }
        let seconds = Int(min(max(0, end - start), Double(Int.max / 2)))
        if seconds >= 3600 {
            return String(format: "%02ld:%02ld:%02ld", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02ld:%02ld", seconds / 60, seconds % 60)
    }

    static func decimal(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func gigabytes(_ bytes: Double?) -> String {
        decimal(bytes.map { $0 / 1_073_741_824 })
    }

    static func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let minutes = Int(min(seconds / 60, Double(Int.max / 2)))
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
