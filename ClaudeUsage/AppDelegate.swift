import AppKit
import Foundation
import UserNotifications

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var accountManager: AccountManager?
    var usageManager: UsageManager?
    var menuUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Request notification permissions
        requestNotificationPermissions()

        // Initialize managers
        accountManager = AccountManager()
        usageManager = UsageManager()
        usageManager?.setAccountManager(accountManager!)

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenuBarButton()
        updateMenuBar()

        // Setup handlers
        setupMenuHandlers()

        // Load accounts and setup usage tracking
        let accounts = accountManager?.accounts ?? []
        for account in accounts {
            usageManager?.setupForAccount(account)
        }

        // Update menu bar periodically
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.updateMenuBar()
            }
        }
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }

        // Clear any stale usage-reset notifications that may have been scheduled
        // with old (non-normalized) identifiers to prevent duplicates
        center.getPendingNotificationRequests { requests in
            let staleIdentifiers = requests
                .map { $0.identifier }
                .filter { $0.hasPrefix("usage-reset-") }

            if !staleIdentifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
                print("Cleared \(staleIdentifiers.count) stale usage-reset notification(s)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Display notifications even when the app is in the foreground
        completionHandler([.banner, .sound])
    }

    private func setupMenuBarButton() {
        guard let button = statusItem?.button else { return }
        button.title = "Claude"
        button.font = NSFont.systemFont(ofSize: 13, weight: .regular)
    }

    private func setupMenuHandlers() {
        MenuDelegate.addAccountHandler = { [weak self] in
            self?.showAddAccountDialog()
        }

        MenuDelegate.refreshHandler = { [weak self] in
            self?.refreshAllAccounts()
        }

        MenuDelegate.resetHandler = { [weak self] in
            self?.resetAllAccounts()
        }
    }

    private func updateMenuBar() {
        guard let usageManager = usageManager else { return }
        statusItem?.button?.title = usageManager.menuBarTitle()
        updateMenu()
    }

    private func updateMenu() {
        guard let accountManager = accountManager, let usageManager = usageManager else { return }

        let menu = MenuBuilder.buildMenu(
            usageStates: usageManager.usageStates,
            accountManager: accountManager,
            usageManager: usageManager,
            onAddAccount: { [weak self] in self?.showAddAccountDialog() },
            onRefresh: { [weak self] in self?.refreshAllAccounts() },
            onReset: { [weak self] in self?.resetAllAccounts() }
        )

        statusItem?.menu = menu
    }

    private func showAddAccountDialog() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Add Claude Account"
        window.center()
        window.isReleasedWhenClosed = false

        let controller = AddAccountViewController()
        window.contentViewController = controller

        controller.onAccountAdded = { [weak self] account in
            self?.accountManager?.addOrUpdateAccount(orgId: account.id, sessionKey: account.sessionKey, name: account.name)
            self?.usageManager?.setupForAccount(account)
            self?.updateMenuBar()
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func refreshAllAccounts() {
        guard let usageManager = usageManager else { return }

        for state in usageManager.usageStates {
            usageManager.updateUsage(for: state.id)
        }
    }

    private func resetAllAccounts() {
        guard let accountManager = accountManager, let usageManager = usageManager else { return }

        // Clear all accounts from account manager
        accountManager.accounts.removeAll()
        accountManager.saveAccounts()

        // Remove all accounts from usage manager
        for state in usageManager.usageStates {
            usageManager.removeAccount(state.id)
        }

        // Update the menu
        updateMenuBar()
    }
}

// MARK: - Main

@main
struct UsageApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
