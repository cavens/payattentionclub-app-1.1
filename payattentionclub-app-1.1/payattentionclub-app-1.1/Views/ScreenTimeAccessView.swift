import SwiftUI
import Foundation
import FamilyControls

struct ScreenTimeAccessView: View {
    @EnvironmentObject var model: AppModel
    @State private var authorizationCenter = AuthorizationCenter.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 60))
                        .foregroundColor(.pink)
                    
                    Text("Screen Time Access Required")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("PayAttentionClub needs Screen Time access to monitor your app usage and help you stay accountable.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                
                Spacer()
                
                Button(action: {
                    Task {
                        do {
                            try await authorizationCenter.requestAuthorization(for: .individual)
                            if authorizationCenter.authorizationStatus == .approved {
                                // Use navigateAfterYield to let system UI fully dismiss
                                await model.navigateAfterYield(.authorization)
                            }
                        } catch {
                            print("Authorization error: \(error)")
                        }
                    }
                }) {
                    Text("Grant Access")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationTitle("Screen Time Access")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(red: 226/255, green: 204/255, blue: 205/255))
            .onAppear {
                // Check if authorization is already granted when view appears
                Task { @MainActor in
                    let status = authorizationCenter.authorizationStatus
                    NSLog("MARKERS ScreenTimeAccessView: Authorization status on appear: %@", String(describing: status))
                    print("MARKERS ScreenTimeAccessView: Authorization status on appear: \(status)")
                    fflush(stdout)
                    
                    if status == .approved {
                        // Skip this view and go directly to authorization
                        NSLog("MARKERS ScreenTimeAccessView: Already approved, skipping to authorization")
                        print("MARKERS ScreenTimeAccessView: Already approved, skipping to authorization")
                        fflush(stdout)
                        await model.navigateAfterYield(.authorization)
                    }
                }
            }
        }
    }
}

