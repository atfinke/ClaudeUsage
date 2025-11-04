import Foundation

// MARK: - API Models

struct UsageData: Codable {
    struct Period: Codable {
        let utilization: Double
        let resets_at: String?
    }

    let five_hour: Period?
}
