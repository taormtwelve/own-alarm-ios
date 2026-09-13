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
        // Whole percents, but not via `step:` — on iOS 26 a stepped slider draws a
        // tick for every step, and a hundred of them read as a dotted line under
        // the bar. The rounding happens in the binding instead.
        Slider(value: Binding(get: { volume },
                              set: { volume = ($0 * 100).rounded() / 100 }),
               in: 0...1) {
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

// MARK: - Slide to stop

/// A track you drag across to stop an alarm — a stray tap cannot trigger it. It only
/// counts once the knob is most of the way across; short of that it springs back.
/// VoiceOver cannot drag, so to VoiceOver it is one button that stops on activate.
struct SlideToStop: View {
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let knob: CGFloat = 56
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let travel = max(0, geo.size.width - knob - inset * 2)
            let progress = travel > 0 ? offset / travel : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Tokens.accentSurface)
                    .overlay(Capsule().strokeBorder(Tokens.accentBorder, lineWidth: 1))

                Text("Slide to stop")
                    .font(Typo.body(16, relativeTo: .headline, weight: .semibold))
                    .foregroundStyle(Tokens.accentText)
                    .frame(maxWidth: .infinity)
                    .opacity(1 - Double(progress))

                Circle()
                    .fill(Tokens.accentFill)
                    .overlay(
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Tokens.inkOnAccent)
                    )
                    .frame(width: knob, height: knob)
                    .offset(x: inset + offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !completed else { return }
                                offset = min(max(0, value.translation.width), travel)
                            }
                            .onEnded { _ in
                                guard !completed else { return }
                                if Self.completes(offset: offset, travel: travel) {
                                    completed = true
                                    offset = travel
                                    action()
                                } else {
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                                        offset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .frame(height: knob + inset * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stop alarm")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityIdentifier("slideToStop")
    }

    /// Past 85% of the way across counts as a deliberate stop.
    static func completes(offset: CGFloat, travel: CGFloat) -> Bool {
        travel > 0 && offset >= travel * 0.85
    }
}
