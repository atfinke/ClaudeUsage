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
    var resetProgress: Int? // Percentage of reset window remaining (100 = just started window, 0 = about to reset)
    var timeUntilReset: String = "..."
    var resetDate: Date? // When the usage period resets
    var status: Status = .loading
    var error: String?
    var timeToFull: String? // ETA to 100%
    var history: [UsageDataPoint] = [] // Last 5 minutes of data

    // Weekly limit (seven_day) - optional, only some accounts have this
    var weeklyPercent: Int?
    var weeklyTimeUntilReset: String?

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
    private var globalRefreshTimer: Timer?
    private var accountManager: AccountManager?
    // Scheduled notifications: Maps reset date -> set of account IDs that reset at that time
    private var scheduledResetNotifications: [Date: Set<String>] = [:]
    // Track last scheduled reset time per account to avoid redundant notification updates
    private var lastScheduledResetTime: [String: Date] = [:]

    // Debounce state for batching UI updates
    private var pendingRefreshAccounts: Set<String> = []
    private var completedRefreshAccounts: Set<String> = []
    private var debounceTask: Task<Void, Never>?
    private let debounceTimeout: TimeInterval = 5

    var isPaused: Bool = false {
        didSet {
            if isPaused {
                logger.debug("Usage tracking paused")
                globalRefreshTimer?.invalidate()
                globalRefreshTimer = nil
            } else {
                logger.debug("Usage tracking resumed")
                startGlobalRefreshTimer()
                refreshAllAccounts()
            }
        }
    }

    // MARK: Constants

    /// How often the global timer fires to refresh all accounts (30s).
    /// Timer aligns to :01 and :31 second marks to catch resets at :00.
    private let activeRefreshInterval: TimeInterval = 30

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
        // resetDate is already normalized by caller to nearest minute

        // Skip if this account's reset time hasn't changed
        if lastScheduledResetTime[accountId] == resetDate {
            return
        }

        // Remove from old reset time group if it changed
        if let oldResetTime = lastScheduledResetTime[accountId] {
            scheduledResetNotifications[oldResetTime]?.remove(accountId)
            if scheduledResetNotifications[oldResetTime]?.isEmpty == true {
                scheduledResetNotifications.removeValue(forKey: oldResetTime)
            }
        }
        lastScheduledResetTime[accountId] = resetDate

        // Add this account to the set of accounts resetting at this time
        if scheduledResetNotifications[resetDate] == nil {
            scheduledResetNotifications[resetDate] = Set<String>()
        }
        scheduledResetNotifications[resetDate]?.insert(accountId)

        let accountCount = scheduledResetNotifications[resetDate]?.count ?? 0
        logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): scheduling reset notification for \(resetDate, privacy: .public) (\(accountCount, privacy: .public) total accounts)")

        updateNotificationContent(for: resetDate)
    }

    func setupForAccount(_ account: Account) {
        let client = ClaudeUsageClient(orgId: account.id, sessionKey: account.sessionKey)
        clients[account.id] = client

        // Create initial state
        if usageStates.firstIndex(where: { $0.id == account.id }) == nil {
            usageStates.append(UsageState(id: account.id))
        }

        // Start global timer if not already running
        if globalRefreshTimer == nil {
            startGlobalRefreshTimer()
        }

        // Fetch initial usage
        updateUsage(for: account.id)
    }

    func removeAccount(_ accountId: String) {
        clients.removeValue(forKey: accountId)
        usageStates.removeAll { $0.id == accountId }
        lastScheduledResetTime.removeValue(forKey: accountId)

        // Stop global timer if no accounts remain
        if usageStates.isEmpty {
            globalRefreshTimer?.invalidate()
            globalRefreshTimer = nil
        }

        // Remove account from all scheduled notifications and update them
        for (resetDate, var accountIds) in scheduledResetNotifications {
            if accountIds.contains(accountId) {
                accountIds.remove(accountId)

                if accountIds.isEmpty {
                    // No more accounts for this reset date, cancel the notification
                    scheduledResetNotifications.removeValue(forKey: resetDate)
                    let identifier = "usage-reset-\(Int(resetDate.timeIntervalSince1970))"
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
                    logger.debug("Cancelled notification for \(resetDate, privacy: .public) (no accounts remaining)")
                } else {
                    // Update the notification with remaining accounts
                    scheduledResetNotifications[resetDate] = accountIds
                    updateNotificationContent(for: resetDate)
                }
            }
        }
    }

    func refreshAllAccounts() {
        // Setup debounce tracking
        pendingRefreshAccounts = Set(usageStates.map { $0.id })
        completedRefreshAccounts.removeAll()
        debounceTask?.cancel()

        logger.debug("Debounce: starting refresh for \(self.pendingRefreshAccounts.count, privacy: .public) accounts")

        // Start timeout task
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                logger.debug("Debounce: timeout fired, flushing")
                self?.flushDebouncedUpdate()
            }
        }

        for state in usageStates {
            updateUsage(for: state.id)
        }
    }

    private func markRefreshComplete(for accountId: String) {
        completedRefreshAccounts.insert(accountId)
        logger.debug("Debounce: account complete \(self.completedRefreshAccounts.count, privacy: .public)/\(self.pendingRefreshAccounts.count, privacy: .public)")

        // Check if all pending accounts have completed
        if completedRefreshAccounts.isSuperset(of: pendingRefreshAccounts) {
            logger.debug("Debounce: all accounts complete, flushing")
            flushDebouncedUpdate()
        }
    }

    private func flushDebouncedUpdate() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingRefreshAccounts.removeAll()
        completedRefreshAccounts.removeAll()
        logger.debug("Debounce: UI update triggered")
        onStateChange?()
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
                logger.debug("Failed to update notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Starts a global timer that fires at :01 and :31 of each minute.
    /// This aligns all account polling to the same schedule, and ensures
    /// polling happens 1 second after reset times (which fire at :00).
    private func startGlobalRefreshTimer() {
        globalRefreshTimer?.invalidate()

        // Calculate time until the next :01 or :31 second mark
        let now = Date()
        let calendar = Calendar.current
        let currentSecond = calendar.component(.second, from: now)

        let nextAlignedSecond: Int
        if currentSecond < 1 {
            nextAlignedSecond = 1
        } else if currentSecond < 31 {
            nextAlignedSecond = 31
        } else {
            nextAlignedSecond = 61 // Will roll over to :01 of next minute
        }

        let secondsUntilNext = nextAlignedSecond - currentSecond
        let firstFireDate = now.addingTimeInterval(TimeInterval(secondsUntilNext))

        logger.debug("Starting global refresh timer, first fire in \(secondsUntilNext, privacy: .public)s at \(firstFireDate, privacy: .public)")

        // Use a one-shot timer for the first fire, then start the repeating timer
        globalRefreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secondsUntilNext), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.refreshAllAccounts()
                self.startRepeatingRefreshTimer()
            }
        }
    }

    private func startRepeatingRefreshTimer() {
        globalRefreshTimer?.invalidate()

        logger.debug("Starting repeating refresh timer (30s interval)")

        globalRefreshTimer = Timer.scheduledTimer(withTimeInterval: activeRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllAccounts()
            }
        }
        globalRefreshTimer?.tolerance = 1 // 1 second tolerance
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
        if isPaused {
            return true
        }

        guard let state = usageStates.first(where: { $0.id == accountId }) else {
            return false
        }

        guard let resetDate = state.resetDate else {
            return false
        }

        // Don't skip if within 1 second of reset (accounts for timer drift)
        let timeRemaining = resetDate.timeIntervalSince(Date())
        if timeRemaining <= 1 {
            return false
        }

        // Skip network requests if usage is at 100% (just update countdown timer locally)
        return state.percent >= 100
    }

    private func updateTimerOnly(for accountId: String) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }),
              let resetDate = usageStates[index].resetDate else { return }

        let timeLeft = timeUntilReset(resetDate)
        usageStates[index].timeUntilReset = timeLeft

        // Recalculate reset progress (countdown) since it changes over time
        usageStates[index].resetProgress = calculateResetProgress(for: usageStates[index])

        logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): timer-only update, time remaining=\(timeLeft, privacy: .public)")

        // Mark as complete for debounced UI update
        markRefreshComplete(for: accountId)
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
            let rawResetDate = parseDate(resetsAtString)
            // Normalize to nearest minute to match notification scheduling
            let secondsSince1970 = rawResetDate.timeIntervalSince1970
            let normalizedSeconds = round(secondsSince1970 / 60.0) * 60.0
            resetDate = Date(timeIntervalSince1970: normalizedSeconds)
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
        logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): usage=\(percent, privacy: .public)%, resets=\(timeLeft, privacy: .public)")

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
            logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): estimated time to full=\(timeToFull, privacy: .public)")
        }

        // Calculate predicted percent based on velocity
        let predictedPercent = calculatePredictedPercent(for: usageStates[index])
        if let predicted = predictedPercent {
            logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): predicted percent=\(predicted, privacy: .public)%")
        }

        // Calculate reset progress (countdown to reset time)
        let resetProgress = calculateResetProgress(for: usageStates[index])

        usageStates[index].timeToFull = timeToFull
        usageStates[index].predictedPercent = predictedPercent
        usageStates[index].resetProgress = resetProgress
        usageStates[index].status = .success
        usageStates[index].error = nil

        // Parse weekly limit if present
        if let sevenDay = usage.sevenDay {
            usageStates[index].weeklyPercent = Int(sevenDay.utilization)
            if let weeklyResetsAt = sevenDay.resetsAt {
                let weeklyResetDate = parseDate(weeklyResetsAt)
                usageStates[index].weeklyTimeUntilReset = timeUntilReset(weeklyResetDate)
            } else {
                usageStates[index].weeklyTimeUntilReset = nil
            }
        } else {
            usageStates[index].weeklyPercent = nil
            usageStates[index].weeklyTimeUntilReset = nil
        }

        markRefreshComplete(for: accountId)
    }

    private func updateState(for accountId: String, error: String) {
        guard let index = usageStates.firstIndex(where: { $0.id == accountId }) else { return }
        logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): error=\(error, privacy: .public)")
        usageStates[index].status = .error
        usageStates[index].error = error

        markRefreshComplete(for: accountId)
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
            logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): insufficient data for time-to-full calculation")
            return nil
        }

        let percentRemaining = Double(100 - percent)
        let secondsToFull = percentRemaining / percentPerSecond

        logger.debug("Account \(self.formatAccountId(accountId), privacy: .public): time-to-full calculation: velocity=\(String(format: "%.3f", percentPerSecond), privacy: .public)%/s, secondsToFull=\(String(format: "%.0f", secondsToFull), privacy: .public)s")

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

    /// Calculate reset progress (countdown) for any usage level
    /// Returns percentage of reset window remaining: 100 = just started window, 0 = about to reset
    private func calculateResetProgress(for state: UsageState) -> Int? {
        guard let resetDate = state.resetDate else { return nil }

        let now = Date()
        let timeRemaining = resetDate.timeIntervalSince(now)

        guard timeRemaining > 0 else { return 0 }

        // Calculate what percentage of the 5-hour window remains
        let progress = (timeRemaining / resetWindowDuration) * 100.0
        return min(100, max(0, Int(progress)))
    }
}
