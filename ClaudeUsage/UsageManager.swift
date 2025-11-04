import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "com.andrewfinke.Usage", category: "UsageManager")

// MARK: - Usage State for Display

struct UsageDataPoint {
    let timestamp: Date
    let percent: Int
}

struct UsageState: Identifiable {
    let id: String // Account ID (orgId)
    var percent: Int = 0
    var timeUntilReset: String = "..."
    var status: Status = .loading
    var error: String?
    var timeToFull: String? // ETA to 100%
    var history: [UsageDataPoint] = [] // Last 5 minutes of data

    enum Status {
        case loading
        case success
        case error
    }
}

// MARK: - Usage Manager

@MainActor
@Observable
class UsageManager {
    var usageStates: [UsageState] = []
    private var clients: [String: ClaudeUsageClient] = [:]
    private var refreshTimers: [String: Timer] = [:]
    private var accountManager: AccountManager?

    // Constants for tracking
    let refreshInterval: TimeInterval = 15 // 15 seconds
    let historyDuration: TimeInterval = 300 // 5 minutes

    func setAccountManager(_ manager: AccountManager) {
        self.accountManager = manager
    }

    private func formatAccountId(_ accountId: String) -> String {
        let shortId = String(accountId.prefix(8)) + "..."
        if let account = accountManager?.accounts.first(where: { $0.id == accountId }),
           let name = account.name {
            return "\(shortId) (\(name))"
        }
        return shortId
    }

    func setupForAccount(_ account: Account) {
        let client = ClaudeUsageClient(orgId: account.id, sessionKey: account.sessionKey)
        clients[account.id] = client

        // Create initial state
        if usageStates.firstIndex(where: { $0.id == account.id }) == nil {
            usageStates.append(UsageState(id: account.id))
        }

        // Start refresh cycle
        startRefreshTimer(for: account.id)
        updateUsage(for: account.id)
    }

    func removeAccount(_ accountId: String) {
        refreshTimers[accountId]?.invalidate()
        refreshTimers.removeValue(forKey: accountId)
        clients.removeValue(forKey: accountId)
        usageStates.removeAll { $0.id == accountId }
    }

    private func startRefreshTimer(for accountId: String) {
        refreshTimers[accountId]?.invalidate()

        refreshTimers[accountId] = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateUsage(for: accountId)
            }
        }
    }

    func updateUsage(for accountId: String) {
        guard let client = clients[accountId] else { return }

        Task {
            do {
                let usage = try await client.fetchUsage()
                await MainActor.run {
                    self.updateState(for: accountId, usage: usage)
                }
            } catch {
                await MainActor.run {
                    self.updateState(for: accountId, error: error.localizedDescription)
                }
            }
        }
    }

    private func updateState(for accountId: String, usage: UsageData) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }) else { return }

        guard let period = usage.five_hour else {
            usageStates[index].status = .error
            usageStates[index].error = "No usage data"
            return
        }

        let percent = Int(period.utilization)
        let timeLeft: String
        if let resetsAtString = period.resets_at {
            let resetDate = parseDate(resetsAtString)
            timeLeft = timeUntilReset(resetDate)
        } else {
            timeLeft = "N/A"
        }

        // Log the fetched data
        logger.log("Account \(self.formatAccountId(accountId)): usage=\(percent)%, resets=\(timeLeft)")

        // Add data point to history
        let dataPoint = UsageDataPoint(timestamp: Date(), percent: percent)
        usageStates[index].history.append(dataPoint)

        // Keep only last 5 minutes of data
        let cutoffTime = Date().addingTimeInterval(-historyDuration)
        usageStates[index].history.removeAll { $0.timestamp < cutoffTime }

        // Calculate time to 100%
        let timeToFull = calculateTimeToFull(for: &usageStates[index])
        if let timeToFull = timeToFull {
            logger.log("Account \(self.formatAccountId(accountId)): estimated time to full=\(timeToFull)")
        }

        usageStates[index].percent = percent
        usageStates[index].timeUntilReset = timeLeft
        usageStates[index].timeToFull = timeToFull
        usageStates[index].status = .success
        usageStates[index].error = nil
    }

    private func updateState(for accountId: String, error: String) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }) else { return }
        logger.error("Account \(self.formatAccountId(accountId)): error=\(error)")
        usageStates[index].status = .error
        usageStates[index].error = error
    }

    private func parseDate(_ dateString: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Fallback: try without fractional seconds
        let fallbackFormatter = ISO8601DateFormatter()
        return fallbackFormatter.date(from: dateString) ?? Date()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0m" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll

        return formatter.string(from: seconds) ?? "0m"
    }

    private func timeUntilReset(_ resetDate: Date) -> String {
        let now = Date()
        let timeInterval = resetDate.timeIntervalSince(now)
        return formatDuration(timeInterval)
    }

    private func calculateTimeToFull(for state: inout UsageState) -> String? {
        let accountId = state.id
        let percent = state.percent
        let historyCount = state.history.count

        guard percent < 100 else {
            // Don't log when already at 100% - this is expected
            return nil
        }

        guard historyCount >= 2 else {
            logger.log("Account \(self.formatAccountId(accountId)): insufficient history for time-to-full calculation (historyCount=\(historyCount))")
            return nil
        }

        // Get data from the last 5 minutes
        let now = Date()
        let oldestTime = now.addingTimeInterval(-historyDuration)
        let relevantHistory = state.history.filter { $0.timestamp >= oldestTime }

        guard relevantHistory.count >= 2 else {
            logger.log("Account \(self.formatAccountId(accountId)): filtered history too small (relevantHistoryCount=\(relevantHistory.count))")
            return nil
        }

        let firstPoint = relevantHistory.first!
        let lastPoint = relevantHistory.last!
        let timeDiff = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)

        guard timeDiff > 0 else { return nil }

        let percentDiff = lastPoint.percent - firstPoint.percent
        guard percentDiff > 0 else {
            logger.log("Account \(self.formatAccountId(accountId)): usage not increasing (percentDiff=\(percentDiff))")
            return nil // Not increasing
        }

        let percentPerSecond = Double(percentDiff) / timeDiff
        let percentRemaining = Double(100 - percent)
        let secondsToFull = percentRemaining / percentPerSecond

        logger.log("Account \(self.formatAccountId(accountId)): time-to-full calculation: percentDiff=\(percentDiff), timeDiff=\(String(format: "%.1f", timeDiff))s, velocity=\(String(format: "%.3f", percentPerSecond))%/s, secondsToFull=\(String(format: "%.0f", secondsToFull))s")

        guard secondsToFull > 0 && secondsToFull < Double(Int.max) else { return nil }

        return formatDuration(secondsToFull)
    }

    func menuBarTitle() -> String {
        if usageStates.isEmpty {
            return "Setup"
        }

        // Sort states alphabetically by account name to match menu ordering
        let sortedStates = usageStates.sorted { state1, state2 in
            let account1 = accountManager?.accounts.first(where: { $0.id == state1.id })
            let account2 = accountManager?.accounts.first(where: { $0.id == state2.id })

            let name1 = account1?.name ?? state1.id
            let name2 = account2?.name ?? state2.id

            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }

        let displays = sortedStates.map { state -> String in
            switch state.status {
            case .loading:
                return "..."
            case .success:
                return "\(state.percent)%"
            case .error:
                return "ERROR"
            }
        }
        return displays.joined(separator: " | ")
    }
}
