import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AlarmStore
    @State private var tab: Tab = .alarms

    private enum Tab: Hashable {
        case alarms, sounds, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            AlarmListView()
                .tabItem { Label("Alarms", systemImage: "alarm") }
                .tag(Tab.alarms)

            SoundsView()
                .tabItem { Label("Sounds", systemImage: "waveform") }
                .tag(Tab.sounds)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Tokens.accentText)
        // The theme preference wins over the system setting; `.automatic` returns
        // nil, which hands control back to iOS.
        .preferredColorScheme(store.settings.theme.colorScheme)
        // An alarm takes the whole screen — it is not something to dismiss by
        // accident, so it is a cover rather than a sheet.
        .fullScreenCover(item: $store.ringing) { alarm in
            RingingView(alarm: alarm)
        }
        // Lets the app set the phone's volume while it plays, without the HUD.
        .hostsSystemVolume()
    }
}
