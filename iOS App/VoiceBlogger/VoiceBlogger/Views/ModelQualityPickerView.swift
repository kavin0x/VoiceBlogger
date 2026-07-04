import SwiftUI

struct ModelQualityPickerView: View {
    @Binding var selection: ModelQualityLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose quality")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(ModelQualityLevel.allCases, id: \.self) { level in
                    QualityOptionRow(
                        level: level,
                        isSelected: selection == level,
                        isRecommended: level == ModelQualityLevel.recommended
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = level
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QualityOptionRow: View {
    let level: ModelQualityLevel
    let isSelected: Bool
    let isRecommended: Bool
    let onSelect: () -> Void

    private var rowFill: Color {
        isSelected ? Color.blue.opacity(0.08) : Color(.secondarySystemFill)
    }

    private var rowBorder: Color {
        isSelected ? Color.blue.opacity(0.5) : .clear
    }

    var body: some View {
        Button(action: onSelect) {
            rowContent
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(rowFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(rowBorder, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.displayName), \(level.tagline), \(level.totalDownloadSizeLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                Text(level.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(level.totalDownloadSizeLabel)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(isSelected ? .blue : .secondary)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.35))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(level.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if isRecommended {
                Text("Recommended")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.12), in: Capsule())
            }
        }
    }
}
