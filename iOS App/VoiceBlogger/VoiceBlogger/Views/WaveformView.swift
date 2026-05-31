import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    var color: Color = .blue

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<levels.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(
                            width: max(2, (geo.size.width - CGFloat(levels.count - 1) * 3) / CGFloat(levels.count)),
                            height: barHeight(level: levels[i], maxHeight: geo.size.height)
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(level: Float, maxHeight: CGFloat) -> CGFloat {
        // level is in dBFS: -60 (silence) to 0 (full scale)
        let clamped = max(-60, min(0, level))
        let normalized = CGFloat((clamped + 60) / 60)  // 0…1
        let minHeight: CGFloat = 4
        return minHeight + normalized * (maxHeight - minHeight)
    }
}

#Preview {
    WaveformView(levels: (0..<30).map { _ in Float.random(in: -50...0) })
        .frame(height: 60)
        .padding()
}
