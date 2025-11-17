import SwiftUI

/// ViewModifier that adds a logout button to the navigation bar
/// Only shows when user is authenticated
struct LogoutToolbarModifier: ViewModifier {
    @EnvironmentObject var model: AppModel
    @State private var isAuthenticated = false
    @State private var showLogoutAlert = false
    @State private var isLoggingOut = false
    
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isAuthenticated {
                        Button(action: {
                            showLogoutAlert = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.primary)
                        }
                        .disabled(isLoggingOut)
                    }
                }
            }
            .alert("Sign Out", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    Task {
                        await handleLogout()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .task {
                // Check authentication status when view appears
                isAuthenticated = await BackendClient.shared.isAuthenticated
            }
    }
    
    private func handleLogout() async {
        isLoggingOut = true
        defer { isLoggingOut = false }
        
        do {
            try await BackendClient.shared.signOut()
            NSLog("LOGOUT: ✅ Successfully signed out")
            
            // Navigate to setup screen
            await MainActor.run {
                model.navigate(.setup)
            }
        } catch {
            NSLog("LOGOUT: ❌ Error signing out: \(error.localizedDescription)")
            // Note: We still navigate to setup even if logout fails
            // The user can try again or the app will handle auth state on next launch
            await MainActor.run {
                model.navigate(.setup)
            }
        }
    }
}

extension View {
    /// Convenience modifier to add logout button to navigation bar
    func withLogoutButton() -> some View {
        modifier(LogoutToolbarModifier())
    }
}

