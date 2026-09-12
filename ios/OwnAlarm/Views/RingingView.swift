import SwiftUI

/// The in-app ringing presentation. The ring around the task name *is* the volume
/// level, so what you see matches what you hear.
struct RingingView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let alarm: Alarm

    @State private var pulse = false

    private var tone: AlarmTone { store.tone(for: alarm) }

    var body: some View {
        ZStack {
            Tokens.ringingBackground(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)

                // On a short phone or at large text the ring is dropped in favour of
                // the plain stack — the alarm still reads, it just loses the flourish.
                ViewThatFits(in: .vertical) {
                    ringDial
                    plainDial
                }

                Spacer(minLength: 16)
                levelPill
                Spacer(minLength: 24)
                actions
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .readableWidth()
        }
        .onAppear {
            player.startRinging(alarm, tone: tone)
            if !reduceMotion { pulse = true }
        }
        .onDisappear { player.stop() }
        // A full-screen cover leaves the root's volume view off screen; host our own.
        .hostsSystemVolume()
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Tokens.accentFill)
                .frame(width: 7, height: 7)
            Text("Alarm ringing")
                .font(Typo.sectionLabel)
                .tracking(1.6)
                .foregroundStyle(Tokens.accentLabel)
        }
    }

    private var ringDial: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .strokeBorder(Tokens.accentFill, lineWidth: 1)
                    .scaleEffect(pulse ? 1.12 : 0.94)
                    .opacity(pulse ? 0 : 0.55)
                    .animation(.easeOut(duration: 2.6).repeatForever(autoreverses: false), value: pulse)
            }

            Circle()
                .stroke(Tokens.track, lineWidth: 10)

            Circle()
                .trim(from: 0, to: alarm.volume)
                .stroke(Tokens.accentFill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            dialContents
                .padding(46)
        }
        .frame(width: 288, height: 288)
        // The dial is decorative scaffolding around text that must stay readable,
        // so it stops growing before it can push its own contents out.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var plainDial: some View {
        dialContents.padding(.vertical, 24)
    }

    private var dialContents: some View {
        VStack(spacing: 10) {
            Text(TimeText.string(hour: alarm.hour, minute: alarm.minute,
                                 format: store.settings.timeFormat))
                .font(Typo.body(17, relativeTo: .headline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.accentLabel)

            Text(alarm.task)
                .font(Typo.display(30, relativeTo: .title))
                .foregroundStyle(Tokens.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var levelPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tokens.accentText)
            Text("\(alarm.volumePercent)%")
                .font(Typo.body(14, relativeTo: .subheadline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.accentText)
            Circle().fill(Tokens.textFaint.opacity(0.6)).frame(width: 3, height: 3)
            Text(alarm.fadeInSeconds > 0 ? "\(tone.name), rising" : "\(tone.name), at full task volume")
                .font(Typo.caption)
                .foregroundStyle(Tokens.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Tokens.accentSurface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.accentBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 14) {
            PrimaryButton(title: "Stop", systemImage: "stop.fill") {
                player.stop()
                store.stop(alarm)
            }

            if alarm.snoozeMinutes > 0 {
                SecondaryButton(
                    title: "Snooze \(alarm.snoozeMinutes) min",
                    detail: alarm.louderAfterSnooze
                        ? "returns at \(min(100, alarm.volumePercent + 10))%"
                        : nil
                ) {
                    player.stop()
                    store.snooze(alarm)
                }
            }
        }
    }
}
