import SwiftUI
import DeviceActivity
import FamilyControls
import Foundation
import PassKit

struct AuthorizationView: View {
    @EnvironmentObject var model: AppModel
    @State private var calculatedAmount: Double = 0.0
    @State private var isLockingIn = false
    @State private var lockInError: String?
    @State private var isPresentingPaymentSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 12) {
                    Text("Authorization Amount")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("$\(calculatedAmount, specifier: "%.2f")")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.pink)
                    
                    Text("This amount is calculated from your time limit, penalty, and selected apps. It secures your commitment for the current period.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
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
                .padding()
                
                // Prominent Apple Pay button (if available)
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
                    
                    // Divider with "or" text
                    HStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal)
                }
                
                // Regular payment button (fallback or when Apple Pay not available)
                Button(action: {
                    Task {
                        await lockInAndStartMonitoring(preferApplePay: false)
                    }
                }) {
                    HStack {
                        if isLockingIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 8)
                        }
                        Text(isPresentingPaymentSheet ? "Setting up payment..." : (isLockingIn ? "Locking in..." : "Other Payment Methods"))
                        .font(.headline)
                        .foregroundColor(.white)
                    }
                        .frame(maxWidth: .infinity)
                        .padding()
                    .background(isLockingIn ? Color.gray : Color.pink)
                        .cornerRadius(12)
                }
                .disabled(isLockingIn || isPresentingPaymentSheet)
                .padding(.horizontal)
                
                // Show error if any
                if let error = lockInError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                Button(role: .cancel) {
                    model.navigate(.setup)
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Authorization")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                calculatedAmount = model.calculateAuthorizationAmount()
                model.authorizationAmount = calculatedAmount
            }
        }
    }
    
    private func lockInAndStartMonitoring(preferApplePay: Bool = false) async {
        // Clear any previous errors
        await MainActor.run {
            lockInError = nil
            isLockingIn = true
        }
        
        do {
            // Step 1: Check billing status and setup payment if needed
            NSLog("LOCKIN AuthorizationView: Step 1 - Checking billing status...")
            let billingStatus = try await BackendClient.shared.checkBillingStatus()
            NSLog("LOCKIN AuthorizationView: ✅ Step 1 complete - Billing status - hasPaymentMethod: \(billingStatus.hasPaymentMethod), needsSetupIntent: \(billingStatus.needsSetupIntent)")
            
            // Step 1.5: Handle Stripe SetupIntent if needed
            if billingStatus.needsSetupIntent {
                NSLog("LOCKIN AuthorizationView: Step 1.5 - SetupIntent needed, presenting payment sheet...")
                
                guard let clientSecret = billingStatus.setupIntentClientSecret else {
                    throw BackendError.decodingError("Missing setup intent client secret")
                }
                
                // Update UI state
                await MainActor.run {
                    isPresentingPaymentSheet = true
                }
                
                do {
                    let paymentSuccess: Bool
                    if preferApplePay {
                        // Use direct Apple Pay (bypasses PaymentSheet)
                        let amount = await MainActor.run { calculatedAmount }
                        paymentSuccess = try await StripePaymentManager.shared.presentApplePay(
                            clientSecret: clientSecret,
                            amount: amount
                        )
                    } else {
                        // Use PaymentSheet (for other payment methods)
                        paymentSuccess = try await StripePaymentManager.shared.presentSetupIntent(
                            clientSecret: clientSecret
                        )
                    }
                    
                    // Update UI state
                    await MainActor.run {
                        isPresentingPaymentSheet = false
                    }
                    
                    if !paymentSuccess {
                        // User cancelled payment setup
                        NSLog("LOCKIN AuthorizationView: ⚠️ Payment setup cancelled by user")
                        await MainActor.run {
                            isLockingIn = false
                            lockInError = "Payment setup was cancelled. Please complete payment setup to lock in your commitment."
                        }
                        return
                    }
                    
                    NSLog("LOCKIN AuthorizationView: ✅ Step 1.5 complete - Payment setup completed successfully")
                    
                    // Optionally: Re-check billing status to verify payment method was saved
                    // This ensures the backend has updated has_active_payment_method flag
                    NSLog("LOCKIN AuthorizationView: Verifying payment method was saved...")
                    let updatedBillingStatus = try await BackendClient.shared.checkBillingStatus()
                    if updatedBillingStatus.hasPaymentMethod {
                        NSLog("LOCKIN AuthorizationView: ✅ Payment method confirmed in backend")
                    } else {
                        NSLog("LOCKIN AuthorizationView: ⚠️ Payment method not yet confirmed, but proceeding...")
                        // Small delay to allow backend to process
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
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
            let weekStartDate = await MainActor.run { model.getNextMondayNoonEST() }
            let limitMinutes = Int(await MainActor.run { model.limitMinutes })
            let penaltyPerMinuteCents = Int(await MainActor.run { model.penaltyPerMinute * 100 })
            let selectedApps = await MainActor.run { model.selectedApps }
            
            NSLog("LOCKIN AuthorizationView: Step 2 - Parameters ready - weekStartDate: \(weekStartDate), limitMinutes: \(limitMinutes), penaltyPerMinuteCents: \(penaltyPerMinuteCents)")
            NSLog("LOCKIN AuthorizationView: Step 2 - Calling createCommitment()...")
            
            let commitmentResponse = try await BackendClient.shared.createCommitment(
                weekStartDate: weekStartDate,
                limitMinutes: limitMinutes,
                penaltyPerMinuteCents: penaltyPerMinuteCents,
                selectedApps: selectedApps
            )
            
            NSLog("LOCKIN AuthorizationView: ✅ Step 2 complete - Commitment created successfully!")
            NSLog("LOCKIN AuthorizationView: commitmentId: \(commitmentResponse.commitmentId)")
            NSLog("LOCKIN AuthorizationView: maxChargeCents: \(commitmentResponse.maxChargeCents)")
            
            // Step 3: Store baseline time (0 when "Lock in" is pressed)
        await MainActor.run {
            model.baselineUsageSeconds = 0
            model.currentUsageSeconds = 0
            model.updateCurrentPenalty()
            model.savePersistedValues()
        }
        
        // Store baseline in App Group
        UsageTracker.shared.storeBaselineTime(0.0)
            
            // Store commitment deadline (next Monday noon EST)
            let deadline = await MainActor.run { model.getNextMondayNoonEST() }
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
            } else {
                NSLog("RESET AuthorizationView: ❌ ERROR: Deadline was NOT stored!")
                print("RESET AuthorizationView: ❌ ERROR: Deadline was NOT stored!")
                fflush(stdout)
            }
        
        // Ensure thresholds are prepared before starting
        if #available(iOS 16.0, *) {
            // Check if thresholds are ready, if not prepare them now
            if !MonitoringManager.shared.thresholdsAreReady(for: model.selectedApps) {
                NSLog("MARKERS AuthorizationView: ⚠️ Thresholds not ready, preparing now...")
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
        await MainActor.run {
            model.navigateAfterYield(.monitor)
        }
        
        // Small delay to let UI settle after navigation
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Start monitoring in background (after navigation and delay)
        // Uses cached thresholds if available (prepared after "Commit" button or above)
        if #available(iOS 16.0, *) {
            Task {
                await MonitoringManager.shared.startMonitoring(
                    selection: model.selectedApps,
                    limitMinutes: Int(model.limitMinutes)
                )
                
                // Clear loading state after monitoring starts
                await MainActor.run {
                    model.isStartingMonitoring = false
                }
            }
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
        let button = PKPaymentButton(paymentButtonType: .plain, paymentButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .touchUpInside)
        button.isEnabled = isEnabled
        return button
    }
    
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.alpha = isEnabled ? 1.0 : 0.6
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

