import SwiftUI

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

            // Predicted progress arc (ghost/shadow, dashed)
            if predictedProgress > 0 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: predictedProgress)
                    .stroke(
                        Color.primary.opacity(0.8),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0, 4])
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
