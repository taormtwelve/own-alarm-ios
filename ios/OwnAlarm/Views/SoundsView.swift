import SwiftUI

/// The Sounds tab: the tone library — tap a tone to hear it as media — and a place to
/// hear it at a chosen level before you trust it to wake you, by ringing the real
/// alarm a few seconds from now.
struct SoundsView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer
    @Environment(\.appLanguage) private var t

    @State private var testLevel: Double = 0.5
    @State private var testToneID: String = AlarmTone.bundled.first?.id ?? "siren"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    testCard
                    SectionLabel(text: t("All tones"))

                    VStack(spacing: 8) {
                        ForEach(store.tones) { tone in
                            LibraryRow(
                                tone: tone,
                                usage: store.usageCount(of: tone),
                                isSelected: tone.id == testToneID,
                                isPlaying: player.previewingToneID == tone.id
                            ) {
                                testToneID = tone.id
                                player.preview(tone)
                            }
                        }
                        SourceChoices()
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .readableWidth()
            }
            .background(Tokens.background)
            .navigationTitle(t("Sounds"))
            // Previews only: a ringing alarm is not stopped by leaving here.
            .onDisappear { player.stopPreview() }
        }
    }

    private var testAlarm: Alarm {
        Self.testAlarm(tone: AlarmTone.tone(id: testToneID, in: store.tones), level: testLevel, language: t)
    }

    /// A stand-in alarm carrying the tone and level chosen here — all a test ring
    /// needs; it is never saved. Named after its tone, so it rings as "Test · Siren".
    /// This tab tries a sound and nothing else, so its test ring never vibrates; the
    /// editor's vibrates only when that alarm's Vibrate switch is on.
    static func testAlarm(tone: AlarmTone, level: Double, language: AppLanguage) -> Alarm {
        Alarm(task: tone.name(in: language), hour: 0, minute: 0, repeatDays: [],
              volume: level, overridesSilent: true, toneID: tone.id, vibrates: false)
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("Try it for real"))
                    .font(Typo.sectionLabel)
                    .tracking(1.1)
                    .foregroundStyle(Tokens.accentLabel)
                Text(t("Tap a tone below to hear it · set a level and it rings in {0} s as a real alarm. The maximum volume depends on your Ringer & Alerts volume — adjust it in Settings › Sounds & Haptics.",
                       Int(AlarmStore.testLead)))
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VolumeSlider(volume: $testLevel)

            HStack {
                Text(t("Test level"))
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textMuted)
                Spacer()
                Text("\(Int((testLevel * 100).rounded()))%")
                    .font(Typo.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.accentText)
            }

            TestRingButton(alarm: testAlarm)
        }
        .padding(16)
        .cardSurface(radius: Metrics.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Tokens.accentBorder, lineWidth: 1)
        )
    }
}

// MARK: - Library row

private struct LibraryRow: View {
    let tone: AlarmTone
    let usage: Int
    let isSelected: Bool
    let isPlaying: Bool
    let select: () -> Void
    @Environment(\.appLanguage) private var t

    var body: some View {
        Button(action: select) {
            HStack(spacing: 13) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill"
                      : tone.source == .imported ? "music.note" : "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Tokens.inkOnAccent : Tokens.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Tokens.accentFill : Tokens.track)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    // Decorative: the name says it all to VoiceOver.
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tone.name(in: t))
                        .font(Typo.rowValue)
                        .foregroundStyle(Tokens.textPrimary)
                    Text(usageText)
                        .font(Typo.caption)
                        .foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PeakMeter(peak: tone.peak)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: Metrics.minTapTarget + 18)
            .cardSurface(radius: 18, tinted: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var usageText: String {
        let character = tone.character(in: t)
        switch usage {
        case 0: return t("{0} · not used yet", character)
        case 1: return t("{0} · used by 1 alarm", character)
        default: return t("{0} · used by {1} alarms", character, usage)
        }
    }
}

/// Three bars showing how loud the recording itself is, independent of the volume
/// setting — two tones at 60% do not land the same.
private struct PeakMeter: View {
    let peak: Int

    @Environment(\.appLanguage) private var t
    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 3 * unit) {
            ForEach(1...3, id: \.self) { level in
                Capsule()
                    .fill(level <= peak ? Tokens.accentFill : Tokens.track)
                    .frame(width: 4 * unit, height: CGFloat(4 + level * 4) * unit)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Recording loudness {0} of 3", peak))
    }
}
