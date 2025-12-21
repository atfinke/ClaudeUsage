import SwiftUI

// MARK: - Menu Bar Progress View

struct MenuBarProgressView: View {
    let usageManager: UsageManager
    let accountManager: AccountManager

    private let circleSize: CGFloat = 11
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        HStack(spacing: 0) {
            if usageManager.usageStates.isEmpty {
                Text("Setup")
                    .font(.system(size: 13, weight: .regular))
            } else {
                ForEach(Array(sortedStates.enumerated()), id: \.element.id) { index, state in
                    if index > 0 {
                        Text("  |  ")
                            .font(.system(size: 13, weight: .regular))
                    }

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
        usageManager.usageStates.sorted { state1, state2 in
            let account1 = accountManager.accounts.first(where: { $0.id == state1.id })
            let account2 = accountManager.accounts.first(where: { $0.id == state2.id })

            let name1 = account1?.name ?? state1.id
            let name2 = account2?.name ?? state2.id

            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
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
                Text(state.timeUntilReset)
                    .font(.system(size: 13, weight: .regular))
            } else {
                CircularProgressIndicator(
                    percent: state.percent,
                    predictedPercent: state.predictedPercent,
                    size: circleSize,
                    lineWidth: lineWidth
                )
            }
        case .error:
            Text("ERR")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Circular Progress Indicator

struct CircularProgressIndicator: View {
    let percent: Int
    let predictedPercent: Int?
    let size: CGFloat
    let lineWidth: CGFloat

    private var currentProgress: CGFloat {
        CGFloat(percent) / 100.0
    }

    private var predictedProgress: CGFloat {
        guard let predicted = predictedPercent, predicted > percent else { return 0 }
        return CGFloat(predicted) / 100.0
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.primary.opacity(0.3), lineWidth: lineWidth)

            // Predicted progress arc (ghost/shadow)
            if predictedProgress > 0 {
                Circle()
                    .trim(from: 0, to: predictedProgress)
                    .stroke(
                        Color.primary.opacity(0.5),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: predictedProgress)
            }

            // Current progress arc (solid)
            Circle()
                .trim(from: 0, to: currentProgress)
                .stroke(
                    Color.primary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: currentProgress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Animated Preview Helper

struct AnimatedPreviewContainer: View {
    @State private var percent: Int = 20
    @State private var predictedPercent: Int = 35

    var body: some View {
        VStack(spacing: 20) {
            Text("Animated Preview")
                .font(.headline)

            HStack(spacing: 20) {
                CircularProgressIndicator(
                    percent: percent,
                    predictedPercent: predictedPercent,
                    size: 44,
                    lineWidth: 6
                )

                VStack(alignment: .leading) {
                    Text("Current: \(percent)%")
                    Text("Predicted: \(predictedPercent)%")
                }
            }

            Button("Simulate Progress") {
                withAnimation {
                    percent = min(100, percent + 10)
                    predictedPercent = min(100, percent + 15)
                }
            }

            Button("Reset") {
                withAnimation {
                    percent = 20
                    predictedPercent = 35
                }
            }
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Static States") {
    VStack(spacing: 20) {
        HStack(spacing: 10) {
            // 25% with no prediction
            CircularProgressIndicator(percent: 25, predictedPercent: nil, size: 11, lineWidth: 2.5)
            // 25% with prediction to 40%
            CircularProgressIndicator(percent: 25, predictedPercent: 40, size: 11, lineWidth: 2.5)
            // 50% with prediction to 75%
            CircularProgressIndicator(percent: 50, predictedPercent: 75, size: 11, lineWidth: 2.5)
            // 75% with prediction to 100%
            CircularProgressIndicator(percent: 75, predictedPercent: 100, size: 11, lineWidth: 2.5)
        }

        // Larger versions for visibility
        HStack(spacing: 20) {
            CircularProgressIndicator(percent: 30, predictedPercent: 50, size: 44, lineWidth: 6)
            CircularProgressIndicator(percent: 60, predictedPercent: 85, size: 44, lineWidth: 6)
            CircularProgressIndicator(percent: 90, predictedPercent: 100, size: 44, lineWidth: 6)
        }
    }
    .padding()
    .background(Color.black.opacity(0.1))
}

#Preview("Animated") {
    AnimatedPreviewContainer()
}
