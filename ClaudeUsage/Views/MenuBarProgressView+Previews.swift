import SwiftUI

// MARK: - Preview Helpers

private class PreviewUsageManager: UsageManager {
    init(states: [UsageState]) {
        super.init()
        self.usageStates = states
    }
}

private class PreviewAccountManager: AccountManager {
    private let mockAccounts: [Account]

    init(accounts: [Account]) {
        self.mockAccounts = accounts
        super.init()
    }

    override func displayName(for accountId: String) -> String {
        mockAccounts.first { $0.id == accountId }?.name ?? accountId
    }
}

// MARK: - Sample Data

private let sampleAccounts = [
    Account(id: "work", sessionKey: "", name: "Work"),
    Account(id: "personal", sessionKey: "", name: "Personal"),
    Account(id: "team", sessionKey: "", name: "Team"),
]

private let typicalStates: [UsageState] = [
    UsageState(
        id: "work",
        percent: 22,
        predictedPercent: 80,
        resetDate: Date().addingTimeInterval(3 * 60 * 60),
        status: .success
    ),
    UsageState(
        id: "personal",
        percent: 78,
        predictedPercent: 95,
        resetDate: Date().addingTimeInterval(2 * 60 * 60),
        status: .success
    ),
]

private let mixedStates: [UsageState] = [
    UsageState(id: "work", percent: 25, predictedPercent: 40, resetDate: Date().addingTimeInterval(4 * 60 * 60), status: .success),
    UsageState(id: "personal", percent: 100, predictedPercent: nil, resetDate: Date().addingTimeInterval(1 * 60 * 60), status: .success),
    UsageState(id: "team", status: .loading),
]

private let allAtLimitStates: [UsageState] = [
    UsageState(id: "work", percent: 100, predictedPercent: nil, resetDate: Date().addingTimeInterval(2.5 * 60 * 60), status: .success),
    UsageState(id: "personal", percent: 100, predictedPercent: nil, resetDate: Date().addingTimeInterval(0.5 * 60 * 60), status: .success),
]

// MARK: - Previews

#Preview("Menu Bar - Typical") {
    MenuBarProgressView(
        usageManager: PreviewUsageManager(states: typicalStates),
        accountManager: PreviewAccountManager(accounts: sampleAccounts)
    )
    .padding()
    .background(.black.opacity(0.8))
}

#Preview("Menu Bar - Mixed States") {
    MenuBarProgressView(
        usageManager: PreviewUsageManager(states: mixedStates),
        accountManager: PreviewAccountManager(accounts: sampleAccounts)
    )
    .padding()
    .background(.black.opacity(0.8))
}

#Preview("Menu Bar - At Limit") {
    MenuBarProgressView(
        usageManager: PreviewUsageManager(states: allAtLimitStates),
        accountManager: PreviewAccountManager(accounts: sampleAccounts)
    )
    .padding()
    .background(.black.opacity(0.8))
}

#Preview("Menu Bar - Empty/Setup") {
    MenuBarProgressView(
        usageManager: PreviewUsageManager(states: []),
        accountManager: PreviewAccountManager(accounts: [])
    )
    .padding()
    .background(.black.opacity(0.8))
}

#Preview("Interactive") {
    InteractivePreview()
}

// MARK: - Interactive Preview

private struct InteractivePreview: View {
    @State private var percent: Int = 45
    @State private var predictedPercent: Int = 60
    @State private var showPredicted = true

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                CircularProgressIndicator(
                    percent: percent,
                    predictedPercent: showPredicted ? predictedPercent : nil,
                    size: 44,
                    lineWidth: 6
                )

                VStack(alignment: .leading) {
                    Text("Current: \(percent)%")
                    if showPredicted {
                        Text("Predicted: \(predictedPercent)%")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Usage")
                    Slider(value: .init(
                        get: { Double(percent) },
                        set: { percent = Int($0) }
                    ), in: 0...100)
                }

                HStack {
                    Text("Predicted")
                    Slider(value: .init(
                        get: { Double(predictedPercent) },
                        set: { predictedPercent = Int($0) }
                    ), in: 0...100)
                    .disabled(!showPredicted)
                }

                Toggle("Show Predicted", isOn: $showPredicted)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
