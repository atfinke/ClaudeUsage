import Foundation
import os
import UserNotifications

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
    var resetDate: Date? // When the usage period resets
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
    private var previousUsagePercent: [String: Int] = [:] // Track previous usage to detect resets

    // Constants for tracking
    let refreshInterval: TimeInterval = 30 // 30 seconds
    let historyDuration: TimeInterval = 300 // 5 minutes
    let lowActivityThreshold: TimeInterval = 120 // 2 minutes - threshold for refresh frequency

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

    private func sendResetNotification(for accountId: String) {
        let content = UNMutableNotificationContent()

        // Get account name if available
        let accountName = accountManager?.accounts.first(where: { $0.id == accountId })?.name ?? "Account"

        content.title = "Claude Usage Reset"
        content.body = "\(accountName) usage has reset to 0%"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage-reset-\(accountId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to send notification: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.log("Sent reset notification for account \(self.formatAccountId(accountId), privacy: .public)")
            }
        }
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
        previousUsagePercent.removeValue(forKey: accountId)
        usageStates.removeAll { $0.id == accountId }
    }

    private func startRefreshTimer(for accountId: String) {
        refreshTimers[accountId]?.invalidate()

        let interval = refreshInterval(for: accountId)
        refreshTimers[accountId] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateUsage(for: accountId)
            }
        }
    }

    private func refreshInterval(for accountId: String) -> TimeInterval {
        guard let state = usageStates.first(where: { $0.id == accountId }),
              let resetDate = state.resetDate else {
            return refreshInterval // Default to 30 seconds if no reset date available
        }

        let timeRemaining = resetDate.timeIntervalSince(Date())
        if timeRemaining > lowActivityThreshold {
            return 60 // 1 minute when > 2 minutes remaining (less frequent when plenty of time)
        } else {
            return refreshInterval // 30 seconds otherwise
        }
    }

    func updateUsage(for accountId: String) {
        guard let client = clients[accountId] else { return }

        // Check if we're in low activity mode (>20 min remaining)
        if shouldSkipNetworkRequest(for: accountId) {
            // Just update the timer display without making a network request
            Task { @MainActor in
                self.updateTimerOnly(for: accountId)
            }
            return
        }

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

    private func shouldSkipNetworkRequest(for accountId: String) -> Bool {
        guard let state = usageStates.first(where: { $0.id == accountId }) else {
            return false // Default to making requests if no state available
        }

        // Don't skip if timer has reached 0 (period has reset)
        guard let resetDate = state.resetDate else {
            return false
        }

        let timeRemaining = resetDate.timeIntervalSince(Date())
        if timeRemaining <= 0 {
            return false // Period has reset, need to fetch new data
        }

        // Skip network requests if usage is at 100% (no need for frequent updates)
        return state.percent >= 100
    }

    private func updateTimerOnly(for accountId: String) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }),
              let resetDate = usageStates[index].resetDate else { return }

        let timeLeft = timeUntilReset(resetDate)
        usageStates[index].timeUntilReset = timeLeft

        logger.log("Account \(self.formatAccountId(accountId), privacy: .public): timer-only update, time remaining=\(timeLeft, privacy: .public)")
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
        let resetDate: Date?
        if let resetsAtString = period.resets_at {
            resetDate = parseDate(resetsAtString)
            timeLeft = timeUntilReset(resetDate!)
        } else {
            resetDate = nil
            timeLeft = "N/A"
        }

        // Detect usage reset to 0
        if let previousPercent = previousUsagePercent[accountId] {
            // If previous usage was > 0 and new usage is 0 (or very low), the account has reset
            if previousPercent > 0 && percent <= 5 {
                logger.log("Account \(self.formatAccountId(accountId), privacy: .public): detected reset (previous=\(previousPercent, privacy: .public)%, current=\(percent, privacy: .public)%)")
                sendResetNotification(for: accountId)
            }
        }

        // Update previous usage for next comparison
        previousUsagePercent[accountId] = percent

        // Log the fetched data
        logger.log("Account \(self.formatAccountId(accountId), privacy: .public): usage=\(percent, privacy: .public)%, resets=\(timeLeft, privacy: .public)")

        // Add data point to history
        let dataPoint = UsageDataPoint(timestamp: Date(), percent: percent)
        usageStates[index].history.append(dataPoint)

        // Keep only last 5 minutes of data
        let cutoffTime = Date().addingTimeInterval(-historyDuration)
        usageStates[index].history.removeAll { $0.timestamp < cutoffTime }

        usageStates[index].percent = percent
        usageStates[index].timeUntilReset = timeLeft
        usageStates[index].resetDate = resetDate

        // Calculate time to 100% AFTER state is updated
        let timeToFull = calculateTimeToFull(for: &usageStates[index])
        if let timeToFull = timeToFull {
            logger.log("Account \(self.formatAccountId(accountId), privacy: .public): estimated time to full=\(timeToFull, privacy: .public)")
        }

        usageStates[index].timeToFull = timeToFull
        usageStates[index].status = .success
        usageStates[index].error = nil

        // Restart timer with appropriate interval based on new data
        startRefreshTimer(for: accountId)
    }

    private func updateState(for accountId: String, error: String) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }) else { return }
        logger.error("Account \(self.formatAccountId(accountId), privacy: .public): error=\(error, privacy: .public)")
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

        guard percent < 100 else {
            // Don't log when already at 100% - this is expected
            return nil
        }

        let historyCount = state.history.count
        guard historyCount >= 2 else {
            logger.log("Account \(self.formatAccountId(accountId), privacy: .public): insufficient history for time-to-full calculation (historyCount=\(historyCount, privacy: .public))")
            return nil
        }

        // Get data from the last 5 minutes
        let now = Date()
        let oldestTime = now.addingTimeInterval(-historyDuration)
        let relevantHistory = state.history.filter { $0.timestamp >= oldestTime }

        guard relevantHistory.count >= 2 else {
            logger.log("Account \(self.formatAccountId(accountId), privacy: .public): filtered history too small (relevantHistoryCount=\(relevantHistory.count, privacy: .public))")
            return nil
        }

        let firstPoint = relevantHistory.first!
        let lastPoint = relevantHistory.last!
        let timeDiff = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)

        guard timeDiff > 0 else { return nil }

        let percentDiff = lastPoint.percent - firstPoint.percent
        guard percentDiff > 0 else {
            logger.log("Account \(self.formatAccountId(accountId), privacy: .public): usage not increasing (percentDiff=\(percentDiff, privacy: .public))")
            return nil // Not increasing
        }

        let percentPerSecond = Double(percentDiff) / timeDiff
        let percentRemaining = Double(100 - percent)
        let secondsToFull = percentRemaining / percentPerSecond

        logger.log("Account \(self.formatAccountId(accountId), privacy: .public): time-to-full calculation: percentDiff=\(percentDiff, privacy: .public), timeDiff=\(String(format: "%.1f", timeDiff), privacy: .public)s, velocity=\(String(format: "%.3f", percentPerSecond), privacy: .public)%/s, secondsToFull=\(String(format: "%.0f", secondsToFull), privacy: .public)s")

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
                if state.percent >= 100 {
                    return state.timeUntilReset
                } else {
                    return "\(state.percent)%"
                }
            case .error:
                return "ERROR"
            }
        }
        return displays.joined(separator: " | ")
    }
}
