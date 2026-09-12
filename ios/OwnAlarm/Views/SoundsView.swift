import SwiftUI

/// The Sounds tab: the tone library, and a place to hear a tone at a chosen level
/// before you trust it to wake you.
struct SoundsView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer

    @State private var testLevel: Double = 0.6
    @State private var testToneID: String = AlarmTone.bundled.first?.id ?? "siren"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    auditionCard
                    SectionLabel(text: "All tones")

                    VStack(spacing: 8) {
                        ForEach(store.tones) { tone in
                            LibraryRow(
                                tone: tone,
                                usage: store.usageCount(of: tone),
                                isPlaying: player.playingToneID == tone.id
                            ) {
                                testToneID = tone.id
                                player.preview(tone, at: testLevel)
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
            .navigationTitle("Sounds")
            .onDisappear { player.stop() }
        }
    }

    private var auditionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Try it in this room")
                        .font(Typo.sectionLabel)
                        .tracking(1.1)
                        .foregroundStyle(Tokens.accentLabel)
                    Text("Plays through the alarm channel, not the media one")
                        .font(Typo.caption)
                        .foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    let tone = AlarmTone.tone(id: testToneID, in: store.tones)
                    if player.playingToneID == nil {
                        player.preview(tone, at: testLevel)
                    } else {
                        player.stop()
                    }
                } label: {
                    Image(systemName: player.playingToneID == nil ? "play.fill" : "stop.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Tokens.inkOnAccent)
                        .frame(width: 46, height: 46)
                        .background(Tokens.accentFill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.playingToneID == nil ? "Play test tone" : "Stop test tone")
            }

            VolumeSlider(volume: $testLevel)

            HStack {
                Text("Test level")
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textMuted)
                Spacer()
                Text("\(Int((testLevel * 100).rounded()))%")
                    .font(Typo.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.accentText)
            }
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
    let isPlaying: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 13) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Tokens.track)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(tone.name)
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
            .cardSurface(radius: 18)
        }
        .buttonStyle(.plain)
    }

    private var usageText: String {
        let character = tone.character
        switch usage {
        case 0: return "\(character) · not used yet"
        case 1: return "\(character) · used by 1 alarm"
        default: return "\(character) · used by \(usage) alarms"
        }
    }
}

/// Three bars showing how loud the recording itself is, independent of the volume
/// setting — two tones at 60% do not land the same.
private struct PeakMeter: View {
    let peak: Int

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
        .accessibilityLabel("Recording loudness \(peak) of 3")
    }
}
