import Foundation
import UIKit
import Combine
import AuthenticationServices
import CryptoKit
import Auth

/// Manages Sign in with Apple authentication flow
@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticating = false
    @Published var authenticationError: String?
    
    private var currentNonce: String?
    
    private override init() {
        super.init()
    }
    
    /// Start Sign in with Apple flow
    /// - Returns: The authenticated session, or nil if cancelled/failed
    func signInWithApple() async throws -> Session {
        isAuthenticating = true
        authenticationError = nil
        defer { isAuthenticating = false }
        
        // Generate nonce for security
        let nonce = randomNonceString()
        currentNonce = nonce
        
        // Create Apple ID request
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        // Perform authorization
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        
        // Use continuation to bridge async/await with delegate pattern
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            authorizationController.performRequests()
        }
    }
    
    // MARK: - Private
    
    private var continuation: CheckedContinuation<Session, Error>?
    
    // Generate random nonce string
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    // SHA256 hash for nonce
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            let error = NSError(domain: "AuthenticationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get Apple ID token"])
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }
        
        // Clear nonce
        currentNonce = nil
        
        // Extract email from Apple credential (only available on first sign-in)
        // On subsequent sign-ins, this will be nil
        let email = appleIDCredential.email
        
        // Sign in with Supabase
        // Capture continuation to avoid multiple resumes
        guard let cont = continuation else {
            NSLog("AUTH: ⚠️ No continuation found")
            return
        }
        continuation = nil // Clear immediately to prevent double resume
        
        Task {
            do {
                let session = try await BackendClient.shared.signInWithApple(
                    idToken: idTokenString,
                    nonce: nonce,
                    email: email  // Pass email if available (real email on first sign-in)
                )
                cont.resume(returning: session)
                NSLog("AUTH: ✅ Successfully signed in with Apple")
                if let email = email {
                    NSLog("AUTH: 📧 Email from Apple credential: \(email)")
                } else {
                    NSLog("AUTH: 📧 No email in credential (subsequent sign-in)")
                }
            } catch {
                NSLog("AUTH: ❌ Failed to sign in with Supabase: \(error.localizedDescription)")
                cont.resume(throwing: error)
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        NSLog("AUTH: ❌ Apple authorization failed: \(error.localizedDescription)")
        guard let cont = continuation else {
            NSLog("AUTH: ⚠️ No continuation found in error handler")
            return
        }
        continuation = nil // Clear immediately to prevent double resume
        currentNonce = nil
        cont.resume(throwing: error)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window's scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            // Fallback: create a new window if needed
            return UIWindow()
        }
        return window
    }
}

