import SwiftUI
import Foundation

/// Temporary test view for testing backend connectivity
/// Remove this file after testing is complete
struct BackendTestView: View {
    @State private var isTesting = false
    @State private var testResult: String = ""
    @State private var testError: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Backend Test")
                    .font(.largeTitle)
                    .padding()
                
                Text("Testing: checkBillingStatus()")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if isTesting {
                    ProgressView()
                        .padding()
                }
                
                if !testResult.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("✅ Success:")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(testResult)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding()
                }
                
                if !testError.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("❌ Error:")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(testError)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding()
                }
                
                Button(action: {
                    testBackend()
                }) {
                    Text("Test Backend")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isTesting ? Color.gray : Color.blue)
                        .cornerRadius(10)
                }
                .disabled(isTesting)
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Backend Test")
            .withLogoutButton()
        }
    }
    
    private func testBackend() {
        isTesting = true
        testResult = ""
        testError = ""
        
        let startTime = Date()
        NSLog("BACKEND_TEST: Starting checkBillingStatus() test")
        
        Task {
            do {
                NSLog("BACKEND_TEST: Calling BackendClient.shared.checkBillingStatus()")
                
                let response = try await BackendClient.shared.checkBillingStatus()
                
                let duration = Date().timeIntervalSince(startTime)
                NSLog("BACKEND_TEST: ✅ Success! Duration: \(String(format: "%.2f", duration))s")
                NSLog("BACKEND_TEST: Response - hasPaymentMethod: \(response.hasPaymentMethod)")
                NSLog("BACKEND_TEST: Response - needsSetupIntent: \(response.needsSetupIntent)")
                NSLog("BACKEND_TEST: Response - setupIntentClientSecret: \(response.setupIntentClientSecret ?? "nil")")
                NSLog("BACKEND_TEST: Response - stripeCustomerId: \(response.stripeCustomerId ?? "nil")")
                
                let resultText = """
                Duration: \(String(format: "%.2f", duration))s
                
                hasPaymentMethod: \(response.hasPaymentMethod)
                needsSetupIntent: \(response.needsSetupIntent)
                setupIntentClientSecret: \(response.setupIntentClientSecret ?? "nil")
                stripeCustomerId: \(response.stripeCustomerId ?? "nil")
                """
                
                await MainActor.run {
                    testResult = resultText
                    testError = ""
                    isTesting = false
                }
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                NSLog("BACKEND_TEST: ❌ Error after \(String(format: "%.2f", duration))s")
                NSLog("BACKEND_TEST: Error type: \(type(of: error))")
                NSLog("BACKEND_TEST: Error description: \(error.localizedDescription)")
                
                if let urlError = error as? URLError {
                    NSLog("BACKEND_TEST: URLError code: \(urlError.code.rawValue)")
                    NSLog("BACKEND_TEST: URLError description: \(urlError.localizedDescription)")
                }
                
                await MainActor.run {
                    testError = """
                    Duration: \(String(format: "%.2f", duration))s
                    
                    Error Type: \(type(of: error))
                    Description: \(error.localizedDescription)
                    
                    \(error)
                    """
                    testResult = ""
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    BackendTestView()
}

