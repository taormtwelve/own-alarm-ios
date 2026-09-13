import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// The iPhone's media volume, while an alarm rings inside the app.
///
/// An in-app alarm plays as media, so the phone's volume is set to the alarm's level
/// for as long as it rings. The volume you had is remembered first and put back the
/// moment it stops. It is also saved to disk, so if the app is closed mid-way the
/// next launch puts it back instead of leaving the phone at 90%. Previews do not come
/// here: they play at the Ringer & Alerts volume, like the real alarm (`AlarmPlayer`).
///
/// iOS has no public setter for system volume. The slider inside `MPVolumeView` is
/// the route alarm apps rely on in practice — undocumented, so treat it as something
/// Apple could change. The view sits in the window (`hostsSystemVolume()`), or iOS
/// may ignore the change and flash its volume HUD over the app.
@MainActor
final class SystemVolume {
    static let shared = SystemVolume()

    private static let originalKey = "ownalarm.systemVolume.original"

    private let defaults: UserDefaults
    private let readLevel: () -> Float
    private let injectedWrite: ((Float) -> Void)?

    private struct Weak { weak var view: MPVolumeView? }
    private var hosted: [Weak] = []
    private lazy var detached = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    /// Tests pass their own reader and writer; the app uses the real device volume.
    init(defaults: UserDefaults = .standard,
         read: (() -> Float)? = nil,
         write: ((Float) -> Void)? = nil) {
        self.defaults = defaults
        self.readLevel = read ?? { AVAudioSession.sharedInstance().outputVolume }
        self.injectedWrite = write
    }

    /// The level the phone is at right now, 0...1.
    var current: Float { readLevel() }

    /// The user's own level, saved while the app has taken the volume over.
    var original: Float? {
        defaults.object(forKey: Self.originalKey) as? Float
    }

    /// Remembers the user's level the first time, then sets ours. Calling it again
    /// while already in charge — every slider movement — keeps the first original.
    func takeOver(at level: Float) {
        if original == nil {
            defaults.set(current, forKey: Self.originalKey)
        }
        set(level)
    }

    /// Puts the user's level back and forgets it. Does nothing if not in charge.
    func restore() {
        guard let original else { return }
        set(original)
        defaults.removeObject(forKey: Self.originalKey)
        // iOS can drop a change that lands straight after another — the last drag
        // step, then this. Check it took, and try once more if not.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.original == nil, abs(self.current - original) > 0.005 else { return }
            self.set(original)
        }
    }

    /// At launch: if the app was closed while it had the volume, put it back.
    func recoverIfNeeded() {
        restore()
    }

    /// Sets the phone's volume, 0...1 of the maximum.
    func set(_ level: Float) {
        let clamped = min(1, max(0, level))
        if let injectedWrite {
            injectedWrite(clamped)
            return
        }
        guard let slider = activeView.subviews.lazy.compactMap({ $0 as? UISlider }).first else { return }
        // Each screen has its own volume view, and one that was off screen can still
        // show an old level. If it already shows this one, the assignment counts as
        // no change and iOS never hears it — so step off it first.
        if abs(slider.value - clamped) < 0.001 {
            slider.value = clamped > 0.5 ? clamped - 0.01 : clamped + 0.01
            slider.sendActions(for: .valueChanged)
        }
        slider.value = clamped
        slider.sendActions(for: .valueChanged)
    }

    // MARK: Hosting

    func attach(_ view: MPVolumeView) {
        hosted.removeAll { $0.view == nil }
        hosted.append(Weak(view: view))
    }

    /// A cover takes its presenter out of the window and a sheet sits over it, so
    /// each hosts its own view, and the most recently attached one still on screen
    /// wins.
    private var activeView: MPVolumeView {
        hosted.compactMap(\.view).last { $0.window != nil } ?? detached
    }
}

/// An invisible `MPVolumeView` for `SystemVolume` to drive.
struct SystemVolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        SystemVolume.shared.attach(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

extension View {
    /// Keeps an invisible volume view in this screen's hierarchy, so the app can set
    /// the phone's volume without the system volume HUD appearing.
    func hostsSystemVolume() -> some View {
        background(
            SystemVolumeHost()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}
