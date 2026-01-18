import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false

    func completeAuthentication() {
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
    }
}
