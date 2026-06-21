//
//  FitbitNetworkManager.swift
//  Google2AppleHealthSync
//
//  Created by Don Misura Kaluarachchi on 21/6/2026.
//

import Foundation

// MARK: - Fitbit Data Models
struct FitbitSleepResponse: Codable {
    let sleep: [FitbitSleep]
}
struct FitbitSleep: Codable {
    let dateOfSleep: String
    let levels: SleepLevels
}
struct SleepLevels: Codable {
    let data: [SleepLevelData]
}
struct SleepLevelData: Codable {
    let dateTime: String
    let level: String
    let seconds: Int
}
struct FitbitHRVResponse: Codable {
    let hrv: [FitbitHRV]
}
struct FitbitHRV: Codable {
    let dateTime: String
    let value: HRVValue
}
struct HRVValue: Codable {
    let dailyRmssd: Double
}

// MARK: - Network Manager
class FitbitNetworkManager {
    static let shared = FitbitNetworkManager()
    private let baseURL = "https://api.fitbit.com/1.2/user/-/"
    
    private var accessToken: String? {
        return UserDefaults.standard.string(forKey: "mock_access_token")
    }
    
    func getOAuthURL() -> URL {
        let clientID = "YOUR_CLIENT_ID"
        let scope = "heartrate%20sleep%20activity"
        return URL(string: "https://www.fitbit.com/oauth2/authorize?response_type=code&client_id=\(clientID)&redirect_uri=your-app-scheme://callback&scope=\(scope)")!
    }
    
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
