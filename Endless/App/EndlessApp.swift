import SwiftUI

@main
struct EndlessApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Auth state handled via direct service calls only
        // No async observers or notification loops
    }

    var body: some Scene {
        WindowGroup {
            if appState.isAuthenticated {
                ContentView()
                    .environmentObject(appState)
            } else {
                AuthenticationView()
                    .environmentObject(appState)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            Text("Welcome to Endless")
            Button("Sign Out") {
                appState.signOut()
            }
        }
    }
}
