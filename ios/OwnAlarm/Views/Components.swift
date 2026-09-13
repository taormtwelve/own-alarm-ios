import SwiftUI

// MARK: - Volume meter

/// The bar meter used on every alarm row. Scales with Dynamic Type via
/// `@ScaledMetric`, and reports itself to VoiceOver as one value rather than
/// eleven meaningless bars.
struct VolumeMeter: View {
    let volume: Double
    var barCount = 10
    var isDimmed = false

    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 3 * unit) {
            ForEach(0..<barCount, id: \.self) { index in
                let filled = Double(index) / Double(barCount) < volume
                Capsule(style: .continuous)
                    .fill(barColor(filled: filled))
                    .frame(width: 5 * unit, height: height(at: index))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
    }

    private func height(at index: Int) -> CGFloat {
        let ramp = 6 + (Double(index) / Double(barCount - 1)) * 11
        return ramp * unit
    }

    private func barColor(filled: Bool) -> Color {
        guard filled else { return Tokens.track }
        return isDimmed ? Tokens.textFaint : Tokens.accentFill
    }
}

// MARK: - Volume slider

/// A styled slider that keeps the real `Slider` underneath, so keyboard control,
/// VoiceOver's adjustable trait and Switch Control all keep working.
struct VolumeSlider: View {
    @Binding var volume: Double
    /// `true` when a drag starts, `false` when it ends — the hook for playing the
    /// tone live while the level is being set.
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        Slider(value: $volume, in: 0...1, step: 0.01) {
            Text("Alarm volume")
        } onEditingChanged: { editing in
            onEditingChanged(editing)
        }
        .tint(Tokens.accentFill)
        .frame(minHeight: Metrics.minTapTarget)
        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
    }
}

// MARK: - Section header

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Typo.sectionLabel)
            .tracking(1.1)
            .foregroundStyle(Tokens.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Grouped rows

/// A card that groups rows with hairline dividers, matching the Settings design.
struct CardGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .cardSurface()
    }
}

/// One row inside a `CardGroup`. Height floats with Dynamic Type instead of being
/// pinned to 48pt, but never drops below the minimum tap target.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsDivider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typo.rowLabel)
                        .foregroundStyle(Tokens.textSecondary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Typo.caption)
                            .foregroundStyle(Tokens.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: Metrics.rowHeight)
            // The whole row is the target. A plain-style button otherwise only
            // answers taps on its text, so the gap between title and value was dead.
            .contentShape(Rectangle())

            if showsDivider {
                Rectangle()
                    .fill(Tokens.divider)
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }
}

/// Trailing chevron + value, the standard "tap to drill in" affordance.
struct RowValue: View {
    let value: String
    var showsChevron = true

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(Typo.rowValue)
                .foregroundStyle(Tokens.textPrimary)
                .monospacedDigit()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.textFaint)
            }
        }
    }
}

// MARK: - Segmented control

/// Used for Appearance and Time format. Wraps `Picker` so it inherits platform
/// behaviour, accessibility and keyboard support.
struct SegmentedChoice<Value: Hashable & Identifiable>: View {
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minHeight: Metrics.minTapTarget)
    }
}

// MARK: - Toggle style

extension ToggleStyle where Self == SwitchToggleStyle {
    static var alarm: SwitchToggleStyle { SwitchToggleStyle(tint: Tokens.accentFill) }
}

// MARK: - List rows as cards

extension View {
    /// Strips List chrome — separators, row background, default insets — so a row
    /// renders as one of our cards while keeping List behaviour like swipe actions.
    func listCardRow(bottom: CGFloat = 6) -> some View {
        self
            .listRowInsets(EdgeInsets(top: 6, leading: Metrics.gutter,
                                      bottom: bottom, trailing: Metrics.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                }
                Text(title)
                    .font(Typo.body(17, relativeTo: .headline, weight: .bold))
            }
            .foregroundStyle(Tokens.inkOnAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(Tokens.accentFill)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(Typo.body(16, relativeTo: .headline, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                if let detail {
                    Text(detail)
                        .font(Typo.caption)
                        .foregroundStyle(Tokens.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .cardSurface(radius: 20)
        }
        .buttonStyle(.plain)
    }
}
