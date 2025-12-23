import AppKit
import Foundation
import SwiftUI
import UserNotifications

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var accountManager: AccountManager?
    var usageManager: UsageManager?
    var hostingView: NSHostingView<MenuBarProgressView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Request notification permissions
        requestNotificationPermissions()

        // Initialize managers
        accountManager = AccountManager()
        usageManager = UsageManager()
        usageManager?.setAccountManager(accountManager!)
        usageManager?.onStateChange = { [weak self] in
            self?.updateMenuBar()
        }

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
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Refresh usage data when reset notification fires
        Task { @MainActor [weak self] in
            self?.usageManager?.refreshAllAccounts()
        }

        // Display notifications even when the app is in the foreground
        completionHandler([.banner, .sound])
    }

    private func setupMenuBarButton() {
        guard let button = statusItem?.button,
              let usageManager = usageManager,
              let accountManager = accountManager else { return }

        // Create SwiftUI view for circular progress indicators
        let progressView = MenuBarProgressView(
            usageManager: usageManager,
            accountManager: accountManager
        )

        hostingView = NSHostingView(rootView: progressView)
        hostingView?.frame = NSRect(x: 0, y: 0, width: 100, height: 22)

        // Add the hosting view to the button
        if let hostingView = hostingView {
            button.addSubview(hostingView)
            button.frame = hostingView.frame
        }
    }

    private func setupMenuHandlers() {
        MenuDelegate.addAccountHandler = { [weak self] in
            self?.showAddAccountDialog()
        }

        MenuDelegate.resetHandler = { [weak self] in
            self?.resetAllAccounts()
        }
    }

    private func updateMenuBar() {
        guard let hostingView = hostingView,
              let button = statusItem?.button else { return }

        // Let SwiftUI calculate the intrinsic size, add buffer to prevent clipping
        let fittingSize = hostingView.fittingSize
        let width = ceil(fittingSize.width) + 4
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 22)
        button.frame = hostingView.frame

        // Create menu with delegate (content built lazily in menuWillOpen)
        if statusItem?.menu == nil {
            let menu = NSMenu()
            menu.delegate = self
            statusItem?.menu = menu
        }
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        // Run synchronously on MainActor since menu needs items before returning
        MainActor.assumeIsolated {
            guard let accountManager = accountManager, let usageManager = usageManager else { return }

            menu.removeAllItems()

            let builtMenu = MenuBuilder.buildMenu(
                usageStates: usageManager.usageStates,
                accountManager: accountManager,
                usageManager: usageManager
            )

            // Copy items from built menu to the existing menu
            for item in builtMenu.items {
                builtMenu.removeItem(item)
                menu.addItem(item)
            }
        }
    }

    private func showAddAccountDialog() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Add Claude Account"
        window.center()
        window.isReleasedWhenClosed = false

        let addAccountView = AddAccountView { [weak self, weak window] account in
            self?.accountManager?.addOrUpdateAccount(orgId: account.id, sessionKey: account.sessionKey, name: account.name)
            self?.usageManager?.setupForAccount(account)
            self?.updateMenuBar()
            window?.close()
        }

        let controller = NSHostingController(rootView: addAccountView)
        window.contentViewController = controller

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
