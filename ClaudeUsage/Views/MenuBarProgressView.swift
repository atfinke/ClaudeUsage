import SwiftUI

// MARK: - Menu Bar Progress View

struct MenuBarProgressView: View {
    let usageManager: UsageManager
    let accountManager: AccountManager

    private let circleSize: CGFloat = 16
    private let lineWidth: CGFloat = 2

    var body: some View {
        HStack(spacing: 10) {
            if usageManager.usageStates.isEmpty {
                Text("Setup")
                    .font(.system(size: 13, weight: .regular))
            } else {
                ForEach(sortedStates) { state in
                    StateIndicator(
                        state: state,
                        circleSize: circleSize,
                        lineWidth: lineWidth
                    )
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var sortedStates: [UsageState] {
        accountManager.sortedByDisplayName(usageManager.usageStates)
    }
}

// MARK: - State Indicator

struct StateIndicator: View {
    let state: UsageState
    let circleSize: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        switch state.status {
        case .loading:
            Text("...")
                .font(.system(size: 13, weight: .regular))
        case .success:
            if state.percent >= 100 {
                // At 100%: show only countdown indicator (full size)
                if let resetProgress = state.resetProgress {
                    CountdownIndicator(
                        resetProgress: resetProgress,
                        size: circleSize
                    )
                }
            } else if let resetProgress = state.resetProgress {
                // Below 100% with reset time: show both indicators overlaid
                ZStack {
                    CountdownIndicator(
                        resetProgress: resetProgress,
                        size: circleSize - (lineWidth * 2) - 3
                    )
                    CircularProgressIndicator(
                        percent: state.percent,
                        predictedPercent: state.predictedPercent,
                        size: circleSize,
                        lineWidth: lineWidth
                    )
                }
            } else {
                // No reset time: show only usage indicator
                CircularProgressIndicator(
                    percent: state.percent,
                    predictedPercent: state.predictedPercent,
                    size: circleSize,
                    lineWidth: lineWidth
                )
            }
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15))
        }
    }
}
