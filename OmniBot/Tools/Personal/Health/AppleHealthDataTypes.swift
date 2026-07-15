import Foundation
import HealthKit

nonisolated enum AppleHealthQuantityType: String, CaseIterable, Sendable {
    enum Aggregation: String, Sendable {
        case cumulative
        case discrete
    }

    case stepCount = "step_count"
    case distanceWalkingRunning = "distance_walking_running"
    case distanceCycling = "distance_cycling"
    case distanceSwimming = "distance_swimming"
    case activeEnergyBurned = "active_energy_burned"
    case basalEnergyBurned = "basal_energy_burned"
    case appleExerciseTime = "apple_exercise_time"
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case walkingHeartRateAverage = "walking_heart_rate_average"
    case heartRateVariabilitySDNN = "heart_rate_variability_sdnn"
    case respiratoryRate = "respiratory_rate"
    case oxygenSaturation = "oxygen_saturation"
    case bodyMass = "body_mass"
    case height
    case bodyMassIndex = "body_mass_index"
    case bodyTemperature = "body_temperature"
    case bloodGlucose = "blood_glucose"
    case bloodPressureSystolic = "blood_pressure_systolic"
    case bloodPressureDiastolic = "blood_pressure_diastolic"

    var healthKitType: HKQuantityType {
        switch self {
        case .stepCount: HKQuantityType(.stepCount)
        case .distanceWalkingRunning: HKQuantityType(.distanceWalkingRunning)
        case .distanceCycling: HKQuantityType(.distanceCycling)
        case .distanceSwimming: HKQuantityType(.distanceSwimming)
        case .activeEnergyBurned: HKQuantityType(.activeEnergyBurned)
        case .basalEnergyBurned: HKQuantityType(.basalEnergyBurned)
        case .appleExerciseTime: HKQuantityType(.appleExerciseTime)
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .walkingHeartRateAverage: HKQuantityType(.walkingHeartRateAverage)
        case .heartRateVariabilitySDNN: HKQuantityType(.heartRateVariabilitySDNN)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .oxygenSaturation: HKQuantityType(.oxygenSaturation)
        case .bodyMass: HKQuantityType(.bodyMass)
        case .height: HKQuantityType(.height)
        case .bodyMassIndex: HKQuantityType(.bodyMassIndex)
        case .bodyTemperature: HKQuantityType(.bodyTemperature)
        case .bloodGlucose: HKQuantityType(.bloodGlucose)
        case .bloodPressureSystolic: HKQuantityType(.bloodPressureSystolic)
        case .bloodPressureDiastolic: HKQuantityType(.bloodPressureDiastolic)
        }
    }

    var unit: HKUnit {
        switch self {
        case .stepCount, .bodyMassIndex:
            .count()
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .height:
            .meter()
        case .activeEnergyBurned, .basalEnergyBurned:
            .kilocalorie()
        case .appleExerciseTime:
            .minute()
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage, .respiratoryRate:
            .count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN:
            .secondUnit(with: .milli)
        case .oxygenSaturation:
            .percent()
        case .bodyMass:
            .gramUnit(with: .kilo)
        case .bodyTemperature:
            .degreeCelsius()
        case .bloodGlucose:
            .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            .millimeterOfMercury()
        }
    }

    var unitSymbol: String {
        switch self {
        case .stepCount: "count"
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .height: "m"
        case .activeEnergyBurned, .basalEnergyBurned: "kcal"
        case .appleExerciseTime: "min"
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage: "count/min"
        case .heartRateVariabilitySDNN: "ms"
        case .respiratoryRate: "breaths/min"
        case .oxygenSaturation: "%"
        case .bodyMass: "kg"
        case .bodyMassIndex: "count"
        case .bodyTemperature: "degC"
        case .bloodGlucose: "mg/dL"
        case .bloodPressureSystolic, .bloodPressureDiastolic: "mmHg"
        }
    }

    var aggregation: Aggregation {
        switch self {
        case .stepCount,
             .distanceWalkingRunning,
             .distanceCycling,
             .distanceSwimming,
             .activeEnergyBurned,
             .basalEnergyBurned,
             .appleExerciseTime:
            .cumulative
        default:
            .discrete
        }
    }
}

nonisolated enum AppleHealthCategoryType: String, CaseIterable, Sendable {
    case sleepAnalysis = "sleep_analysis"
    case mindfulSession = "mindful_session"
    case appleStandHour = "apple_stand_hour"

    var healthKitType: HKCategoryType {
        switch self {
        case .sleepAnalysis: HKCategoryType(.sleepAnalysis)
        case .mindfulSession: HKCategoryType(.mindfulSession)
        case .appleStandHour: HKCategoryType(.appleStandHour)
        }
    }

    func valueName(_ value: Int) -> String {
        switch self {
        case .sleepAnalysis:
            switch value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue: "in_bed"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: "asleep_unspecified"
            case HKCategoryValueSleepAnalysis.awake.rawValue: "awake"
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: "asleep_core"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: "asleep_deep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: "asleep_rem"
            default: "unknown_\(value)"
            }
        case .mindfulSession:
            value == 0 ? "present" : "unknown_\(value)"
        case .appleStandHour:
            switch value {
            case HKCategoryValueAppleStandHour.stood.rawValue: "stood"
            case HKCategoryValueAppleStandHour.idle.rawValue: "idle"
            default: "unknown_\(value)"
            }
        }
    }
}

nonisolated enum AppleHealthStatistic: String, CaseIterable, Sendable {
    case sum
    case average
    case minimum
    case maximum

    var healthKitOption: HKStatisticsOptions {
        switch self {
        case .sum: .cumulativeSum
        case .average: .discreteAverage
        case .minimum: .discreteMin
        case .maximum: .discreteMax
        }
    }

    func quantity(from statistics: HKStatistics) -> HKQuantity? {
        switch self {
        case .sum: statistics.sumQuantity()
        case .average: statistics.averageQuantity()
        case .minimum: statistics.minimumQuantity()
        case .maximum: statistics.maximumQuantity()
        }
    }
}
