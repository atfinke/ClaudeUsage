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
    var predictedPercent: Int? // Estimated percent based on current velocity
    var resetProgress: Int? // When at 100%: percentage of reset window remaining (100 = just hit limit, 0 = about to reset)
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
    var onStateChange: (() -> Void)?
    private var clients: [String: ClaudeUsageClient] = [:]
    private var refreshTimers: [String: Timer] = [:]
    private var accountManager: AccountManager?
    // Scheduled notifications: Maps reset date -> set of account IDs that reset at that time
    private var scheduledResetNotifications: [Date: Set<String>] = [:]
    // Track last scheduled reset time per account to avoid redundant notification updates
    private var lastScheduledResetTime: [String: Date] = [:]

    // MARK: Constants

    /// How often to poll the API when close to reset time (30s).
    /// Used when time until reset is below `idleThreshold`. Also the fallback
    /// when reset date is unknown.
    private let activeRefreshInterval: TimeInterval = 30

    /// How often to poll the API when far from reset time (60s).
    /// Used when time until reset exceeds `idleThreshold`.
    private let idleRefreshInterval: TimeInterval = 60

    /// Threshold for switching between active and idle polling (2 min).
    /// Below this: poll every `activeRefreshInterval` for responsive updates.
    /// Above this: poll every `idleRefreshInterval` to reduce API calls.
    private let idleThreshold: TimeInterval = 120

    /// Window of historical data points used to calculate usage velocity (5 min).
    /// Longer windows smooth out spikes but are slower to reflect rate changes.
    private let historyDuration: TimeInterval = 300

    /// Claude's usage reset window (5 hours). Used to calculate countdown progress
    /// when at 100% utilization (how much of the wait remains).
    private let resetWindowDuration: TimeInterval = 5 * 60 * 60

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

    private func scheduleOrUpdateResetNotification(for accountId: String, resetDate: Date) {
        // Normalize reset date to the nearest minute to prevent duplicate notifications
        // when API returns timestamps that fluctuate by a few seconds between calls
        let secondsSince1970 = resetDate.timeIntervalSince1970
        let normalizedSeconds = round(secondsSince1970 / 60.0) * 60.0
        let normalizedResetDate = Date(timeIntervalSince1970: normalizedSeconds)

        // Skip if this account's reset time hasn't changed
        if lastScheduledResetTime[accountId] == normalizedResetDate {
            return
        }

        // Remove from old reset time group if it changed
        if let oldResetTime = lastScheduledResetTime[accountId] {
            scheduledResetNotifications[oldResetTime]?.remove(accountId)
            if scheduledResetNotifications[oldResetTime]?.isEmpty == true {
                scheduledResetNotifications.removeValue(forKey: oldResetTime)
            }
        }
        lastScheduledResetTime[accountId] = normalizedResetDate

        // Add this account to the set of accounts resetting at this time
        if scheduledResetNotifications[normalizedResetDate] == nil {
            scheduledResetNotifications[normalizedResetDate] = Set<String>()
        }
        scheduledResetNotifications[normalizedResetDate]?.insert(accountId)

        let accountCount = scheduledResetNotifications[normalizedResetDate]?.count ?? 0
        logger.log("Account \(self.formatAccountId(accountId), privacy: .public): scheduling reset notification for \(normalizedResetDate, privacy: .public) (\(accountCount, privacy: .public) total accounts)")

        updateNotificationContent(for: normalizedResetDate)
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
        lastScheduledResetTime.removeValue(forKey: accountId)

        // Remove account from all scheduled notifications and update them
        for (resetDate, var accountIds) in scheduledResetNotifications {
            if accountIds.contains(accountId) {
                accountIds.remove(accountId)

                if accountIds.isEmpty {
                    // No more accounts for this reset date, cancel the notification
                    scheduledResetNotifications.removeValue(forKey: resetDate)
                    let identifier = "usage-reset-\(Int(resetDate.timeIntervalSince1970))"
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
                    logger.log("Cancelled notification for \(resetDate, privacy: .public) (no accounts remaining)")
                } else {
                    // Update the notification with remaining accounts
                    scheduledResetNotifications[resetDate] = accountIds
                    updateNotificationContent(for: resetDate)
                }
            }
        }
    }

    func refreshAllAccounts() {
        for state in usageStates {
            updateUsage(for: state.id)
        }
    }

    private func updateNotificationContent(for resetDate: Date) {
        let accountIds = scheduledResetNotifications[resetDate] ?? []
        guard !accountIds.isEmpty else { return }

        let accountNames = accountIds.map { id in
            if let account = accountManager?.accounts.first(where: { $0.id == id }),
               let name = account.name {
                return name
            } else {
                return String(id.prefix(8)) + "..."
            }
        }.sorted()

        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Reset"
        if accountNames.count == 1 {
            content.body = "\(accountNames.first ?? "Account") usage has reset to 0%"
        } else {
            content.body = "\(accountNames.count) accounts have reset to 0%: \(accountNames.joined(separator: ", "))"
        }
        content.sound = .default

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: resetDate)
        components.second = 0 // Ensure notification fires at the start of the minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let identifier = "usage-reset-\(Int(resetDate.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to update notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func startRefreshTimer(for accountId: String) {
        refreshTimers[accountId]?.invalidate()

        let interval = refreshInterval(for: accountId)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.updateUsage(for: accountId)
            }
        }
        timer.tolerance = interval * 0.1 // 10% tolerance for battery efficiency
        refreshTimers[accountId] = timer
    }

    private func refreshInterval(for accountId: String) -> TimeInterval {
        guard let state = usageStates.first(where: { $0.id == accountId }),
              let resetDate = state.resetDate else {
            return activeRefreshInterval
        }

        let timeRemaining = resetDate.timeIntervalSince(Date())
        if timeRemaining > idleThreshold {
            return idleRefreshInterval
        } else {
            return activeRefreshInterval
        }
    }

    func updateUsage(for accountId: String) {
        guard let client = clients[accountId] else { return }

        // Skip network when at 100% - just update countdown timer locally
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

        // Recalculate reset progress (countdown) since it changes over time
        usageStates[index].resetProgress = calculateResetProgress(for: usageStates[index])

        logger.log("Account \(self.formatAccountId(accountId), privacy: .public): timer-only update, time remaining=\(timeLeft, privacy: .public)")
    }

    private func updateState(for accountId: String, usage: UsageData) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }) else { return }

        guard let period = usage.fiveHour else {
            usageStates[index].status = .error
            usageStates[index].error = "No usage data"
            return
        }

        let percent = Int(period.utilization)
        let timeLeft: String
        let resetDate: Date?
        if let resetsAtString = period.resetsAt {
            resetDate = parseDate(resetsAtString)
            timeLeft = timeUntilReset(resetDate!)
        } else {
            resetDate = nil
            timeLeft = "N/A"
        }

        // Schedule notification for when this account's usage period resets
        if let resetDate = resetDate {
            scheduleOrUpdateResetNotification(for: accountId, resetDate: resetDate)
        }

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

        // Calculate predicted percent based on velocity
        let predictedPercent = calculatePredictedPercent(for: usageStates[index])
        if let predicted = predictedPercent {
            logger.log("Account \(self.formatAccountId(accountId), privacy: .public): predicted percent=\(predicted, privacy: .public)%")
        }

        // Calculate reset progress (countdown when at 100%)
        let resetProgress = calculateResetProgress(for: usageStates[index])

        usageStates[index].timeToFull = timeToFull
        usageStates[index].predictedPercent = predictedPercent
        usageStates[index].resetProgress = resetProgress
        usageStates[index].status = .success
        usageStates[index].error = nil

        // Restart timer with appropriate interval based on new data
        startRefreshTimer(for: accountId)

        onStateChange?()
    }

    private func updateState(for accountId: String, error: String) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }) else { return }
        logger.error("Account \(self.formatAccountId(accountId), privacy: .public): error=\(error, privacy: .public)")
        usageStates[index].status = .error
        usageStates[index].error = error

        onStateChange?()
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

    /// Returns velocity in percent per second, or nil if not calculable
    private func calculateVelocity(for state: UsageState) -> Double? {
        let historyCount = state.history.count
        guard historyCount >= 2 else { return nil }

        // Get data from the last 5 minutes
        let now = Date()
        let oldestTime = now.addingTimeInterval(-historyDuration)
        let relevantHistory = state.history.filter { $0.timestamp >= oldestTime }

        guard relevantHistory.count >= 2 else { return nil }

        let firstPoint = relevantHistory.first!
        let lastPoint = relevantHistory.last!
        let timeDiff = lastPoint.timestamp.timeIntervalSince(firstPoint.timestamp)

        guard timeDiff > 0 else { return nil }

        let percentDiff = lastPoint.percent - firstPoint.percent
        guard percentDiff > 0 else { return nil } // Not increasing

        return Double(percentDiff) / timeDiff
    }

    private func calculateTimeToFull(for state: inout UsageState) -> String? {
        let accountId = state.id
        let percent = state.percent

        guard percent < 100 else {
            // Don't log when already at 100% - this is expected
            return nil
        }

        guard let percentPerSecond = calculateVelocity(for: state) else {
            logger.log("Account \(self.formatAccountId(accountId), privacy: .public): insufficient data for time-to-full calculation")
            return nil
        }

        let percentRemaining = Double(100 - percent)
        let secondsToFull = percentRemaining / percentPerSecond

        logger.log("Account \(self.formatAccountId(accountId), privacy: .public): time-to-full calculation: velocity=\(String(format: "%.3f", percentPerSecond), privacy: .public)%/s, secondsToFull=\(String(format: "%.0f", secondsToFull), privacy: .public)s")

        guard secondsToFull > 0 && secondsToFull < Double(Int.max) else { return nil }

        return formatDuration(secondsToFull)
    }

    /// How far ahead to project usage based on current velocity (15 min).
    /// Shown as a "ghost" arc on the circular progress indicator.
    private let predictionWindow: TimeInterval = 900

    private func calculatePredictedPercent(for state: UsageState) -> Int? {
        let percent = state.percent

        guard percent < 100 else { return nil }

        guard let percentPerSecond = calculateVelocity(for: state) else { return nil }

        let predictedIncrease = percentPerSecond * predictionWindow
        let predictedPercent = Double(percent) + predictedIncrease

        // Cap at 100
        return min(100, Int(predictedPercent))
    }

    /// Calculate reset progress (countdown) when at 100%
    /// Returns percentage of reset window remaining: 100 = just hit limit, 0 = about to reset
    private func calculateResetProgress(for state: UsageState) -> Int? {
        guard state.percent >= 100,
              let resetDate = state.resetDate else { return nil }

        let now = Date()
        let timeRemaining = resetDate.timeIntervalSince(now)

        guard timeRemaining > 0 else { return 0 }

        // Calculate what percentage of the 5-hour window remains
        let progress = (timeRemaining / resetWindowDuration) * 100.0
        return min(100, max(0, Int(progress)))
    }
}
