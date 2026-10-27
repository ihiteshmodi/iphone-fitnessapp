import SwiftUI
import UIKit

@main
struct FitnessApp: App {
    @StateObject private var session = AppSession()

    init() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Theme.card)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navigationBar = UINavigationBarAppearance()
        navigationBar.configureWithOpaqueBackground()
        navigationBar.backgroundColor = UIColor(Theme.background)
        navigationBar.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        navigationBar.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = navigationBar
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView().tint(Theme.green)
            case .needsImport:
                ImportDatabaseView()
            case .failed(let message):
                VStack(spacing: 12) {
                    Text("Something went wrong").font(.headline).foregroundColor(Theme.text)
                    Text(message).font(.footnote).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                    Button("Try again") { session.recheck() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.green)
                }
                .padding()
            case .ready:
                if let services = session.services {
                    MainTabs().environmentObject(services)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .task { session.start() }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            WorkoutTabView()
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
            BodyTabView()
                .tabItem { Label("Body", systemImage: "scalemass.fill") }
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            MoreTabView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
    }
}
