//
//  ContentView.swift
//  Google2AppleHealthSync
//
//  Created by Don Misura Kaluarachchi on 21/6/2026.
//

import SwiftUI
import AuthenticationServices

struct ContentView: View {
    // Read the sync date directly from UserDefaults
    @AppStorage("lastSuccessfulSyncDate") private var lastSyncTimestamp: Double = 0
    @State private var isSyncing = false
    @State private var statusMessage = "Waiting to sync..."
    
    private var formattedLastSync: String {
        if lastSyncTimestamp == 0 {
            return "Never"
        }
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                
                // Status Header
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
                
                // Actions
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
                
                // Feedback Console
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
                // Request HealthKit permissions as soon as the view loads
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
        // Here you will implement ASWebAuthenticationSession using the URL from FitbitNetworkManager
        statusMessage = "Launching OAuth flow..."
        
        /* Example Implementation for later:
         let authURL = FitbitNetworkManager.shared.getOAuthURL()
         let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "your-app-scheme") { callbackURL, error in
             // Handle token extraction and save to Keychain here
         }
         session.presentationContextProvider = self // Requires extending ASWebAuthenticationPresentationContextProviding
         session.start()
         */
    }
    
    private func performManualSync() {
        isSyncing = true
        statusMessage = "Fetching data from Fitbit..."
        
        Task {
            do {
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                
                // Fetch
                let sleepData = try await FitbitNetworkManager.shared.fetchSleepData(for: yesterday)
                let hrvData = try await FitbitNetworkManager.shared.fetchHRVData(for: yesterday)
                
                statusMessage = "Writing to HealthKit..."
                
                // Save
                try await HealthKitManager.shared.saveSleepData(fitbitData: sleepData)
                try await HealthKitManager.shared.saveHRVData(fitbitData: hrvData)
                
                // Update State
                lastSyncTimestamp = Date().timeIntervalSince1970
                statusMessage = "Sync Complete!"
                
            } catch {
                statusMessage = "Sync Failed: \(error.localizedDescription)"
            }
            
            isSyncing = false
        }
    }
}

#Preview {
    ContentView()
}
