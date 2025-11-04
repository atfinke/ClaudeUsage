import Foundation

// MARK: - Account Model

struct Account: Codable, Identifiable {
    let id: String // orgId
    var sessionKey: String
    var name: String? // Optional friendly name

    enum CodingKeys: String, CodingKey {
        case id = "orgId"
        case sessionKey
        case name
    }
}

// MARK: - Account Manager

@MainActor
@Observable
class AccountManager {
    private static let accountsKey = "claude_accounts_keychain"

    var accounts: [Account] = []

    init() {
        loadAccounts()
    }

    private func loadAccounts() {
        guard let data = KeychainManager.shared.load(key: Self.accountsKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            return
        }
        accounts = decoded
    }

    func saveAccounts() {
        guard let encoded = try? JSONEncoder().encode(accounts) else { return }
        _ = KeychainManager.shared.save(key: Self.accountsKey, data: encoded)
    }

    func addOrUpdateAccount(orgId: String, sessionKey: String, name: String? = nil) {
        if let index = accounts.firstIndex(where: { $0.id == orgId }) {
            accounts[index].sessionKey = sessionKey
            if let name = name {
                accounts[index].name = name
            }
        } else {
            accounts.append(Account(id: orgId, sessionKey: sessionKey, name: name))
        }
        saveAccounts()
    }

    func removeAccount(id: String) {
        accounts.removeAll { $0.id == id }
        saveAccounts()
    }
}
