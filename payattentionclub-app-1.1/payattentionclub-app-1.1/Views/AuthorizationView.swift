import SwiftUI
import DeviceActivity
import FamilyControls

struct AuthorizationView: View {
    @EnvironmentObject var model: AppModel
    @State private var calculatedAmount: Double = 0.0
    
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
                
                Button(action: {
                    Task {
                        await lockInAndStartMonitoring()
                    }
                }) {
                    Text("Lock In and Start Monitoring")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
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
    
    private func lockInAndStartMonitoring() async {
        // Store baseline time (0 when "Lock in" is pressed)
        await MainActor.run {
            model.baselineUsageSeconds = 0
            model.currentUsageSeconds = 0
            model.updateCurrentPenalty()
            model.savePersistedValues()
        }
        
        // Store baseline in App Group
        UsageTracker.shared.storeBaselineTime(0.0)
        
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
    }
}

