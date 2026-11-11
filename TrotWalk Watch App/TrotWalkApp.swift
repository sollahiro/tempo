import SwiftUI

@main
struct TrotWalkWatchApp: App {
    @State private var workout = WorkoutManager()
    @State private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(workout)
                .environment(settings)
        }
    }
}

struct RootView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        switch workout.state {
        case .idle:
            StartView()
        case .preparing:
            ProgressView("準備中")
        case .running, .paused, .ending:
            WorkoutView()
        case .finished:
            SummaryView()
        }
    }
}
