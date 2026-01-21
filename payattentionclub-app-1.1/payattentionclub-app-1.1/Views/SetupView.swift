import SwiftUI
import Foundation
import FamilyControls
import Auth
import UIKit

// Shake animation modifier for buzzing effect
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(shakes * .pi * 2) * 10
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

// Custom Slider View with pink thumb and #666666 inactive track
struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    
    var body: some View {
        GeometryReader { geometry in
            let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let sliderWidth = geometry.size.width
            let thumbPosition = max(0, min(sliderWidth, sliderWidth * CGFloat(normalizedValue)))
            
            ZStack(alignment: .leading) {
                // Inactive track (dark part) - #666666
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 102/255, green: 102/255, blue: 102/255))
                    .frame(height: 4)
                
                // Active track (pink)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 226/255, green: 204/255, blue: 205/255))
                    .frame(width: thumbPosition, height: 4)
                
                // Thumb (circle) - pink
                Circle()
                    .fill(Color(red: 226/255, green: 204/255, blue: 205/255))
                    .frame(width: 20, height: 20)
                    .offset(x: thumbPosition - 10)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { dragValue in
                                let newPosition = max(0, min(sliderWidth, dragValue.location.x))
                                let newNormalized = Double(newPosition / sliderWidth)
                                let newValue = range.lowerBound + newNormalized * (range.upperBound - range.lowerBound)
                                
                                // Apply step
                                let steppedValue = round((newValue - range.lowerBound) / step) * step + range.lowerBound
                                let oldValue = value
                                value = max(range.lowerBound, min(range.upperBound, steppedValue))
                                
                                // Haptic feedback when value changes
                                if abs(value - oldValue) > 0.001 {
                                    let generator = UISelectionFeedbackGenerator()
                                    generator.selectionChanged()
                                }
                            }
                    )
            }
        }
        .frame(height: 20)
    }
}

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAppPicker = false
    @State private var isAuthenticating = false
    @State private var authenticationError: String?
    @State private var showAuthorizationAlert = false
    @State private var tapCount = 0
    @State private var lastTapTime: Date?
    @State private var shouldShakeAppButton: CGFloat = 0 // For buzzing animation when commit is disabled
    @State private var isRequestingAuthorization = false // Loading state for authorization request
    @State private var authorizationStatus: AuthorizationStatus = .notDetermined // Cached authorization status
    
    // Pink color constant: #E2CCCD
    private let pinkColor = Color(red: 226/255, green: 204/255, blue: 205/255)
    // Gray color for text and dividers: #666666
    private let grayColor = Color(red: 102/255, green: 102/255, blue: 102/255)
    
    // Check if no apps are selected
    private var hasNoAppsSelected: Bool {
        model.selectedApps.applicationTokens.count == 0 && model.selectedApps.categoryTokens.count == 0
    }
    
    // Convert slider position (0.0-1.0) to penalty value ($0.05-$5.00) with $0.10 in the middle
    private func positionToPenalty(_ position: Double) -> Double {
        let minPenalty = 0.05
        let midPenalty = 0.10
        let maxPenalty = 5.00
        
        if position <= 0.5 {
            // First half: linear from $0.05 to $0.10
            return minPenalty + (midPenalty - minPenalty) * (position / 0.5)
        } else {
            // Second half: logarithmic from $0.10 to $5.00
            let ratio = (position - 0.5) / 0.5 // 0.0 to 1.0
            let logRatio = log(midPenalty / minPenalty) + ratio * log(maxPenalty / midPenalty)
            return minPenalty * exp(logRatio)
        }
    }
    
    // Convert penalty value ($0.05-$5.00) to slider position (0.0-1.0)
    private func penaltyToPosition(_ penalty: Double) -> Double {
        let minPenalty = 0.05
        let midPenalty = 0.10
        let maxPenalty = 5.00
        
        if penalty <= midPenalty {
            // First half: linear from $0.05 to $0.10
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
            GeometryReader { geometry in
                ZStack {
                    // Header absolutely positioned at top - fixed position
                    VStack(alignment: .leading, spacing: 0) {
                        PageHeader()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Rectangle absolutely positioned - 20 points below countdown (which is at bottom of 180px header)
                    VStack(spacing: 16) {
                        // Black rectangle with sliders
                        ContentCard {
                            VStack(spacing: 0) {
                            // Time Limit Slider
                            VStack(alignment: .leading, spacing: 12) {
                                Text(formatDeadlineLabel())
                                    .font(.headline)
                                    .foregroundColor(pinkColor)
                                    .onTapGesture {
                                        handleDeadlineLabelTap()
                                    }
                                
                                Text(formatTime(model.limitMinutes))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(pinkColor)
                                
                                CustomSlider(
                                    value: $model.limitMinutes,
                                    range: 30...2520, // 30 minutes to 42 hours (in minutes)
                                    step: 15
                                )
                                
                                HStack {
                                    Text("30 min")
                                        .font(.caption)
                                        .foregroundColor(grayColor)
                                    Spacer()
                                    Text("42 hours")
                                        .font(.caption)
                                        .foregroundColor(grayColor)
                                }
                            }
                            .padding(.bottom, 20)
                            
                            // Dotted horizontal divider
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 1)
                                .overlay(
                                    GeometryReader { geometry in
                                        Path { path in
                                            path.move(to: CGPoint(x: 0, y: 0))
                                            path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                                        }
                                        .stroke(grayColor, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    }
                                )
                                .padding(.vertical, 15)
                            
                            // Penalty Slider
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Penalty per minute over limit")
                                    .font(.headline)
                                    .foregroundColor(pinkColor)
                                
                                Text("$\(model.penaltyPerMinute, specifier: "%.2f")")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(pinkColor)
                                
                                CustomSlider(
                                    value: Binding(
                                        get: { penaltyToPosition(model.penaltyPerMinute) },
                                        set: { newPosition in
                                            model.penaltyPerMinute = positionToPenalty(newPosition)
                                        }
                                    ),
                                    range: 0.0...1.0,
                                    step: 0.001
                                )
                                
                                HStack {
                                    Text("$0.05")
                                        .font(.caption)
                                        .foregroundColor(grayColor)
                                    Spacer()
                                    Text("$5.00")
                                        .font(.caption)
                                        .foregroundColor(grayColor)
                                }
                            }
                            .padding(.top, 20)
                        }
                    }
                    
                    // Text under the black rectangle
                    Text("The total weekly penalties will be used for activist anti-screentime campaigns.")
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .padding(.top, 220) // 180px (header height) + 40px spacing = 220px from top
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Buttons positioned absolutely at bottom (like position: absolute in CSS)
                    VStack(spacing: 8) {
                    // App Selector
                    Button(action: {
                        // Immediate feedback - no async wrapper needed for this
                        // Provide haptic feedback immediately to acknowledge tap
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        // Check cached authorization status first (fast path)
                        if authorizationStatus == .approved {
                            // Already approved, show picker immediately (no async needed)
                            NSLog("SETUP SetupView: Authorization approved (cached), showing picker immediately")
                            showAppPicker = true
                        } else {
                            // Not approved - show loading state immediately, then request authorization
                            NSLog("SETUP SetupView: Authorization not approved (\(authorizationStatus.rawValue)), requesting...")
                            isRequestingAuthorization = true
                            
                            Task { @MainActor in
                                do {
                                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                                    let newStatus = AuthorizationCenter.shared.authorizationStatus
                                    authorizationStatus = newStatus // Update cache
                                    NSLog("SETUP SetupView: Authorization request completed, new status: \(newStatus.rawValue)")
                                    
                                    isRequestingAuthorization = false
                                    
                                    if newStatus == .approved {
                                        // Now approved, show picker
                                        NSLog("SETUP SetupView: Authorization granted, showing picker")
                                        showAppPicker = true
                                    } else {
                                        // Still not approved, show alert
                                        NSLog("SETUP SetupView: Authorization still not granted, showing alert")
                                        showAuthorizationAlert = true
                                    }
                                } catch {
                                    NSLog("SETUP SetupView: ❌ Failed to request authorization: \(error)")
                                    isRequestingAuthorization = false
                                    showAuthorizationAlert = true
                                }
                            }
                        }
                    }) {
                        HStack {
                            if isRequestingAuthorization {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: pinkColor))
                                    .padding(.trailing, 8)
                            }
                            Label("Select Apps to Limit (\(model.selectedApps.applicationTokens.count + model.selectedApps.categoryTokens.count))", systemImage: "app.fill")
                                .font(.headline)
                                .foregroundColor(isRequestingAuthorization ? grayColor : pinkColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .cornerRadius(12)
                    }
                    .disabled(isRequestingAuthorization) // Disable button during authorization request
                    .padding(.horizontal)
                    .modifier(ShakeEffect(shakes: shouldShakeAppButton))
                    .familyActivityPicker(isPresented: $showAppPicker, selection: $model.selectedApps)
                    .alert("Screen Time Access Required", isPresented: $showAuthorizationAlert) {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Screen Time access is required to select apps to limit. Please grant access in Settings → Screen Time → [Your App].")
                    }
                    .onChange(of: model.selectedApps) { newSelection in
                        NSLog("SETUP SetupView: selectedApps changed! Apps: \(newSelection.applicationTokens.count), Categories: \(newSelection.categoryTokens.count)")
                    }
                    
                    // Authentication Error Display
                    if let error = authenticationError {
                        Text("Authentication Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    // Commit Button
                    Button(action: {
                        if hasNoAppsSelected {
                            // Trigger haptic feedback and shake animation
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.warning)
                            
                            // Trigger shake animation on app button
                            withAnimation(.linear(duration: 0.4)) {
                                shouldShakeAppButton = 6
                            }
                            
                            // Reset animation after it completes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                shouldShakeAppButton = 0
                            }
                        } else if !isAuthenticating {
                            handleCommit()
                        }
                    }) {
                        HStack {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: pinkColor))
                                    .padding(.trailing, 8)
                            }
                            Text(isAuthenticating ? "Signing in..." : "Commit")
                            .font(.headline)
                            .foregroundColor((isAuthenticating || hasNoAppsSelected) ? grayColor : pinkColor)
                        }
                            .frame(maxWidth: .infinity)
                            .padding()
                        .background(Color.black)
                            .cornerRadius(12)
                    }
                    .disabled(isAuthenticating) // Only disable when authenticating, not when no apps selected
                    .padding(.horizontal)
                    }
                    .padding(.bottom, (geometry.safeAreaInsets.bottom > 0 ? geometry.safeAreaInsets.bottom : 20) + 20) // Move buttons up by 20 points
                    .background(Color(red: 226/255, green: 204/255, blue: 205/255)) // Match background color
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true) // Hide navigation bar to avoid white stripes
            .background(Color(red: 226/255, green: 204/255, blue: 205/255))
            .scrollContentBackground(.hidden)
            .ignoresSafeArea()
            .onAppear {
                // Pre-initialize AuthorizationCenter to avoid first-access delay
                // This warms up the framework and caches the authorization status
                let center = AuthorizationCenter.shared
                authorizationStatus = center.authorizationStatus
                NSLog("SETUP SetupView: Cached authorization status on appear: \(authorizationStatus.rawValue)")
            }
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
    
    private func handleDeadlineLabelTap() {
        let now = Date()
        
        // Reset tap count if more than 1 second has passed since last tap
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) > 1.0 {
            tapCount = 0
        }
        
        tapCount += 1
        lastTapTime = now
        
        // If we've reached 3 taps, set limit to 1 minute
        if tapCount >= 3 {
            model.limitMinutes = 1.0
            tapCount = 0
            lastTapTime = nil
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

