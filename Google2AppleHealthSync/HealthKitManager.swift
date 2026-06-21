//
//  HealthKitManager.swift
//  Google2AppleHealthSync
//
//  Created by Don Misura Kaluarachchi on 21/6/2026.
//

import Foundation
import HealthKit

class HealthKitManager {
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()
    
    // MARK: - Authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw URLError(.cannotOpenFile)
        }
        
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let workoutType = HKObjectType.workoutType()
        
        let typesToWrite: Set = [sleepType, hrvType, hrType, energyType, workoutType]
        let typesToRead: Set = [sleepType, hrvType, hrType]
        
        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
    }
    
    // MARK: - Save Sleep Data
    func saveSleepData(fitbitData: FitbitSleepResponse) async throws {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        var sleepSamples: [HKCategorySample] = []
        let dateFormatter = ISO8601DateFormatter()
        
        for sleepSession in fitbitData.sleep {
            for levelData in sleepSession.levels.data {
                guard let startDate = dateFormatter.date(from: levelData.dateTime) else { continue }
                let endDate = startDate.addingTimeInterval(TimeInterval(levelData.seconds))
                
                let hkSleepValue: HKCategoryValueSleepAnalysis
                switch levelData.level.lowercased() {
                case "wake": hkSleepValue = .awake
                case "light": hkSleepValue = .asleepCore
                case "deep": hkSleepValue = .asleepDeep
                case "rem": hkSleepValue = .asleepREM
                default: hkSleepValue = .asleepUnspecified
                }
                
                let metadata: [String: Any] = [
                    HKMetadataKeyExternalUUID: "fitbit_sleep_\(levelData.dateTime)",
                    HKMetadataKeySyncIdentifier: "FitbitBridge"
                ]
                
                let sample = HKCategorySample(type: sleepType,
                                              value: hkSleepValue.rawValue,
                                              start: startDate,
                                              end: endDate,
                                              metadata: metadata)
                sleepSamples.append(sample)
            }
        }
        
        if !sleepSamples.isEmpty {
            try await healthStore.save(sleepSamples)
        }
    }
    
    // MARK: - Save HRV Data
    func saveHRVData(fitbitData: FitbitHRVResponse) async throws {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        var hrvSamples: [HKQuantitySample] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for hrvItem in fitbitData.hrv {
            guard let date = dateFormatter.date(from: hrvItem.dateTime) else { continue }
            let hrvQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: hrvItem.value.dailyRmssd)
            
            let metadata: [String: Any] = [
                HKMetadataKeyExternalUUID: "fitbit_hrv_\(hrvItem.dateTime)",
                "OriginalDataPoint": "RMSSD"
            ]
            
            let sample = HKQuantitySample(type: hrvType,
                                          quantity: hrvQuantity,
                                          start: date,
                                          end: date,
                                          metadata: metadata)
            hrvSamples.append(sample)
        }
        
        if !hrvSamples.isEmpty {
            try await healthStore.save(hrvSamples)
        }
    }
}
