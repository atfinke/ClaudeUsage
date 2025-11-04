import AppKit
import SwiftUI
import Foundation

// MARK: - Menu Delegate

@MainActor
class MenuDelegate: NSObject {
    static var addAccountHandler: (() -> Void)?
    static var refreshHandler: (() -> Void)?
    static var resetHandler: (() -> Void)?

    @objc static func addAccount() {
        addAccountHandler?()
    }

    @objc static func refreshNow() {
        refreshHandler?()
    }

    @objc static func reset() {
        resetHandler?()
    }
}

// MARK: - Menu Builder

class MenuBuilder {
    @MainActor
    static func buildMenu(usageStates: [UsageState], accountManager: AccountManager, usageManager: UsageManager, onAddAccount: @escaping () -> Void, onRefresh: @escaping () -> Void, onReset: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()

        // Empty state or account sections
        if usageStates.isEmpty {
            // Standard menu item for empty state
            let emptyItem = NSMenuItem(title: "No accounts configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)

            menu.addItem(NSMenuItem.separator())
        } else {
            // Account sections with SwiftUI views
            let sortedStates = usageStates.sorted { state1, state2 in
                let account1 = accountManager.accounts.first(where: { $0.id == state1.id })
                let account2 = accountManager.accounts.first(where: { $0.id == state2.id })

                let name1 = account1?.name ?? state1.id
                let name2 = account2?.name ?? state2.id

                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }

            for state in sortedStates {
                if let account = accountManager.accounts.first(where: { $0.id == state.id }) {
                    // SwiftUI usage view
                    let usageView = UsageMenuView(state: state, accountName: account.name)
                    let hostingView = NSHostingView(rootView: usageView)

                    // Calculate height based on content
                    let baseHeight: CGFloat = 60
                    let hasTimeToFull = state.timeToFull != nil
                    let height = hasTimeToFull ? baseHeight + 18 : baseHeight

                    hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: height)

                    let usageItem = NSMenuItem()
                    usageItem.view = hostingView
                    usageItem.isEnabled = false
                    menu.addItem(usageItem)

                    // Separator
                    menu.addItem(NSMenuItem.separator())
                }
            }
        }

        // Add Account button
        let addAccountItem = menu.addItem(
            withTitle: "Add Account",
            action: #selector(MenuDelegate.addAccount),
            keyEquivalent: ""
        )
        addAccountItem.target = MenuDelegate.self

        // Refresh button (only if accounts exist)
        if !usageStates.isEmpty {
            let refreshItem = menu.addItem(
                withTitle: "Refresh Now",
                action: #selector(MenuDelegate.refreshNow),
                keyEquivalent: "r"
            )
            refreshItem.target = MenuDelegate.self
        }

        menu.addItem(NSMenuItem.separator())

        // Reset button
        let resetItem = menu.addItem(
            withTitle: "Reset All Accounts",
            action: #selector(MenuDelegate.reset),
            keyEquivalent: ""
        )
        resetItem.target = MenuDelegate.self

        // Quit
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return menu
    }
}
