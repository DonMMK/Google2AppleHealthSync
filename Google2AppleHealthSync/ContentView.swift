//
//  ContentView.swift
//  Google2AppleHealthSync
//
//  Created by Don Misura Kaluarachchi on 21/6/2026.
//

import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @AppStorage("lastSuccessfulSyncDate") private var lastSyncTimestamp: Double = 0
    @State private var isSyncing = false
    @State private var statusMessage = "Waiting to sync..."
    // Maintain a reference to the auth session so it doesn't deallocate instantly
    @State private var authSession: ASWebAuthenticationSession?
    
    private var formattedLastSync: String {
        if lastSyncTimestamp == 0 { return "Never" }
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 50))
                        .foregroundStyle(isSyncing ? .blue : .green)
                        .symbolEffect(.bounce, options: .repeating, value: isSyncing)
                    
                    Text("Data Bridge Active")
                        .font(.headline)
                    
                    Text("Last Sync: \(formattedLastSync)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                
                Divider()
                
                VStack(spacing: 16) {
                    Button(action: connectFitbit) {
                        Label("Connect Fitbit Account", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    
                    Button(action: performManualSync) {
                        Label(isSyncing ? "Syncing..." : "Force Manual Sync", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isSyncing)
                }
                .padding(.horizontal, 40)
                
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Fitbit to Apple")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    try await HealthKitManager.shared.requestAuthorization()
                    statusMessage = "HealthKit Authorized."
                } catch {
                    statusMessage = "HealthKit Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func connectFitbit() {
        // 1. Generate the PKCE security strings
        let codeVerifier = String.generatePKCEVerifier()
        let codeChallenge = codeVerifier.generatePKCEChallenge()
        
        guard let authURL = FitbitNetworkManager.shared.getOAuthURL(codeChallenge: codeChallenge) else {
            statusMessage = "Invalid Auth URL"
            return
        }
        
        statusMessage = "Launching Google login..."
        
        // 2. Launch the session using the Reversed Client ID scheme
        let scheme = FitbitNetworkManager.shared.reversedClientID
        
        authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { callbackURL, error in
            
            if let error = error {
                guard (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue else {
                    statusMessage = "Login canceled."
                    return
                }
                statusMessage = "Auth Error: \(error.localizedDescription)"
                return
            }
            
            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                  let authCode = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                statusMessage = "Failed to parse callback URL."
                return
            }
            
            statusMessage = "Exchanging code for token..."
            
            // 3. Pass both the code AND the verifier to complete the PKCE loop
            Task {
                do {
                    try await FitbitNetworkManager.shared.exchangeCodeForToken(authCode: authCode, codeVerifier: codeVerifier)
                    statusMessage = "Fitbit Successfully Linked via Google!"
                } catch {
                    statusMessage = "Token Exchange Failed."
                }
            }
        }
        
        let contextProvider = AuthContextProvider()
        authSession?.presentationContextProvider = contextProvider
        authSession?.start()
    }
    private func performManualSync() {
            isSyncing = true
            statusMessage = "Fetching data from Google Health..."
            
            Task {
                do {
                    // Fetch the last 24 hours
                    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                    
                    let sleepData = try await FitbitNetworkManager.shared.fetchSleepData(for: yesterday)
                    let hrvData = try await FitbitNetworkManager.shared.fetchHRVData(for: yesterday)
                    
                    statusMessage = "Writing to Apple Health..."
                    
                    try await HealthKitManager.shared.saveSleepData(fitbitData: sleepData)
                    try await HealthKitManager.shared.saveHRVData(fitbitData: hrvData)
                    
                    lastSyncTimestamp = Date().timeIntervalSince1970
                    statusMessage = "Sync Complete!"
                    
                } catch {
                    statusMessage = "Sync Failed: \(error.localizedDescription)"
                }
                
                isSyncing = false
            }
        }
}

// MARK: - Auth Context Provider
class AuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

#Preview {
    ContentView()
}
