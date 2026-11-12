import Foundation
import HealthKit
import TrotWalkCore

/// 強度ガイドに使う年齢と安静時心拍を Health から読む。
enum HealthProfile {
    /// 安静時心拍が記録されていないときの仮の値
    static let fallbackRestingHeartRate: Double = 65

    static func zones(store: HKHealthStore, briskReserve: Double) async -> HeartRateZones? {
        guard let age = age(store: store) else { return nil }
        let resting = await latestRestingHeartRate(store: store) ?? fallbackRestingHeartRate
        return HeartRateZones(age: age, restingHeartRate: resting, briskReserve: briskReserve)
    }

    static func age(store: HKHealthStore) -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthday = Calendar.current.date(from: components)
        else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: .now).year
    }

    static func latestRestingHeartRate(store: HKHealthStore) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.restingHeartRate),
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .beatsPerMinute)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}

extension HKUnit {
    static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
}
