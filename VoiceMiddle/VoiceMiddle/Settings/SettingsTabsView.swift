import SwiftUI
import VMCore

/// Root view of the Settings scene. Hosts a `TabView` with one tab per
/// logical section of the app's preferences.
///
/// Each tab is a stand-alone view (see `GeneralTab`, `LanguagesTab`,
/// `TranslationTab`, `AudioTab`, `PrivacyTab`). They receive their own
/// dependencies via plain `let` properties rather than `@EnvironmentObject`
/// so the wiring is explicit and trivially Sendable-safe.
struct SettingsTabsView: View {
    let hudViewModel: HUDViewModel
    let installer: SystemExtensionInstaller
    let settings: SettingsStore

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            LanguagesTab(settings: settings)
                .tabItem { Label("Languages", systemImage: "globe") }

            TranslationTab(settings: settings)
                .tabItem {
                    Label("Translation", systemImage: "text.bubble")
                }

            AudioTab(hudViewModel: hudViewModel)
                .tabItem { Label("Audio", systemImage: "waveform") }

            PrivacyTab(settings: settings)
                .tabItem { Label("Privacy", systemImage: "lock") }
        }
        .frame(minWidth: 720, minHeight: 480)
        .padding(0)
    }
}
