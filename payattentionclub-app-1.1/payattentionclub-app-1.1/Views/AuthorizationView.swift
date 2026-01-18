import SwiftUI
import DeviceActivity
import FamilyControls
import Foundation
import PassKit

struct AuthorizationView: View {
    @EnvironmentObject var model: AppModel
    @State private var calculatedAmount: Double = 0.0
    @State private var animatedAmount: Double = 0.0
    @State private var isLockingIn = false
    @State private var lockInError: String?
    @State private var isPresentingPaymentSheet = false
    @State private var isLoadingAuthorization = false
    @State private var previewDeadlineDate: String? = nil // Store preview deadline for Test 5
    // Pink color constant: #E2CCCD
    private let pinkColor = Color(red: 226/255, green: 204/255, blue: 205/255)
    
    var body: some View {
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
                        // Black rectangle with authorization amount
                        ContentCard {
                            VStack(spacing: 0) {
                                VStack(alignment: .center, spacing: 12) {
                                    Text("Authorization Amount")
                                        .font(.headline)
                                        .foregroundColor(pinkColor)
                                    
                                    if isLoadingAuthorization {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: pinkColor))
                                            .scaleEffect(1.5)
                                    } else {
                                        Text("$\(animatedAmount, specifier: "%.2f")")
                                            .font(.system(size: 56, weight: .bold))
                                            .foregroundColor(pinkColor)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120) // Double the height (was ~60, now 120)
                        }
                        
                        // Text under the black rectangle
                        VStack(spacing: 12) {
                            (Text("Given your settings we calculated this ") +
                             Text("maximum charge").fontWeight(.bold) +
                             Text(" amount. This means you can never loose more than this amount."))
                                .font(.headline)
                                .fontWeight(.regular)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            // Horizontal dotted divider in black
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 1)
                                .overlay(
                                    GeometryReader { geometry in
                                        Path { path in
                                            path.move(to: CGPoint(x: 0, y: 0))
                                            path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                                        }
                                        .stroke(Color.black, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    }
                                )
                                .padding(.horizontal)
                            
                            Text("The total weekly penalties will be used for activist anti-screentime campaigns.")
                                .font(.headline)
                                .fontWeight(.regular)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.top, 220) // 180px (header height) + 40px spacing = 220px from top
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Buttons positioned absolutely at bottom (like position: absolute in CSS)
                    VStack(spacing: 8) {
                        // Apple Pay Button
                        if PKPaymentAuthorizationController.canMakePayments() {
                            ApplePayButton(
                                action: {
                                    Task {
                                        await lockInAndStartMonitoring(preferApplePay: true)
                                    }
                                },
                                isEnabled: !isLockingIn && !isPresentingPaymentSheet
                            )
                            .frame(height: 50)
                            .padding(.horizontal)
                        }
                        
                        // Other Payment Methods Button
                        Button(action: {
                            Task {
                                await lockInAndStartMonitoring(preferApplePay: false)
                            }
                        }) {
                            HStack {
                                if isLockingIn {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .padding(.trailing, 8)
                                }
                                Text(isPresentingPaymentSheet ? "Setting up payment..." : (isLockingIn ? "Locking in..." : "Other Payment Methods"))
                                    .font(.headline)
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 255/255, green: 244/255, blue: 244/255)) // #FFF4F4
                            .cornerRadius(12)
                        }
                        .disabled(isLockingIn || isPresentingPaymentSheet)
                        .padding(.horizontal)
                        
                        // Cancel button (just text)
                        Button(action: {
                            model.navigate(.setup)
                        }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.black)
                        }
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
            .task {
                isLoadingAuthorization = true
                // Fetch authorization amount and capture preview deadline for Test 5
                let previewResponse = try? await BackendClient.shared.previewMaxCharge(
                    limitMinutes: Int(model.limitMinutes),
                    penaltyPerMinuteCents: Int(model.penaltyPerMinute * 100),
                    selectedApps: model.selectedApps
                )
                if let preview = previewResponse {
                    previewDeadlineDate = preview.deadlineDate
                    calculatedAmount = preview.maxChargeDollars
                    NSLog("🧪 TEST 5 - PREVIEW: iOS app captured deadline: \(preview.deadlineDate) at \(Date().ISO8601Format())")
                } else {
                    // Fallback to model method if direct call fails
                    calculatedAmount = await model.fetchAuthorizationAmount()
                }
                model.authorizationAmount = calculatedAmount
                model.savePersistedValues() // Save authorization amount
                
                isLoadingAuthorization = false
                
                // Animate from 0 to calculated amount over 1 second
                animateAmount(from: 0.0, to: calculatedAmount, duration: 1.0)
            }
            .onDisappear {
                // Cleanup if needed
            }
    }
    
    private func animateAmount(from: Double, to: Double, duration: Double) {
        // Use SwiftUI's animation system which works well for number animations
        animatedAmount = from
        
        // Animate to target value over the specified duration
        withAnimation(.easeOut(duration: duration)) {
            animatedAmount = to
        }
    }
    
    private func lockInAndStartMonitoring(preferApplePay: Bool = false) async {
        // Clear any previous errors
        await MainActor.run {
            lockInError = nil
            isLockingIn = true
        }
        
        do {
            // Step 1: Check billing status and create PaymentIntent if needed
            NSLog("LOCKIN AuthorizationView: Step 1 - Checking billing status...")
            let authorizationAmountCents = Int(await MainActor.run { calculatedAmount * 100 })
            let billingStatus = try await BackendClient.shared.checkBillingStatus(authorizationAmountCents: authorizationAmountCents)
            NSLog("LOCKIN AuthorizationView: ✅ Step 1 complete - Billing status - hasPaymentMethod: \(billingStatus.hasPaymentMethod), needsPaymentIntent: \(billingStatus.needsPaymentIntent)")
            
            // Step 1.5: Handle Stripe PaymentIntent if needed
            var savedPaymentMethodId: String? = nil
            if billingStatus.needsPaymentIntent {
                NSLog("LOCKIN AuthorizationView: Step 1.5 - PaymentIntent needed, presenting payment sheet...")
                
                guard let clientSecret = billingStatus.paymentIntentClientSecret else {
                    throw BackendError.decodingError("Missing payment intent client secret")
                }
                
                // Update UI state
                await MainActor.run {
                    isPresentingPaymentSheet = true
                }
                
                do {
                    if preferApplePay {
                        // Use direct Apple Pay (bypasses PaymentSheet)
                        let amount = await MainActor.run { calculatedAmount }
                        savedPaymentMethodId = try await StripePaymentManager.shared.presentApplePay(
                            clientSecret: clientSecret,
                            amount: amount
                        )
                        NSLog("LOCKIN AuthorizationView: ✅ Step 1.5 complete - PaymentIntent confirmed and cancelled, saved payment method ID: \(savedPaymentMethodId ?? "nil")")
                    } else {
                        // Use PaymentSheet (for other payment methods)
                        // Note: PaymentSheet with PaymentIntent is not yet implemented
                        // For now, fall back to Apple Pay or show error
                        throw BackendError.serverError("PaymentSheet with PaymentIntent not yet supported. Please use Apple Pay.")
                    }
                    
                    // Update UI state
                    await MainActor.run {
                        isPresentingPaymentSheet = false
                    }
                } catch {
                    // Update UI state
                    await MainActor.run {
                        isPresentingPaymentSheet = false
                    }
                    
                    NSLog("LOCKIN AuthorizationView: ❌ Step 1.5 failed - Payment setup error: \(error.localizedDescription)")
                    throw error
                }
            }
            
            // Step 2: Create commitment in backend
            NSLog("LOCKIN AuthorizationView: Step 2 - Preparing commitment parameters...")
            // Note: Deadline is calculated by backend (single source of truth)
            let limitMinutes = Int(await MainActor.run { model.limitMinutes })
            let penaltyPerMinuteCents = Int(await MainActor.run { model.penaltyPerMinute * 100 })
            let selectedApps = await MainActor.run { model.selectedApps }
            
            NSLog("LOCKIN AuthorizationView: Step 2 - Parameters ready - limitMinutes: \(limitMinutes), penaltyPerMinuteCents: \(penaltyPerMinuteCents)")
            NSLog("LOCKIN AuthorizationView: Step 2 - Saved payment method ID: \(savedPaymentMethodId ?? "nil")")
            NSLog("LOCKIN AuthorizationView: Step 2 - Calling createCommitment()... (backend will calculate deadline)")
            
            let commitmentResponse = try await BackendClient.shared.createCommitment(
                limitMinutes: limitMinutes,
                penaltyPerMinuteCents: penaltyPerMinuteCents,
                selectedApps: selectedApps,
                savedPaymentMethodId: savedPaymentMethodId
            )
            
            NSLog("LOCKIN AuthorizationView: ✅ Step 2 complete - Commitment created successfully!")
            NSLog("LOCKIN AuthorizationView: commitmentId: \(commitmentResponse.commitmentId)")
            
            // Store commitment ID in App Group for usage tracking
            UsageTracker.shared.storeCommitmentId(commitmentResponse.commitmentId)
            NSLog("LOCKIN AuthorizationView: ✅ Stored commitment ID: \(commitmentResponse.commitmentId)")
            NSLog("LOCKIN AuthorizationView: maxChargeCents: \(commitmentResponse.maxChargeCents)")
            NSLog("LOCKIN AuthorizationView: deadlineDate from backend: \(commitmentResponse.deadlineDate)")
            
            // Request notification permissions and reset notification state for new commitment
            await MainActor.run {
                NotificationManager.shared.resetNotificationState()
            }
            // Request permission (non-blocking - don't wait for user response)
            Task {
                let granted = await NotificationManager.shared.requestPermission()
                if granted {
                    NSLog("LOCKIN AuthorizationView: ✅ Notification permission granted")
                } else {
                    NSLog("LOCKIN AuthorizationView: ⚠️ Notification permission denied - notifications will be skipped")
                }
            }
            
            // Test 5: Compare preview and commitment deadlines
            NSLog("🧪 TEST 5 - COMMITMENT: iOS app received deadline from backend: \(commitmentResponse.deadlineDate) at \(Date().ISO8601Format())")
            if let previewDeadline = previewDeadlineDate {
                NSLog("🧪 TEST 5 - COMPARISON:")
                NSLog("   Preview deadline: \(previewDeadline)")
                NSLog("   Commitment deadline: \(commitmentResponse.deadlineDate)")
                if previewDeadline == commitmentResponse.deadlineDate {
                    NSLog("   ✅ PASS: Both deadlines match (same calculation)")
                } else {
                    NSLog("   ⚠️  DIFFERENT: Deadlines differ (expected if time passed between preview and commitment)")
                    NSLog("   This is OK - backend recalculates deadline at commitment time")
                }
            } else {
                NSLog("🧪 TEST 5 - ⚠️  No preview deadline stored for comparison")
            }
            
            // Step 3: Store baseline time (0 when "Lock in" is pressed)
        await MainActor.run {
            model.baselineUsageSeconds = 0
            model.currentUsageSeconds = 0
            model.updateCurrentPenalty()
            model.savePersistedValues()
        }
        
        // Store baseline in App Group
        UsageTracker.shared.storeBaselineTime(0.0)
        
        // Reset consumedMinutes to 0 when commitment is created
        // This ensures old usage from previous commitments doesn't carry over
        // The extension will also reset it in intervalDidStart, but we do it here too
        // to prevent any race conditions where the app reads the old value before monitoring starts
        if let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub2.0.app") {
            userDefaults.set(0.0, forKey: "consumedMinutes")
            userDefaults.set(Date().timeIntervalSince1970, forKey: "consumedMinutesTimestamp")
            userDefaults.synchronize()
            NSLog("LOCKIN AuthorizationView: ✅ Reset consumedMinutes to 0")
        }
            
            // Store commitment deadline - use backend deadline (compressed in testing mode, normal in production)
            // Parse deadlineDate from backend response
            // In testing mode: ISO 8601 format (e.g., "2025-12-31T12:06:00.000Z")
            // In normal mode: Date only format (e.g., "2025-12-31")
            let deadline: Date
            
            // Try parsing as ISO 8601 first (testing mode with full timestamp)
            // Try with fractional seconds first, then without
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            var isoDeadline: Date?
            isoDeadline = iso8601Formatter.date(from: commitmentResponse.deadlineDate)
            
            if isoDeadline == nil {
                // Try without fractional seconds
                iso8601Formatter.formatOptions = [.withInternetDateTime]
                isoDeadline = iso8601Formatter.date(from: commitmentResponse.deadlineDate)
            }
            
            if let isoDeadline = isoDeadline {
                // Successfully parsed as ISO 8601 (testing mode)
                deadline = isoDeadline
                NSLog("AUTH AuthorizationView: ✅ Using backend deadline (ISO 8601): \(deadline) (from \(commitmentResponse.deadlineDate))")
                print("AUTH AuthorizationView: ✅ Using backend deadline (ISO 8601): \(deadline) (from \(commitmentResponse.deadlineDate))")
                fflush(stdout)
            } else {
                // Try parsing as date only (normal mode: "yyyy-MM-dd")
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
                
                if let backendDeadline = dateFormatter.date(from: commitmentResponse.deadlineDate) {
                    // Use backend deadline (normal mode)
                    // Set time to 12:00 ET (noon) to match backend's deadline time
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: backendDeadline)
                    components.hour = 12
                    components.minute = 0
                    components.second = 0
                    components.timeZone = TimeZone(identifier: "America/New_York")
                    if let deadlineWithTime = Calendar.current.date(from: components) {
                        deadline = deadlineWithTime
                    } else {
                        // If time setting fails, use the date as-is (will be midnight, but better than nothing)
                        deadline = backendDeadline
                    }
                    NSLog("AUTH AuthorizationView: ✅ Using backend deadline (date only): \(deadline) (from \(commitmentResponse.deadlineDate))")
                    print("AUTH AuthorizationView: ✅ Using backend deadline (date only): \(deadline) (from \(commitmentResponse.deadlineDate))")
                    fflush(stdout)
                } else {
                    // Fallback to local calculation if parsing fails
                    deadline = await MainActor.run { model.getNextMondayNoonEST() }
                    NSLog("AUTH AuthorizationView: ⚠️ Fallback to local deadline calculation (failed to parse: \(commitmentResponse.deadlineDate))")
                    print("AUTH AuthorizationView: ⚠️ Fallback to local deadline calculation (failed to parse: \(commitmentResponse.deadlineDate))")
                    fflush(stdout)
                }
            }
            
            NSLog("RESET AuthorizationView: 🔒 Storing commitment deadline: %@", String(describing: deadline))
            print("RESET AuthorizationView: 🔒 Storing commitment deadline: \(deadline)")
            fflush(stdout)
            UsageTracker.shared.storeCommitmentDeadline(deadline)
            
            // Verify deadline was stored
            let storedDeadline = UsageTracker.shared.getCommitmentDeadline()
            if let storedDeadline = storedDeadline {
                NSLog("RESET AuthorizationView: ✅ Deadline stored successfully: %@", String(describing: storedDeadline))
                print("RESET AuthorizationView: ✅ Deadline stored successfully: \(storedDeadline)")
                fflush(stdout)
                
                // Update countdown model with the stored deadline (from backend, compressed in testing mode)
                model.countdownModel?.updateDeadline(storedDeadline)
                NSLog("RESET AuthorizationView: ✅ Updated countdown model with stored deadline")
                print("RESET AuthorizationView: ✅ Updated countdown model with stored deadline")
                fflush(stdout)
            } else {
                NSLog("RESET AuthorizationView: ❌ ERROR: Deadline was NOT stored!")
                print("RESET AuthorizationView: ❌ ERROR: Deadline was NOT stored!")
                fflush(stdout)
            }
        
        // Ensure thresholds are prepared before starting
        if #available(iOS 16.0, *) {
            // Check if thresholds are ready, if not prepare them now
            if !MonitoringManager.shared.thresholdsAreReady(for: model.selectedApps) {
                NSLog("LOCKIN AuthorizationView: ⚠️ Thresholds not ready, preparing now...")
                fflush(stdout)
                await MonitoringManager.shared.prepareThresholds(
                    selection: model.selectedApps,
                    limitMinutes: Int(model.limitMinutes)
                )
            }
        }
            
        // Clear loading state
        await MainActor.run {
            isLockingIn = false
        }
        
        // Set loading state before navigation
        await MainActor.run {
            model.isStartingMonitoring = true
        }
        
        // Navigate immediately (don't wait for monitoring to start)
        // Now awaitable to ensure navigation completes
        NSLog("LOCKIN AuthorizationView: Step 8 - About to navigate to monitor...")
        await model.navigateAfterYield(.monitor)
        NSLog("LOCKIN AuthorizationView: ✅ Step 8 complete - Navigation to monitor completed")
        
        // Small delay to let UI settle after navigation
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Start monitoring in background (after navigation and delay)
        // Uses cached thresholds if available (prepared after "Commit" button or above)
        NSLog("LOCKIN AuthorizationView: Step 9 - Starting monitoring in background...")
        if #available(iOS 16.0, *) {
            Task {
                do {
                    await MonitoringManager.shared.startMonitoring(
                        selection: model.selectedApps,
                        limitMinutes: Int(model.limitMinutes)
                    )
                    
                    NSLog("LOCKIN AuthorizationView: ✅ Step 9 complete - Monitoring started successfully")
                    
                    // Clear loading state after monitoring starts
                    await MainActor.run {
                        model.isStartingMonitoring = false
                    }
                } catch {
                    NSLog("LOCKIN AuthorizationView: ⚠️ Step 9 failed - Monitoring start error: \(error.localizedDescription)")
                    NSLog("LOCKIN AuthorizationView: Error type: \(type(of: error))")
                    // Don't prevent navigation if monitoring fails - user is already on monitor screen
                    await MainActor.run {
                        model.isStartingMonitoring = false
                    }
                }
            }
        }
        
        // Update daily usage and sync to backend after commitment creation
        // This ensures any existing usage data is synced immediately
        Task {
            await UsageSyncManager.shared.updateAndSync()
        }
        } catch {
            NSLog("LOCKIN AuthorizationView: ❌ Error during lock in: \(error.localizedDescription)")
            NSLog("LOCKIN AuthorizationView: Error type: \(type(of: error))")
            NSLog("LOCKIN AuthorizationView: Full error: \(error)")
            await MainActor.run {
                isLockingIn = false
                lockInError = "Failed to lock in: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Apple Pay Button Wrapper

struct ApplePayButton: UIViewRepresentable {
    let action: () -> Void
    var isEnabled: Bool = true
    
    func makeUIView(context: Context) -> PKPaymentButton {
        // Note: Apple Pay logo color cannot be customized per Apple's guidelines
        // Available styles: .black, .white, .whiteOutline
        // Using .black style with white logo (standard)
        let button = PKPaymentButton(paymentButtonType: .plain, paymentButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .touchUpInside)
        button.isEnabled = isEnabled
        
        // Set corner radius to match other buttons (12 points)
        button.layer.cornerRadius = 12
        button.clipsToBounds = true
        
        return button
    }
    
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.alpha = isEnabled ? 1.0 : 0.6
        
        // Ensure corner radius is maintained
        uiView.layer.cornerRadius = 12
        uiView.clipsToBounds = true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    class Coordinator: NSObject {
        let action: () -> Void
        
        init(action: @escaping () -> Void) {
            self.action = action
        }
        
        @objc func buttonTapped() {
            action()
        }
    }
}
