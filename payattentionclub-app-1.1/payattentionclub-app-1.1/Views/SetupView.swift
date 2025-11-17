import SwiftUI
import Foundation
import FamilyControls
import Auth

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAppPicker = false
    @State private var isAuthenticating = false
    @State private var authenticationError: String?
    
    // Convert slider position (0.0-1.0) to penalty value ($0.01-$5.00) with $0.10 in the middle
    private func positionToPenalty(_ position: Double) -> Double {
        let minPenalty = 0.01
        let midPenalty = 0.10
        let maxPenalty = 5.00
        
        if position <= 0.5 {
            // First half: linear from $0.01 to $0.10
            return minPenalty + (midPenalty - minPenalty) * (position / 0.5)
        } else {
            // Second half: logarithmic from $0.10 to $5.00
            let ratio = (position - 0.5) / 0.5 // 0.0 to 1.0
            let logRatio = log(midPenalty / minPenalty) + ratio * log(maxPenalty / midPenalty)
            return minPenalty * exp(logRatio)
        }
    }
    
    // Convert penalty value ($0.01-$5.00) to slider position (0.0-1.0)
    private func penaltyToPosition(_ penalty: Double) -> Double {
        let minPenalty = 0.01
        let midPenalty = 0.10
        let maxPenalty = 5.00
        
        if penalty <= midPenalty {
            // First half: linear from $0.01 to $0.10
            return 0.5 * (penalty - minPenalty) / (midPenalty - minPenalty)
        } else {
            // Second half: logarithmic from $0.10 to $5.00
            let logRatio = log(penalty / minPenalty)
            let totalLogRange = log(maxPenalty / minPenalty)
            let firstHalfLogRange = log(midPenalty / minPenalty)
            return 0.5 + 0.5 * (logRatio - firstHalfLogRange) / (totalLogRange - firstHalfLogRange)
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Countdown
                    VStack(spacing: 8) {
                        Text("Next deadline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let countdownModel = model.countdownModel {
                            CountdownView(model: countdownModel)
                        } else {
                            Text("00:00:00:00")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 20)
                    
                    // Time Limit Slider
                    VStack(alignment: .leading, spacing: 15) {
                        Text(formatDeadlineLabel())
                            .font(.headline)
                        
                        Text(formatTime(model.limitMinutes))
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Slider(
                            value: $model.limitMinutes,
                            in: 30...2520, // 30 minutes to 42 hours (in minutes)
                            step: 15
                        )
                        
                        HStack {
                            Text("30 min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("42 hours")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Testing button to set limit to 1 minute
                        Button(action: {
                            model.limitMinutes = 1.0
                        }) {
                            Text("Set to 1 min (testing)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Penalty Slider
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Penalty per minute over limit")
                            .font(.headline)
                        
                        Text("$\(model.penaltyPerMinute, specifier: "%.2f")")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Slider(
                            value: Binding(
                                get: { penaltyToPosition(model.penaltyPerMinute) },
                                set: { newPosition in
                                    model.penaltyPerMinute = positionToPenalty(newPosition)
                                }
                            ),
                            in: 0.0...1.0,
                            step: 0.001
                        )
                        
                        HStack {
                            Text("$0.01")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("$5.00")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // App Selector
                    Button(action: {
                        showAppPicker = true
                    }) {
                        Label("Select Apps to Limit (\(model.selectedApps.applicationTokens.count + model.selectedApps.categoryTokens.count))", systemImage: "app.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .familyActivityPicker(isPresented: $showAppPicker, selection: $model.selectedApps)
                    
                    // TEMPORARY: Backend Test Button (Remove after testing)
                    Button(action: {
                        model.navigate(.backendTest)
                    }) {
                        Text("🧪 Test Backend (Temporary)")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    
                    // Authentication Error Display
                    if let error = authenticationError {
                        Text("Authentication Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    // Commit Button
                    Button(action: {
                        handleCommit()
                    }) {
                        HStack {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 8)
                            }
                            Text(isAuthenticating ? "Signing in..." : "Commit")
                            .font(.headline)
                            .foregroundColor(.white)
                        }
                            .frame(maxWidth: .infinity)
                            .padding()
                        .background(isAuthenticating ? Color.gray : Color.pink)
                            .cornerRadius(12)
                    }
                    .disabled(isAuthenticating)
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func formatTime(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
    
    private func formatDeadlineLabel() -> String {
        let deadlineEST = nextMondayNoonEST()
        let localDeadline = deadlineEST // Date automatically converts to local timezone when formatted
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm" // 24-hour format: 1400
        formatter.timeZone = TimeZone.current // Use device's local timezone
        
        let timeString = formatter.string(from: localDeadline)
        // Format as "1400h" (add 'h' at the end)
        let formattedTime = "\(timeString)h"
        
        return "Time limit till next Monday \(formattedTime)"
    }
    
    private func nextMondayNoonEST() -> Date {
        let calendar = Calendar.current
        var estCalendar = calendar
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        let now = Date()
        var components = estCalendar.dateComponents([.year, .month, .day, .weekday, .hour], from: now)
        
        // Find next Monday
        if let weekday = components.weekday {
            let daysUntilMonday = (9 - weekday) % 7
            if daysUntilMonday == 0 && (components.hour ?? 0) < 12 {
                // Today is Monday and before noon, use today
                components.hour = 12
                components.minute = 0
                components.second = 0
            } else {
                // Find next Monday
                let daysToAdd = daysUntilMonday == 0 ? 7 : daysUntilMonday
                components.day = (components.day ?? 0) + daysToAdd
                components.hour = 12
                components.minute = 0
                components.second = 0
            }
        }
        
        return estCalendar.date(from: components) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
    }
    
    private func handleCommit() {
        model.savePersistedValues()
        authenticationError = nil
        
        // Start preparing thresholds asynchronously (non-blocking)
        // This happens in background while user goes through authentication and ScreenTime access
        if #available(iOS 16.0, *) {
            Task {
                await MonitoringManager.shared.prepareThresholds(
                    selection: model.selectedApps,
                    limitMinutes: Int(model.limitMinutes)
                )
            }
        }
        
        // Handle authentication and navigation
        Task { @MainActor in
            await ensureAuthenticatedAndNavigate()
        }
    }
    
    private func ensureAuthenticatedAndNavigate() async {
        // Check if already authenticated
        let isAuth = await BackendClient.shared.isAuthenticated
        
        if !isAuth {
            // Need to sign in with Apple
            isAuthenticating = true
            NSLog("AUTH SetupView: Starting Sign in with Apple")
            
            do {
                let session = try await AuthenticationManager.shared.signInWithApple()
                NSLog("AUTH SetupView: ✅ Successfully authenticated: \(session.user.id)")
                isAuthenticating = false
                
                // Continue with navigation after successful authentication
                await navigateToNextScreen()
            } catch {
                NSLog("AUTH SetupView: ❌ Authentication failed: \(error.localizedDescription)")
                isAuthenticating = false
                authenticationError = error.localizedDescription
            }
        } else {
            NSLog("AUTH SetupView: Already authenticated, proceeding")
            await navigateToNextScreen()
        }
    }
    
    private func navigateToNextScreen() async {
        // Navigate to next screen based on ScreenTime authorization status
        let authorizationCenter = AuthorizationCenter.shared
        let status = authorizationCenter.authorizationStatus
        NSLog("MARKERS SetupView: Authorization status: %@", String(describing: status))
        print("MARKERS SetupView: Authorization status: \(status)")
        fflush(stdout)
        
        if status == .approved {
            // Skip ScreenTime access view, go directly to authorization
            NSLog("MARKERS SetupView: ScreenTime already approved, skipping to authorization")
            print("MARKERS SetupView: ScreenTime already approved, skipping to authorization")
            fflush(stdout)
            await MainActor.run {
                model.navigate(.authorization)
            }
        } else {
            // Need to request ScreenTime access
            NSLog("MARKERS SetupView: ScreenTime not approved, showing access screen")
            print("MARKERS SetupView: ScreenTime not approved, showing access screen")
            fflush(stdout)
            await MainActor.run {
                model.navigate(.screenTimeAccess)
            }
        }
    }
}

