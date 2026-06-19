import SwiftUI

/// A small status dot: green (with a soft glow) when the snippet is running,
/// grey when it's stopped.
struct StatusIndicator: View {
    let isRunning: Bool
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.secondary)
            .frame(width: size, height: size)
            .shadow(color: isRunning ? .green.opacity(0.5) : .clear, radius: 3)
    }
}

#Preview {
    HStack(spacing: 20) {
        StatusIndicator(isRunning: true)
        StatusIndicator(isRunning: false)
        StatusIndicator(isRunning: true, size: 16)
    }
    .padding()
}
