import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    var color: Color = .blue

    var body: some View {
        // Canvas draws a single Core Graphics pass instead of 30 individual SwiftUI
        // shape views — avoids the GeometryReader layout overhead and per-bar view
        // allocation that previously ran 20× per second during recording.
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(count - 1)
            let barWidth = max(2, (size.width - totalSpacing) / CGFloat(count))
            let minHeight: CGFloat = 4

            for i in 0..<count {
                let clamped = Double(max(-60, min(0, levels[i])))
                let normalized = CGFloat((clamped + 60.0) / 60.0)
                let barHeight = minHeight + normalized * (size.height - minHeight)
                let x = CGFloat(i) * (barWidth + spacing)
                let y = (size.height - barHeight) / 2
                let path = Path(
                    roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                    cornerRadius: 2
                )
                context.fill(path, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    WaveformView(levels: (0..<30).map { _ in Float.random(in: -50...0) })
        .frame(height: 60)
        .padding()
}
