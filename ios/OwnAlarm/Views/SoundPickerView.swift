import SwiftUI
import UIKit

/// The per-alarm sound sheet: fade-in curve on top, tone list beneath, and a way
/// to hear the tone at exactly the level this alarm is set to.
struct SoundPickerView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer
    @Environment(\.dismiss) private var dismiss

    @Binding var alarm: Alarm

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if alarm.fadeInSeconds > 0 {
                        FadeCurveCard(alarm: alarm)
                    }

                    SectionLabel(text: "Alarm tones")

                    VStack(spacing: 8) {
                        ForEach(store.tones) { tone in
                            ToneRow(
                                tone: tone,
                                isSelected: tone.id == alarm.toneID,
                                isPlaying: player.playingToneID == tone.id
                            ) {
                                alarm.toneID = tone.id
                                player.preview(tone, at: alarm.volume)
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
            .navigationTitle("Sound & loudness")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Hear it at \(alarm.volumePercent)%", systemImage: "speaker.wave.3.fill") {
                    player.preview(store.tone(for: alarm), at: alarm.volume)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        player.stop()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            // Previews only: a ringing alarm's cover also makes this disappear.
            .onDisappear { player.stopPreviews() }
        }
        // A sheet sits over the root's volume view; host our own.
        .hostsSystemVolume()
    }
}

// MARK: - Fade curve

private struct FadeCurveCard: View {
    let alarm: Alarm

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fade-in curve")
                    .font(Typo.body(13, relativeTo: .footnote, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                Spacer()
                Text("\(Int(alarm.startingVolume * 100))% → \(alarm.volumePercent)% over \(alarm.fadeInSeconds)s")
                    .font(Typo.caption)
                    .foregroundStyle(Tokens.textMuted)
            }

            FadeCurve(startFraction: Alarm.fadeInFloor)
                .frame(height: 68)
                .accessibilityLabel("Volume rises from \(Int(alarm.startingVolume * 100)) to \(alarm.volumePercent) percent over \(alarm.fadeInSeconds) seconds")

            HStack {
                Text("0s")
                Spacer()
                Text("\(alarm.fadeInSeconds / 2)s")
                Spacer()
                Text("\(alarm.fadeInSeconds)s")
            }
            .font(Typo.caption)
            .foregroundStyle(Tokens.textFaint)
        }
        .padding(16)
        .cardSurface()
    }
}

private struct FadeCurve: View {
    let startFraction: Double

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                area(in: size)
                    .fill(Tokens.accentFill.opacity(0.18))
                line(in: size)
                    .stroke(Tokens.accentText, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Circle()
                    .fill(Tokens.accentText)
                    .frame(width: 9, height: 9)
                    .position(endPoint(in: size))
            }
        }
    }

    private func startPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: 0, y: size.height * (1 - startFraction))
    }

    private func endPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width, y: size.height * 0.08)
    }

    private func line(in size: CGSize) -> Path {
        var path = Path()
        let start = startPoint(in: size)
        path.move(to: start)
        path.addCurve(
            to: endPoint(in: size),
            control1: CGPoint(x: size.width * 0.42, y: start.y),
            control2: CGPoint(x: size.width * 0.62, y: size.height * 0.18)
        )
        return path
    }

    private func area(in size: CGSize) -> Path {
        var path = line(in: size)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tone row

struct ToneRow: View {
    let tone: AlarmTone
    let isSelected: Bool
    let isPlaying: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 13) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Tokens.inkOnAccent : Tokens.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? Tokens.accentFill : Tokens.track)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // Decorative: without this VoiceOver reads "Play" before every name.
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tone.name)
                        .font(Typo.rowValue)
                        .foregroundStyle(Tokens.textPrimary)
                    Text(tone.character)
                        .font(Typo.caption)
                        .foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    // The selected trait below says this already.
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Tokens.accentText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: Metrics.minTapTarget + 14)
            .cardSurface(radius: Metrics.innerRadius, tinted: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("tone.\(tone.id)")
    }
}

// MARK: - Other sources

/// Adds the reader's own audio from Music or Files.
struct SourceChoices: View {
    @State private var showingImporter = false
    @EnvironmentObject private var store: AlarmStore

    var body: some View {
        importTile.fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                importTone(from: url)
            }
        }
    }

    private var importTile: some View {
        SourceTile(systemImage: "plus", title: "Music or Files") {
            showingImporter = true
        }
    }

    private func importTone(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let folder = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tones", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let destination = folder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { return }

        store.addImportedTone(
            AlarmTone(
                id: url.lastPathComponent,
                name: url.deletingPathExtension().lastPathComponent,
                character: "Yours",
                peak: 2,
                fileName: url.lastPathComponent,
                source: .imported
            )
        )
    }
}

private struct SourceTile: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(Typo.body(13, relativeTo: .footnote, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Tokens.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 62)
            .padding(8)
            .background(Tokens.card)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
                    .strokeBorder(Tokens.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}
