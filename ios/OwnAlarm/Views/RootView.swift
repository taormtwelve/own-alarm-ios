import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AlarmStore

    var body: some View {
        TabView {
            AlarmListView()
                .tabItem { Label("Alarms", systemImage: "alarm") }

            SoundsView()
                .tabItem { Label("Sounds", systemImage: "waveform") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
        // Lets the app set the device volume (100% = maximum) without the HUD.
        .hostsSystemVolume()
    }
}
