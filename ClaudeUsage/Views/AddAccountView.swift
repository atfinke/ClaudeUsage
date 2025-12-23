import SwiftUI
import AppKit

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

// MARK: - Add Account View

struct AddAccountView: View {
    @State private var orgId = ""
    @State private var sessionKey = ""
    @State private var accountName = ""
    @State private var statusMessage = ""
    @State private var statusColor: Color = .red
    @State private var isValidating = false

    var onAccountAdded: (Account) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Instructions
            Text("Get the 'usage' request cURL from Inspector, then paste it below")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Buttons
            HStack(spacing: 12) {
                Button("Open Claude Settings") {
                    openSettings()
                }

                Button("Parse from Clipboard") {
                    parseCurl()
                }
            }

            // Org ID
            VStack(alignment: .leading, spacing: 6) {
                Text("Organization ID:")
                    .font(.system(size: 13))

                TextField("UUID (auto-filled from cURL)", text: $orgId)
                    .textFieldStyle(.roundedBorder)
            }

            // Session Key
            VStack(alignment: .leading, spacing: 6) {
                Text("Session Key:")
                    .font(.system(size: 13))

                TextField("sk-ant-... (auto-filled from cURL)", text: $sessionKey)
                    .textFieldStyle(.roundedBorder)
            }

            // Account Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Account Name (optional):")
                    .font(.system(size: 13))

                TextField("e.g., Work Account, Personal Account", text: $accountName)
                    .textFieldStyle(.roundedBorder)
            }

            // Status Message
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 1)

            // Add Button
            HStack {
                Spacer()

                Button("Add") {
                    validateAndAdd()
                }
                .disabled(isValidating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350, height: 380)
    }

    private func openSettings() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    private func parseCurl() {
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else {
            statusMessage = "Nothing found in clipboard"
            statusColor = .red
            return
        }

        let (parsedOrgId, parsedSessionKey) = CurlParser.parse(clipboardString)

        if let parsedOrgId = parsedOrgId {
            orgId = parsedOrgId
        } else {
            statusMessage = "Could not extract Org ID from clipboard"
            statusColor = .orange
        }

        if let parsedSessionKey = parsedSessionKey {
            sessionKey = parsedSessionKey
        } else {
            statusMessage = "Could not extract Session Key from clipboard"
            statusColor = .orange
        }

        if parsedOrgId != nil && parsedSessionKey != nil {
            statusMessage = "Parsed successfully!"
            statusColor = .green
        }
    }

    private func validateAndAdd() {
        guard !isValidating else { return }

        let trimmedOrgId = orgId.trimmingCharacters(in: .whitespaces)
        let trimmedSessionKey = sessionKey.trimmingCharacters(in: .whitespaces)
        let trimmedAccountName = accountName.trimmingCharacters(in: .whitespaces)

        guard !trimmedOrgId.isEmpty else {
            statusMessage = "Please enter Organization ID"
            statusColor = .red
            return
        }

        guard !trimmedSessionKey.isEmpty else {
            statusMessage = "Please enter Session Key"
            statusColor = .red
            return
        }

        isValidating = true
        statusMessage = "Validating..."
        statusColor = .orange

        Task {
            do {
                let client = ClaudeUsageClient(orgId: trimmedOrgId, sessionKey: trimmedSessionKey)
                let _: UsageData = try await client.fetchUsage()

                await MainActor.run {
                    var account = Account(id: trimmedOrgId, sessionKey: trimmedSessionKey)
                    if !trimmedAccountName.isEmpty {
                        account.name = trimmedAccountName
                    }
                    onAccountAdded(account)
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Validation failed: \(error.localizedDescription)"
                    statusColor = .red
                    isValidating = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddAccountView { account in
        print("Account added: \(account.id)")
    }
}
