import SwiftUI

/// Top-of-screen progress for optional single-domain model updates (Speech / Writing).
struct ModelUpdateProgressBanner: View {
    let domain: ModelUpdateDomain
    let progress: Double
    let detail: String
    let error: String?

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: error == nil ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(error == nil ? Color.blue : Color.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(error == nil ? "Updating \(domain.displayName)" : "Update paused")
                        .font(.subheadline.weight(.semibold))
                    Text(error ?? detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if error == nil {
                    Text(clampedProgress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if error == nil {
                ProgressView(value: clampedProgress)
                    .tint(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Updating \(domain.displayName)")
        .accessibilityValue(error ?? detail)
    }
}
