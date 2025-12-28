import Foundation
import UIKit
import StripePaymentSheet
import Stripe
import PassKit
import ObjectiveC

/// Manages Stripe SetupIntent payment flow
@MainActor
class StripePaymentManager {
    static let shared = StripePaymentManager()
    
    private init() {}
    
    /// Present Apple Pay directly using native PKPaymentAuthorizationController
    /// This bypasses Stripe's PaymentSheet and shows only Apple's native payment UI
    /// - Parameters:
    ///   - clientSecret: The PaymentIntent client secret from backend
    ///   - amount: The authorization amount to show in Apple Pay (in dollars)
    /// - Returns: The saved payment method ID (from setup_future_usage)
    /// - Throws: Error if payment setup failed
    func presentApplePay(clientSecret: String, amount: Double) async throws -> String {
        NSLog("STRIPE StripePaymentManager: Presenting direct Apple Pay (bypassing PaymentSheet)")
        
        // Check Apple Pay availability
        guard PKPaymentAuthorizationController.canMakePayments() else {
            throw StripePaymentError.setupFailed("Apple Pay is not available on this device")
        }
        
        let merchantId = "merchant.com.payattentionclub2.0.app"
        let countryCode = Locale.current.region?.identifier ?? "US"
        
        // Create payment request
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantId
        request.supportedNetworks = [.visa, .masterCard, .amex]
        request.merchantCapabilities = .capability3DS
        request.countryCode = countryCode
        request.currencyCode = "USD"
        
        // For PaymentIntent, we show the authorization amount (will be cancelled immediately after confirmation)
        // Round amount to 2 decimal places for USD (Apple Pay requirement)
        let roundedAmount = round(amount * 100) / 100.0
        let amountInCents = NSDecimalNumber(value: roundedAmount)
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Pay Attention Club", amount: amountInCents)
        ]
        
        // Create payment authorization controller
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        
        // Use continuation to bridge delegate pattern with async/await
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ApplePayDelegate(
                clientSecret: clientSecret,
                continuation: continuation
            )
            
            // Store delegate to prevent deallocation
            controller.delegate = delegate
            objc_setAssociatedObject(controller, &AssociatedKeys.delegate, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            NSLog("STRIPE StripePaymentManager: Presenting native Apple Pay sheet...")
            controller.present { presented in
                if !presented {
                    continuation.resume(throwing: StripePaymentError.presentationFailed("Could not present Apple Pay"))
                }
            }
        }
    }
    
    // Helper to store delegate reference
    private struct AssociatedKeys {
        static var delegate: UInt8 = 0
    }
    
    /// Present Stripe SetupIntent payment sheet
    /// - Parameters:
    ///   - clientSecret: The SetupIntent client secret from backend
    ///   - preferApplePay: If true, Apple Pay will be the primary option (default: false)
    /// - Returns: `true` if payment setup completed successfully, `false` if cancelled
    /// - Throws: Error if payment setup failed
    func presentSetupIntent(clientSecret: String, preferApplePay: Bool = false) async throws -> Bool {
        NSLog("STRIPE StripePaymentManager: Preparing SetupIntent with clientSecret: \(clientSecret.prefix(20))...")
        
        // Validate client secret format
        guard clientSecret.hasPrefix("seti_") else {
            NSLog("STRIPE StripePaymentManager: ❌ Invalid client secret format (should start with 'seti_')")
            throw StripePaymentError.setupFailed("Invalid payment setup configuration")
        }
        
        // Check Apple Pay availability
        let merchantId = "merchant.com.payattentionclub2.0.app"
        let canUseApplePay = PKPaymentAuthorizationController.canMakePayments(usingNetworks: [.visa, .masterCard, .amex])
        let hasApplePayCapability = PKPaymentAuthorizationController.canMakePayments()
        
        NSLog("STRIPE StripePaymentManager: Apple Pay availability check:")
        NSLog("STRIPE StripePaymentManager:   canMakePayments: \(hasApplePayCapability)")
        NSLog("STRIPE StripePaymentManager:   canMakePayments(usingNetworks): \(canUseApplePay)")
        NSLog("STRIPE StripePaymentManager:   merchantId: \(merchantId)")
        
        // Create PaymentSheet configuration
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "Pay Attention Club"
        configuration.allowsDelayedPaymentMethods = true // Required for SetupIntent
        
        // Enable Apple Pay if available
        if hasApplePayCapability {
            // Get user's country code from device locale
            let countryCode = Locale.current.region?.identifier ?? "US"
            NSLog("STRIPE StripePaymentManager: Configuring Apple Pay with merchantId: \(merchantId), countryCode: \(countryCode)")
            
            configuration.applePay = .init(
                merchantId: merchantId,
                merchantCountryCode: countryCode
            )
        } else {
            NSLog("STRIPE StripePaymentManager: ⚠️ Apple Pay not available on this device")
        }
        
        // Note: Stripe PaymentSheet automatically prioritizes Apple Pay when available
        // Apple Pay will appear at the top of the payment methods list
        // The order is determined by Stripe's backend based on device capabilities and user preferences
        
        // If preferApplePay is true, we've already configured Apple Pay above
        // Stripe will automatically show it as the first option when available
        
        // Create PaymentSheet
        let paymentSheet = PaymentSheet(
            setupIntentClientSecret: clientSecret,
            configuration: configuration
        )
        
        NSLog("STRIPE StripePaymentManager: PaymentSheet created successfully")
        
        // Get the root view controller to present from
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            NSLog("STRIPE StripePaymentManager: ❌ Could not find root view controller")
            throw StripePaymentError.presentationFailed("Could not find root view controller")
        }
        
        // Find the topmost presented view controller
        var topViewController = rootViewController
        while let presented = topViewController.presentedViewController {
            topViewController = presented
        }
        
        // Use continuation to bridge async/await with completion handler pattern
        return try await withCheckedThrowingContinuation { continuation in
            NSLog("STRIPE StripePaymentManager: Presenting PaymentSheet...")
            
            paymentSheet.present(from: topViewController) { paymentResult in
                switch paymentResult {
                case .completed:
                    NSLog("STRIPE StripePaymentManager: ✅ SetupIntent completed successfully")
                    continuation.resume(returning: true)
                    
                case .canceled:
                    NSLog("STRIPE StripePaymentManager: ⚠️ SetupIntent cancelled by user")
                    continuation.resume(returning: false)
                    
                case .failed(let error):
                    NSLog("STRIPE StripePaymentManager: ❌ SetupIntent failed")
                    NSLog("STRIPE StripePaymentManager: Error localizedDescription: \(error.localizedDescription)")
                    NSLog("STRIPE StripePaymentManager: Error description: \(error)")
                    if let nsError = error as NSError? {
                        NSLog("STRIPE StripePaymentManager: NSError domain: \(nsError.domain)")
                        NSLog("STRIPE StripePaymentManager: NSError code: \(nsError.code)")
                        NSLog("STRIPE StripePaymentManager: NSError userInfo: \(nsError.userInfo)")
                    }
                    continuation.resume(throwing: StripePaymentError.setupFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Apple Pay Delegate

/// Delegate to handle PKPaymentAuthorizationController callbacks
private class ApplePayDelegate: NSObject, PKPaymentAuthorizationControllerDelegate {
    let clientSecret: String
    let continuation: CheckedContinuation<String, Error>
    var hasAuthorized = false
    
    init(clientSecret: String, continuation: CheckedContinuation<String, Error>) {
        self.clientSecret = clientSecret
        self.continuation = continuation
    }
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        NSLog("STRIPE ApplePayDelegate: Payment authorized, processing with backend...")
        hasAuthorized = true
        
        // Extract payment token data and convert using Stripe SDK
        NSLog("STRIPE ApplePayDelegate: Converting Apple Pay token to Stripe PaymentMethod...")
        NSLog("STRIPE ApplePayDelegate: Using publishable key: \(StripeConfig.publishableKey.prefix(20))...")
        NSLog("STRIPE ApplePayDelegate: Merchant ID from request: merchant.com.payattentionclub2.0.app")
        
        // Use Stripe's SDK to create a PaymentMethod from Apple Pay payment
        // This converts the Apple Pay token to a Stripe PaymentMethod
        Task {
            do {
                // Create PaymentMethod from Apple Pay using Stripe SDK
                // Create a fresh STPAPIClient instance to ensure clean configuration
                let apiClient = STPAPIClient(publishableKey: StripeConfig.publishableKey)
                
                NSLog("STRIPE ApplePayDelegate: Created STPAPIClient with publishable key")
                NSLog("STRIPE ApplePayDelegate: PKPayment details:")
                NSLog("STRIPE ApplePayDelegate:   - Token paymentData length: \(payment.token.paymentData.count) bytes")
                NSLog("STRIPE ApplePayDelegate:   - Token transactionIdentifier: \(payment.token.transactionIdentifier)")
                NSLog("STRIPE ApplePayDelegate:   - Payment method type: \(payment.token.paymentMethod.type.rawValue)")
                
                let merchantId = "merchant.com.payattentionclub2.0.app"
                NSLog("STRIPE ApplePayDelegate: Expected merchant ID: \(merchantId)")
                
                let paymentMethod = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<STPPaymentMethod, Error>) in
                    NSLog("STRIPE ApplePayDelegate: Calling STPAPIClient.createPaymentMethod with PKPayment...")
                    NSLog("STRIPE ApplePayDelegate: Note: This calls /v1/tokens internally, which requires certificate decryption")
                    
                    apiClient.createPaymentMethod(with: payment) { paymentMethod, error in
                        if let error = error {
                            NSLog("STRIPE ApplePayDelegate: ❌ createPaymentMethod error: \(error.localizedDescription)")
                            if let nsError = error as NSError? {
                                NSLog("STRIPE ApplePayDelegate: Error domain: \(nsError.domain)")
                                NSLog("STRIPE ApplePayDelegate: Error code: \(nsError.code)")
                                NSLog("STRIPE ApplePayDelegate: Error userInfo: \(nsError.userInfo)")
                            }
                            continuation.resume(throwing: error)
                        } else if let paymentMethod = paymentMethod {
                            NSLog("STRIPE ApplePayDelegate: ✅ PaymentMethod created successfully")
                            continuation.resume(returning: paymentMethod)
                        } else {
                            NSLog("STRIPE ApplePayDelegate: ❌ No payment method returned (nil)")
                            continuation.resume(throwing: StripePaymentError.setupFailed("No payment method returned"))
                        }
                    }
                }
                
                NSLog("STRIPE ApplePayDelegate: ✅ PaymentMethod created: \(paymentMethod.stripeId)")
                
                // Send PaymentMethod ID to backend to confirm PaymentIntent and cancel it
                let savedPaymentMethodId = try await BackendClient.shared.confirmPaymentIntentAndCancel(
                    clientSecret: clientSecret,
                    paymentMethodId: paymentMethod.stripeId
                )
                
                NSLog("STRIPE ApplePayDelegate: ✅ PaymentIntent confirmed and cancelled")
                NSLog("STRIPE ApplePayDelegate: ✅ Saved payment method ID: \(savedPaymentMethodId)")
                await MainActor.run {
                    completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                }
                continuation.resume(returning: savedPaymentMethodId)
            } catch {
                NSLog("STRIPE ApplePayDelegate: ❌ Error confirming PaymentIntent: \(error)")
                await MainActor.run {
                    completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                }
                continuation.resume(throwing: error)
            }
        }
    }
    
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        NSLog("STRIPE ApplePayDelegate: Payment authorization finished (authorized: \(hasAuthorized))")
        controller.dismiss()
        
        // If user cancelled (didn't authorize), resume with error
        if !hasAuthorized {
            continuation.resume(throwing: StripePaymentError.setupFailed("User cancelled payment"))
        }
    }
}

// MARK: - Errors

enum StripePaymentError: LocalizedError {
    case presentationFailed(String)
    case setupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .presentationFailed(let message):
            return "Failed to present payment sheet: \(message)"
        case .setupFailed(let message):
            return "Payment setup failed: \(message)"
        }
    }
}

