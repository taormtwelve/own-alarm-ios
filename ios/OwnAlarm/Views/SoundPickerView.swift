import AVFoundation
import SwiftUI
import UIKit

/// The per-alarm sound sheet: the tone list — tapping one picks it and plays a short
/// preview as media, so it can be recognised — and a way to hear it at exactly the
/// level this alarm is set to, by ringing the real alarm a few seconds from now.
struct SoundPickerView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var t

    @Binding var alarm: Alarm

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: t("Alarm tones"))

                    VStack(spacing: 8) {
                        ForEach(store.tones) { tone in
                            ToneRow(tone: tone,
                                    isSelected: tone.id == alarm.toneID,
                                    isPlaying: player.previewingToneID == tone.id) {
                                alarm.toneID = tone.id
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
            .navigationTitle(t("Sound & loudness"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                TestRingButton(alarm: alarm)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done")) { dismiss() }
                        .fontWeight(.bold)
                }
            }
            // Previews only: a ringing alarm is not stopped by leaving here.
            .onDisappear { player.stopPreview() }
        }
    }
}

// MARK: - Tone row

struct ToneRow: View {
    let tone: AlarmTone
    let isSelected: Bool
    var isPlaying = false
    let select: () -> Void
    @Environment(\.appLanguage) private var t

    var body: some View {
        Button(action: select) {
            HStack(spacing: 13) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill"
                      : tone.source == .imported ? "music.note" : "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Tokens.inkOnAccent : Tokens.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? Tokens.accentFill : Tokens.track)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // Decorative: the name says it all to VoiceOver.
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tone.name(in: t))
                        .font(Typo.rowValue)
                        .foregroundStyle(Tokens.textPrimary)
                    Text(tone.character(in: t))
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
    /// A song just imported that is longer than an alarm sound may be.
    @State private var trimmedName: String?
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.appLanguage) private var t

    private static let limit = Int(ScaledSound.maxSeconds)

    var body: some View {
        importTile
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    importTone(from: url)
                }
            }
            // iOS caps alarm sounds at 30 s; a longer song rings from its start and
            // stops there, which is better said now than discovered at 6 a.m.
            .alert(t("Only the first {0} seconds will ring", Self.limit),
                   isPresented: Binding(get: { trimmedName != nil },
                                        set: { if !$0 { trimmedName = nil } })) {
                Button(t("OK")) {}
            } message: {
                Text(t("{0} is longer than iOS allows for an alarm sound. It plays from the start and stops at {1} seconds.",
                       trimmedName ?? t("This song"), Self.limit))
            }
    }

    private var importTile: some View {
        SourceTile(systemImage: "plus", title: t("Music or Files")) {
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

        let seconds = (try? AVAudioFile(forReading: destination))
            .map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        let tooLong = seconds > ScaledSound.maxSeconds
        let name = url.deletingPathExtension().lastPathComponent
        store.addImportedTone(
            AlarmTone(
                id: url.lastPathComponent,
                name: name,
                // Said on the row too, so the cut is never a surprise later. Saved in
                // English, shown in the app's language (`AlarmTone.character(in:)`).
                character: tooLong
                    ? AppLanguage.english.callAsFunction("Yours · first {0} s rings", Self.limit)
                    : "Yours",
                peak: 2,
                fileName: url.lastPathComponent,
                source: .imported
            )
        )
        if tooLong { trimmedName = name }
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
