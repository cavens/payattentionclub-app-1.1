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
                    CountdownView(model: model)
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
        
        // Start monitoring to trigger Monitor Extension
        if #available(iOS 16.0, *) {
            MonitoringManager.shared.startMonitoring(selection: model.selectedApps)
        }
        
        // Navigate to monitor view - Yield to ensure scene is active
        await MainActor.run {
            model.navigateAfterYield(.monitor)
        }
    }
}

