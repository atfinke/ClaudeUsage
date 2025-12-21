import SwiftUI

// MARK: - Usage Menu View

struct UsageMenuView: View {
    let state: UsageState
    let accountName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Account name
            Text(accountName ?? state.id)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            // Usage info
            switch state.status {
            case .loading:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            case .success:
                VStack(alignment: .leading, spacing: 2) {
                    // Usage percentage
                    HStack(spacing: 4) {
                        Circle()
                            .fill(usageColor)
                            .frame(width: 8, height: 8)
                        Text("Usage: \(state.percent)%")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // Time to full (if available)
                    if let timeToFull = state.timeToFull {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                            Text("Full in: \(timeToFull)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Time until reset
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                            .foregroundStyle(.blue)
                        Text("Resets in: \(state.timeUntilReset)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            case .error:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(state.error ?? "Unknown error")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(width: 200, alignment: .leading)
    }

    private var usageColor: Color {
        let percent = state.percent
        if percent < 50 {
            return .green
        } else if percent < 80 {
            return .orange
        } else {
            return .red
        }
    }
}
