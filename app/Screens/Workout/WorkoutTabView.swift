import SwiftUI

/// Entry point of the Workout tab. Waits for the injected services so the view model can take them in its initializer.
struct WorkoutTabView: View {
    @EnvironmentObject private var services: Services

    var body: some View {
        WorkoutDayScreen(services: services)
    }
}

struct WorkoutExerciseRoute: Hashable {
    let exerciseId: Int
    let dayId: Int
}
