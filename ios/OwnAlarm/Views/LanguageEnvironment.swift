import SwiftUI

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .english
}

extension EnvironmentValues {
    /// The language every screen is written in, from Settings. Set once, at the root,
    /// so tabs, sheets and the ringing screen all read it:
    /// `@Environment(\.appLanguage) private var t`, then `Text(t("Save"))`.
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}
