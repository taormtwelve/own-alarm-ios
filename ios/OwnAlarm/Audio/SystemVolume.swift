import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// The device's output level — which is what "100%" means in this app.
///
/// `AVAudioPlayer.volume` is only a fraction of whatever the volume buttons are set
/// to, so on its own "85%" could come out at 40%. Instead, while the app is playing
/// it sets the *device* level to the alarm's percentage and runs the player at full
/// scale on top, then puts the user's own level back when playback ends.
///
/// iOS has no public setter for system volume. The slider inside `MPVolumeView` is
/// the route alarm apps rely on in practice — undocumented, so treat it as something
/// Apple could change. The view must sit in the window (see `hostsSystemVolume()`),
/// or iOS may ignore the change and flash its volume HUD over the app.
@MainActor
final class SystemVolume {
    static let shared = SystemVolume()

    private struct Weak { weak var view: MPVolumeView? }
    private var hosted: [Weak] = []
    private lazy var detached = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private var savedLevel: Float?

    /// The level the volume buttons are at right now, 0...1.
    var current: Float { AVAudioSession.sharedInstance().outputVolume }

    func attach(_ view: MPVolumeView) {
        hosted.removeAll { $0.view == nil }
        hosted.append(Weak(view: view))
    }

    /// Sets the device output level, 0...1 of the maximum.
    func set(_ level: Float) {
        let clamped = min(1, max(0, level))
        guard let slider = activeView.subviews.lazy.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = clamped
        slider.sendActions(for: .valueChanged)
    }

    /// Remembers the user's level the first time it is called, then sets ours.
    func takeOver(at level: Float) {
        if savedLevel == nil { savedLevel = current }
        set(level)
    }

    /// Puts the volume buttons' level back to where the user left it.
    func restore() {
        guard let savedLevel else { return }
        set(savedLevel)
        self.savedLevel = nil
    }

    /// A full-screen cover takes its presenter out of the window, so the most
    /// recently attached view that is still on screen wins.
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
    /// the device level without the system volume HUD appearing.
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
