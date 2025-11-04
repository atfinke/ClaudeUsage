import AppKit
import Foundation

// MARK: - cURL Parser

struct CurlParser {
    static func parse(_ curlString: String) -> (orgId: String?, sessionKey: String?) {
        var orgId: String?
        var sessionKey: String?

        // Extract orgId from URL
        if let urlRange = curlString.range(of: "organizations/") {
            let afterOrg = curlString[urlRange.upperBound...]
            if let slashIndex = afterOrg.firstIndex(of: "/") {
                let id = String(afterOrg[..<slashIndex])
                if !id.isEmpty && id.count == 36 { // UUID format
                    orgId = id
                }
            }
        }

        // Extract sessionKey from Cookie header
        if let cookieRange = curlString.range(of: "sessionKey=") {
            let afterSessionKey = curlString[cookieRange.upperBound...]
            var key = ""
            for char in afterSessionKey {
                if char == ";" || char == "'" || char == "\"" || char == "\n" {
                    break
                }
                key.append(char)
            }
            if !key.isEmpty && key.hasPrefix("sk-ant-") {
                sessionKey = key.trimmingCharacters(in: .whitespaces)
            }
        }

        return (orgId, sessionKey)
    }
}

// MARK: - Add Account Dialog

class AddAccountViewController: NSViewController {
    private let orgIdTextField = NSTextField()
    private let sessionKeyTextField = NSTextField()
    private let accountNameTextField = NSTextField()
    private let statusLabel = NSTextField()
    private let addButton = NSButton()
    private let cancelButton = NSButton()
    private let parseButton = NSButton()
    private let openSettingsButton = NSButton()

    var onAccountAdded: ((Account) -> Void)?
    private var isValidating = false

    override func loadView() {
        view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 380)

        setupUI()
    }

    private func setupUI() {
        // Instructions
        let instructionsLabel = NSTextField(labelWithString: "Get the 'usage' request cURL from Inspector, then paste it below")
        instructionsLabel.font = NSFont.systemFont(ofSize: 12)
        instructionsLabel.textColor = .secondaryLabelColor
        instructionsLabel.frame = NSRect(x: 20, y: 330, width: 460, height: 32)
        instructionsLabel.cell?.wraps = true
        view.addSubview(instructionsLabel)

        // Open Settings Button
        openSettingsButton.frame = NSRect(x: 20, y: 280, width: 220, height: 32)
        openSettingsButton.title = "Open Claude Settings"
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openSettings)
        view.addSubview(openSettingsButton)

        // Parse from Clipboard Button
        parseButton.frame = NSRect(x: 260, y: 280, width: 220, height: 32)
        parseButton.title = "Parse from Clipboard"
        parseButton.bezelStyle = .rounded
        parseButton.target = self
        parseButton.action = #selector(parseCurl)
        view.addSubview(parseButton)

        // Org ID Label
        let orgIdLabel = NSTextField(labelWithString: "Organization ID:")
        orgIdLabel.frame = NSRect(x: 20, y: 225, width: 460, height: 16)
        view.addSubview(orgIdLabel)

        // Org ID TextField
        orgIdTextField.frame = NSRect(x: 20, y: 200, width: 460, height: 22)
        orgIdTextField.placeholderString = "UUID (auto-filled from cURL)"
        view.addSubview(orgIdTextField)

        // Session Key Label
        let sessionKeyLabel = NSTextField(labelWithString: "Session Key:")
        sessionKeyLabel.frame = NSRect(x: 20, y: 170, width: 460, height: 16)
        view.addSubview(sessionKeyLabel)

        // Session Key TextField
        sessionKeyTextField.frame = NSRect(x: 20, y: 145, width: 460, height: 22)
        sessionKeyTextField.placeholderString = "sk-ant-... (auto-filled from cURL)"
        view.addSubview(sessionKeyTextField)

        // Account Name Label
        let nameLabel = NSTextField(labelWithString: "Account Name (optional):")
        nameLabel.frame = NSRect(x: 20, y: 115, width: 460, height: 16)
        view.addSubview(nameLabel)

        // Account Name TextField
        accountNameTextField.frame = NSRect(x: 20, y: 90, width: 460, height: 22)
        accountNameTextField.placeholderString = "e.g., Work Account, Personal Account"
        view.addSubview(accountNameTextField)

        // Status Label
        statusLabel.frame = NSRect(x: 20, y: 65, width: 460, height: 24)
        statusLabel.textColor = .systemRed
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        view.addSubview(statusLabel)

        // Cancel Button
        cancelButton.frame = NSRect(x: 20, y: 20, width: 100, height: 32)
        cancelButton.title = "Cancel"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        view.addSubview(cancelButton)

        // Add Button
        addButton.frame = NSRect(x: 380, y: 20, width: 100, height: 32)
        addButton.title = "Add"
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(validateAndAdd)
        addButton.isEnabled = true
        view.addSubview(addButton)
    }

    @objc private func openSettings() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func parseCurl() {
        // Get clipboard content
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else {
            statusLabel.stringValue = "Nothing found in clipboard"
            statusLabel.textColor = .systemRed
            return
        }

        let (orgId, sessionKey) = CurlParser.parse(clipboardString)

        if let orgId = orgId {
            orgIdTextField.stringValue = orgId
        } else {
            statusLabel.stringValue = "Could not extract Org ID from clipboard"
            statusLabel.textColor = .systemOrange
        }

        if let sessionKey = sessionKey {
            sessionKeyTextField.stringValue = sessionKey
        } else {
            statusLabel.stringValue = "Could not extract Session Key from clipboard"
            statusLabel.textColor = .systemOrange
        }

        if orgId != nil && sessionKey != nil {
            statusLabel.stringValue = "Parsed successfully!"
            statusLabel.textColor = .systemGreen
            // Focus on account name field after successful parse
            self.view.window?.makeFirstResponder(accountNameTextField)
        }
    }

    @objc private func validateAndAdd() {
        guard !isValidating else { return }

        let orgId = orgIdTextField.stringValue.trimmingCharacters(in: .whitespaces)
        let sessionKey = sessionKeyTextField.stringValue.trimmingCharacters(in: .whitespaces)
        let accountName = accountNameTextField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !orgId.isEmpty else {
            statusLabel.stringValue = "Please enter Organization ID"
            statusLabel.textColor = .systemRed
            return
        }

        guard !sessionKey.isEmpty else {
            statusLabel.stringValue = "Please enter Session Key"
            statusLabel.textColor = .systemRed
            return
        }

        isValidating = true
        addButton.isEnabled = false
        statusLabel.stringValue = "Validating..."
        statusLabel.textColor = .systemOrange

        Task {
            do {
                let client = ClaudeUsageClient(orgId: orgId, sessionKey: sessionKey)
                let _: UsageData = try await client.fetchUsage()

                await MainActor.run {
                    var account = Account(id: orgId, sessionKey: sessionKey)
                    if !accountName.isEmpty {
                        account.name = accountName
                    }
                    self.onAccountAdded?(account)
                    self.view.window?.close()
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.stringValue = "Validation failed: \(error.localizedDescription)"
                    self.statusLabel.textColor = .systemRed
                    self.isValidating = false
                    self.addButton.isEnabled = true
                }
            }
        }
    }

    @objc private func cancel() {
        view.window?.close()
    }
}
