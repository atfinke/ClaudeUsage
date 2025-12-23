import SwiftUI

// MARK: - Countdown Indicator (Time until reset)

struct CountdownIndicator: View {
    let resetProgress: Int // 100 = just started reset window, 0 = about to reset
    let size: CGFloat

    private var countdownProgress: CGFloat {
        CGFloat(resetProgress) / 100.0
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.primary.opacity(0.2))

            // Filled pie wedge (shrinks as reset approaches)
            PieSlice(progress: countdownProgress)
                .fill(Color.primary.opacity(0.5))
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
