import SwiftUI

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
            CountdownIndicator(resetProgress: 40, size: 11)
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

#Preview("Overlaid Indicators") {
    VStack(spacing: 20) {
        Text("Normal + Reset Time (Overlaid)")
            .font(.headline)

        // Menu bar size examples
        HStack(spacing: 10) {
            StateIndicator(
                state: UsageState(
                    id: "1",
                    percent: 25,
                    predictedPercent: 40,
                    resetDate: Date().addingTimeInterval(4 * 60 * 60), // 4h remaining
                    status: .success
                ),
                circleSize: 16,
                lineWidth: 3
            )
            StateIndicator(
                state: UsageState(
                    id: "2",
                    percent: 50,
                    predictedPercent: 70,
                    resetDate: Date().addingTimeInterval(3 * 60 * 60), // 3h remaining
                    status: .success
                ),
                circleSize: 16,
                lineWidth: 3
            )
            StateIndicator(
                state: UsageState(
                    id: "3",
                    percent: 75,
                    predictedPercent: 90,
                    resetDate: Date().addingTimeInterval(2 * 60 * 60), // 2h remaining
                    status: .success
                ),
                circleSize: 16,
                lineWidth: 3
            )
            StateIndicator(
                state: UsageState(
                    id: "4",
                    percent: 95,
                    predictedPercent: nil,
                    resetDate: Date().addingTimeInterval(1 * 60 * 60), // 1h remaining
                    status: .success
                ),
                circleSize: 16,
                lineWidth: 3
            )
        }

        Divider()

        Text("Comparison: With vs Without Reset Time")
            .font(.headline)

        HStack(spacing: 40) {
            VStack {
                Text("With Reset Time")
                    .font(.subheadline)
                StateIndicator(
                    state: UsageState(
                        id: "5",
                        percent: 60,
                        predictedPercent: 75,
                        resetDate: Date().addingTimeInterval(2.5 * 60 * 60), // 2.5h remaining
                        status: .success
                    ),
                    circleSize: 16,
                    lineWidth: 3
                )
            }

            VStack {
                Text("Without Reset Time")
                    .font(.subheadline)
                StateIndicator(
                    state: UsageState(
                        id: "6",
                        percent: 60,
                        predictedPercent: 75,
                        resetDate: nil,
                        status: .success
                    ),
                    circleSize: 16,
                    lineWidth: 3
                )
            }
        }
    }
    .padding()
    .background(Color.black.opacity(0.1))
}
