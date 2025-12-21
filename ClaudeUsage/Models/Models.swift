import Foundation

// MARK: - API Models

struct UsageData: Codable, Sendable {
    struct Period: Codable, Sendable {
        let utilization: Double
        let resetsAt: String?
    }

    let fiveHour: Period?
}
