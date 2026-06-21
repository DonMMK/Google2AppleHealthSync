//
//  Google2AppleHealthSyncApp.swift
//  Google2AppleHealthSync
//
//  Created by Don Misura Kaluarachchi on 21/6/2026.
//

import SwiftUI
import BackgroundTasks

@main
struct Google2AppleHealthSyncApp: App {
    // Inject the App Delegate to handle background tasks
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - App Delegate for Background Tasks
class AppDelegate: NSObject, UIApplicationDelegate {
    // Ensure this exactly matches the identifier in your Info.plist
    let backgroundTaskIdentifier = "com.Don.Google2AppleHealthSync"
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Register the background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        return true
    }
    
    // Schedule the next background task
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Request a fetch no earlier than 4 hours from now to preserve battery
        request.earliestBeginDate = Date(timeIntervalSinceNow: 14400)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error.localizedDescription)")
        }
    }
    
    // Execute the Sync
    func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh() // Always schedule the next one immediately
        
        task.expirationHandler = {
            // iOS is killing the task early. Cancel network requests here if needed.
        }
        
        Task {
            do {
                // Fetch last 24 hours
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                
                // Fetch and Save (Assuming your managers are implemented)
                let sleepData = try await FitbitNetworkManager.shared.fetchSleepData(for: yesterday)
                let hrvData = try await FitbitNetworkManager.shared.fetchHRVData(for: yesterday)
                
                try await HealthKitManager.shared.saveSleepData(fitbitData: sleepData)
                try await HealthKitManager.shared.saveHRVData(fitbitData: hrvData)
                
                // Update the last sync date in UserDefaults
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSuccessfulSyncDate")
                
                task.setTaskCompleted(success: true)
                
            } catch {
                print("Background sync failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}
