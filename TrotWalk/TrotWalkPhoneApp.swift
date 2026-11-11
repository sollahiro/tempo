import SwiftUI

@main
struct TrotWalkPhoneApp: App {
    @State private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
    }
}
