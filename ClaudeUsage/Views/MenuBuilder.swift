import AppKit
import SwiftUI
import Foundation

// MARK: - Menu Delegate

@MainActor
class MenuDelegate: NSObject {
    static var addAccountHandler: (() -> Void)?
    static var resetHandler: (() -> Void)?

    @objc static func addAccount() {
        addAccountHandler?()
    }

    @objc static func reset() {
        resetHandler?()
    }
}

// MARK: - Menu Builder

class MenuBuilder {
    @MainActor
    static func buildMenu(usageStates: [UsageState], accountManager: AccountManager, usageManager: UsageManager) -> NSMenu {
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
            let sortedStates = accountManager.sortedByDisplayName(usageStates)

            for state in sortedStates {
                if let account = accountManager.accounts.first(where: { $0.id == state.id }) {
                    // SwiftUI usage view
                    let usageView = UsageMenuView(state: state, accountName: account.name)
                    let hostingView = NSHostingView(rootView: usageView)

                    // Calculate height based on content
                    let baseHeight: CGFloat = 60
                    var height = baseHeight
                    if state.timeToFull != nil {
                        height += 18
                    }
                    if state.weeklyPercent != nil {
                        height += 18  // Weekly percent line
                        if state.weeklyTimeUntilReset != nil {
                            height += 18  // Weekly reset line
                        }
                    }

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

        // Reset button
        let resetItem = menu.addItem(
            withTitle: "Reset Accounts",
            action: #selector(MenuDelegate.reset),
            keyEquivalent: ""
        )
        resetItem.target = MenuDelegate.self

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return menu
    }
}
