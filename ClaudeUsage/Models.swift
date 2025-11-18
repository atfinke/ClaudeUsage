import Foundation

// MARK: - API Models

struct UsageData: Codable, Sendable {
    struct Period: Codable, Sendable {
        let utilization: Double
        let resets_at: String?
    }

    let five_hour: Period?
}
