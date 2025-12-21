import SwiftUI

// MARK: - Menu Bar Progress View

struct MenuBarProgressView: View {
    let usageManager: UsageManager
    let accountManager: AccountManager

    private let circleSize: CGFloat = 16
    private let lineWidth: CGFloat = 3

    var body: some View {
        HStack(spacing: 0) {
            if usageManager.usageStates.isEmpty {
                Text("Setup")
                    .font(.system(size: 13, weight: .regular))
            } else {
                ForEach(Array(sortedStates.enumerated()), id: \.element.id) { index, state in
                    if index > 0 {
                        Text("|")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
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
                // At 100%: show countdown indicator
                CountdownIndicator(
                    resetProgress: state.resetProgress ?? 100,
                    size: circleSize
                )
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

// MARK: - Circular Progress Indicator (Normal Usage)

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
            // Background circle (inset so stroke stays within frame)
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Color.primary.opacity(0.3), lineWidth: lineWidth)

            // Predicted progress arc (ghost/shadow)
            if predictedProgress > 0 {
                Circle()
                    .inset(by: lineWidth / 2)
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
                .inset(by: lineWidth / 2)
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

// MARK: - Countdown Indicator (At 100%, waiting for reset)

struct CountdownIndicator: View {
    let resetProgress: Int // 100 = just hit limit, 0 = about to reset
    let size: CGFloat

    private var countdownProgress: CGFloat {
        CGFloat(resetProgress) / 100.0
    }

    var body: some View {
        ZStack {
            // Background circle (light blue)
            Circle()
                .fill(Color.blue.opacity(0.2))

            // Filled pie wedge (shrinks as reset approaches)
            PieSlice(progress: countdownProgress)
                .fill(Color.blue.opacity(0.5))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: countdownProgress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Pie Slice Shape

struct PieSlice: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let endAngle = Angle(degrees: 360 * Double(progress))

        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .zero,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Animated Preview Helpers

private struct AnimatedUsagePreview: View {
    @State private var percent: Int = 20
    @State private var predictedPercent: Int = 35

    var body: some View {
        VStack(spacing: 20) {
            Text("Usage Progress")
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

            HStack {
                Button("+10%") {
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
        }
        .padding()
    }
}

private struct AnimatedCountdownPreview: View {
    @State private var resetProgress: Int = 100

    private var hoursRemaining: Int {
        Int((Double(resetProgress) / 100.0) * 5.0)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Countdown (at 100%)")
                .font(.headline)

            HStack(spacing: 20) {
                CountdownIndicator(
                    resetProgress: resetProgress,
                    size: 44
                )

                VStack(alignment: .leading) {
                    Text("Reset progress: \(resetProgress)%")
                    Text("~\(hoursRemaining)h remaining")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Time passes") {
                    withAnimation {
                        resetProgress = max(0, resetProgress - 20)
                    }
                }
                Button("Reset") {
                    withAnimation {
                        resetProgress = 100
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Normal Usage States") {
    VStack(spacing: 20) {
        Text("Normal Usage (< 100%)")
            .font(.headline)

        // Small size (menu bar)
        HStack(spacing: 10) {
            CircularProgressIndicator(percent: 10, predictedPercent: nil, size: 11, lineWidth: 2.5)
            CircularProgressIndicator(percent: 25, predictedPercent: 40, size: 11, lineWidth: 2.5)
            CircularProgressIndicator(percent: 50, predictedPercent: 75, size: 11, lineWidth: 2.5)
            CircularProgressIndicator(percent: 75, predictedPercent: 90, size: 11, lineWidth: 2.5)
            CircularProgressIndicator(percent: 95, predictedPercent: 100, size: 11, lineWidth: 2.5)
        }

        // Large size for detail
        HStack(spacing: 20) {
            VStack {
                CircularProgressIndicator(percent: 25, predictedPercent: 40, size: 44, lineWidth: 6)
                Text("25%")
                    .font(.caption)
            }
            VStack {
                CircularProgressIndicator(percent: 50, predictedPercent: 75, size: 44, lineWidth: 6)
                Text("50%")
                    .font(.caption)
            }
            VStack {
                CircularProgressIndicator(percent: 75, predictedPercent: 90, size: 44, lineWidth: 6)
                Text("75%")
                    .font(.caption)
            }
        }
    }
    .padding()
    .background(Color.black.opacity(0.1))
}

#Preview("Countdown States (at 100%)") {
    VStack(spacing: 20) {
        Text("Countdown (at 100%, waiting for reset)")
            .font(.headline)

        // Small size (menu bar)
        HStack(spacing: 10) {
            CountdownIndicator(resetProgress: 100, size: 11)
            CountdownIndicator(resetProgress: 75, size: 11)
            CountdownIndicator(resetProgress: 50, size: 11)
            CountdownIndicator(resetProgress: 25, size: 11)
            CountdownIndicator(resetProgress: 5, size: 11)
        }

        // Large size with labels
        HStack(spacing: 20) {
            VStack {
                CountdownIndicator(resetProgress: 100, size: 44)
                Text("~5h left")
                    .font(.caption)
            }
            VStack {
                CountdownIndicator(resetProgress: 60, size: 44)
                Text("~3h left")
                    .font(.caption)
            }
            VStack {
                CountdownIndicator(resetProgress: 20, size: 44)
                Text("~1h left")
                    .font(.caption)
            }
            VStack {
                CountdownIndicator(resetProgress: 5, size: 44)
                Text("~15m left")
                    .font(.caption)
            }
        }
    }
    .padding()
    .background(Color.black.opacity(0.1))
}

#Preview("Side by Side Comparison") {
    VStack(spacing: 30) {
        Text("Usage vs Countdown")
            .font(.headline)

        HStack(spacing: 40) {
            VStack {
                Text("Normal Usage")
                    .font(.subheadline)
                CircularProgressIndicator(percent: 75, predictedPercent: 90, size: 44, lineWidth: 6)
                Text("75% used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                Text("At Limit")
                    .font(.subheadline)
                CountdownIndicator(resetProgress: 60, size: 44)
                Text("~3h until reset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        Text("Menu Bar Size")
            .font(.subheadline)

        HStack(spacing: 6) {
            CircularProgressIndicator(percent: 45, predictedPercent: 60, size: 11, lineWidth: 2.5)
            Text("  |  ")
            CountdownIndicator(resetProgress: 40, size: 11)
            Text("  |  ")
            CircularProgressIndicator(percent: 80, predictedPercent: 95, size: 11, lineWidth: 2.5)
        }
        .font(.system(size: 13))
    }
    .padding()
    .background(Color.black.opacity(0.1))
}

#Preview("Animated Usage") {
    AnimatedUsagePreview()
}

#Preview("Animated Countdown") {
    AnimatedCountdownPreview()
}
