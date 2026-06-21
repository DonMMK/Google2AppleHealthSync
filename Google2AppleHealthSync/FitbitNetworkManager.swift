//
//  FitbitNetworkManager.swift
//  Google2AppleHealthSync
//
//  Created by Don Misura Kaluarachchi on 21/6/2026.
//

import Foundation
import CryptoKit

// MARK: - Fitbit Data Models
struct FitbitSleepResponse: Codable { let sleep: [FitbitSleep] }
struct FitbitSleep: Codable { let dateOfSleep: String; let levels: SleepLevels }
struct SleepLevels: Codable { let data: [SleepLevelData] }
struct SleepLevelData: Codable { let dateTime: String; let level: String; let seconds: Int }
struct FitbitHRVResponse: Codable { let hrv: [FitbitHRV] }
struct FitbitHRV: Codable { let dateTime: String; let value: HRVValue }
struct HRVValue: Codable { let dailyRmssd: Double }

// MARK: - Network Manager
class FitbitNetworkManager {
    static let shared = FitbitNetworkManager()
    private let baseURL = "https://api.fitbit.com/1.2/user/-/"
    
    // Dynamically load keys from Secrets.plist
    private var clientID: String {
        guard let filePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: filePath),
              let value = plist["CLIENT_ID"] as? String else {
            fatalError("Couldn't find ClientID in Secrets.plist")
        }
        return value
    }
    
    var reversedClientID: String {
        guard let filePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: filePath),
              let value = plist["REVERSED_CLIENT_ID"] as? String else {
            fatalError("Couldn't find REVERSED_CLIENT_ID in Secrets.plist")
        }
        return value
    }
    
    // Token storage
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "fitbit_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "fitbit_access_token") }
    }
    
    // MARK: - PKCE & OAuth Flow
    
    func getOAuthURL(codeChallenge: String) -> URL? {
            // Updated Google Health API v4 Scopes
            let scopes = [
                "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
                "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
                "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly"
            ].joined(separator: " ")
            
            let encodedScopes = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let redirectURI = "\(reversedClientID):/oauth2redirect"
            
            let urlString = "https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=\(clientID)&redirect_uri=\(redirectURI)&scope=\(encodedScopes)&code_challenge=\(codeChallenge)&code_challenge_method=S256"
            
            return URL(string: urlString)
        }
    
    func exchangeCodeForToken(authCode: String, codeVerifier: String) async throws {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let redirectURI = "\(reversedClientID):/oauth2redirect"
        
        // No client secret needed. We prove our identity using the code_verifier we generated earlier.
        let bodyString = "client_id=\(clientID)&grant_type=authorization_code&redirect_uri=\(redirectURI)&code=\(authCode)&code_verifier=\(codeVerifier)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
            print("Google Token Error: \(errorMsg)")
            throw URLError(.badServerResponse)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String
        }
        
        let tokenData = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenData.access_token
        UserDefaults.standard.set(tokenData.refresh_token, forKey: "fitbit_refresh_token")
    }
    
    // MARK: - Data Fetching
    
    private func fetch<T: Codable>(endpoint: String) async throws -> T {
        guard let token = accessToken else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: baseURL + endpoint) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func fetchSleepData(for date: Date) async throws -> FitbitSleepResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return try await fetch(endpoint: "sleep/date/\(dateString).json")
    }
    
    func fetchHRVData(for date: Date) async throws -> FitbitHRVResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return try await fetch(endpoint: "hrv/date/\(dateString).json")
    }
}

// MARK: - PKCE Crypto Helpers
extension String {
    static func generatePKCEVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    func generatePKCEChallenge() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
