import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer
    @State private var tab: Tab = .alarms

    /// Read from the store: the environment value is set by this view, below, so it
    /// is not visible here.
    private var t: AppLanguage { store.settings.language }

    private enum Tab: Hashable {
        case alarms, sounds, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            AlarmListView()
                .tabItem { Label(t("Alarms"), systemImage: "alarm") }
                .tag(Tab.alarms)

            SoundsView()
                .tabItem { Label(t("Sounds"), systemImage: "waveform") }
                .tag(Tab.sounds)

            SettingsView()
                .tabItem { Label(t("Settings"), systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Tokens.accentText)
        // Changing tab ends a preview at once. A tab is not reliably told it has
        // disappeared the moment you leave it, so this does not wait to be told.
        .onChange(of: tab) { _ in player.stopPreview() }
        // A test ring that came due with the app open rings here, as a real alarm
        // would inside the app — unless a real one is ringing already.
        .onChange(of: store.testRingingInApp?.id) { _ in
            guard store.ringing == nil else { return }
            if let test = store.testRingingInApp {
                player.startRinging(test, tone: store.tone(for: test))
            } else {
                player.stop()
            }
        }
        // The theme preference wins over the system setting; `.automatic` returns
        // nil, which hands control back to iOS.
        .preferredColorScheme(store.settings.theme.colorScheme)
        // An alarm takes the whole screen — it is not something to dismiss by
        // accident, so it is a cover rather than a sheet.
        .fullScreenCover(item: $store.ringing) { alarm in
            RingingView(alarm: alarm)
        }
        // Lets the app set the phone's volume while an alarm rings, without the HUD.
        .hostsSystemVolume()
        // Last, so everything above — tabs, their sheets, the ringing cover — speaks it.
        .environment(\.appLanguage, t)
    }
}
