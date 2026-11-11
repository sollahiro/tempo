import XCTest
@testable import TrotWalkCore

final class IntervalPlanTests: XCTestCase {
    func testStandardPlanIs30MinutesWith15MinutesBrisk() {
        let plan = IntervalPlan.standard
        XCTAssertEqual(plan.totalDuration, 30 * 60)
        XCTAssertEqual(plan.totalBriskDuration, 15 * 60)
        XCTAssertEqual(plan.segments.count, 10)
        XCTAssertEqual(plan.segments.first?.phase, .brisk)
        XCTAssertEqual(plan.segments.last?.phase, .easy)
    }

    func testSetsAreClamped() {
        XCTAssertEqual(IntervalPlan(sets: 0).sets, 1)
        XCTAssertEqual(IntervalPlan(sets: 99).sets, 10)
    }

    func testPositionMatchesSegments() {
        let plan = IntervalPlan(briskDuration: 120, easyDuration: 180, sets: 3)
        for segment in plan.segments {
            let mid = segment.start + segment.duration / 2
            XCTAssertEqual(plan.position(at: mid)?.segment, segment)
            XCTAssertEqual(plan.position(at: segment.start)?.segment, segment)
        }
        XCTAssertEqual(plan.position(at: 130)?.segment.phase, .easy)
        XCTAssertEqual(plan.position(at: 130)?.remainingInSegment, 170)
        XCTAssertNil(plan.position(at: plan.totalDuration))
        XCTAssertNil(plan.position(at: -1))
    }

    func testBriskTimeUpTo() {
        let plan = IntervalPlan(briskDuration: 120, easyDuration: 180, sets: 3)
        XCTAssertEqual(plan.briskTime(upTo: 60), 60)
        XCTAssertEqual(plan.briskTime(upTo: 200), 120)
        XCTAssertEqual(plan.briskTime(upTo: 330), 150)
        XCTAssertEqual(plan.briskTime(upTo: 10_000), 360)
    }
}

final class CueScheduleTests: XCTestCase {
    let plan = IntervalPlan(briskDuration: 180, easyDuration: 180, sets: 2)

    func testCuesAtBoundaries() {
        let schedule = CueSchedule(plan: plan)
        XCTAssertNil(schedule.cue(from: 0, to: 1))
        XCTAssertEqual(schedule.cue(from: 169, to: 170), .switchSoon)
        XCTAssertEqual(schedule.cue(from: 179, to: 180), .easyStart)
        XCTAssertEqual(schedule.cue(from: 359, to: 360), .briskStart)
        XCTAssertEqual(schedule.cue(from: 719, to: 720), .finished)
        XCTAssertNil(schedule.cue(from: 720, to: 721))
    }

    func testLargeJumpReturnsOnlyLatestCue() {
        let schedule = CueSchedule(plan: plan)
        // 予告と緩歩開始の両方をまたいだら、緩歩開始だけ
        XCTAssertEqual(schedule.cue(from: 160, to: 200), .easyStart)
    }

    func testWarningCanBeDisabled() {
        let schedule = CueSchedule(plan: plan, warningLead: 0)
        XCTAssertNil(schedule.cue(from: 169, to: 171))
        XCTAssertFalse(schedule.events.contains { $0.cue == .switchSoon })
    }
}

final class IntensityCoachTests: XCTestCase {
    let plan = IntervalPlan.standard
    // 安静時 60, 最大 160 → 速歩下限 130, 速歩上限 145, 緩歩上限 100
    let zones = HeartRateZones(restingHeartRate: 60, maxHeartRate: 160)

    func testZones() {
        XCTAssertEqual(zones.briskLowerBound, 130, accuracy: 0.001)
        XCTAssertEqual(zones.briskUpperBound, 145, accuracy: 0.001)
        XCTAssertEqual(zones.easyUpperBound, 100, accuracy: 0.001)
        XCTAssertEqual(HeartRateZones(age: 40, restingHeartRate: 60).maxHeartRate, 180, accuracy: 0.001)
    }

    private func run(_ coach: inout IntensityCoach, heartRate: Double, from: Int, to: Int) -> [(Int, HapticCue)] {
        var cues: [(Int, HapticCue)] = []
        for t in from...to {
            let now = TimeInterval(t)
            if let position = plan.position(at: now),
               let cue = coach.evaluate(heartRate: heartRate, position: position, now: now) {
                cues.append((t, cue))
            }
        }
        return cues
    }

    func testNoCueDuringGracePeriod() {
        var coach = IntensityCoach(zones: zones)
        XCTAssertTrue(run(&coach, heartRate: 90, from: 0, to: 59).isEmpty)
    }

    func testSpeedUpAfterSustainedLowHeartRateThenRateLimited() {
        var coach = IntensityCoach(zones: zones)
        let cues = run(&coach, heartRate: 110, from: 0, to: 169)
        XCTAssertEqual(cues.map(\.1), [.speedUp, .speedUp])
        XCTAssertEqual(cues.map(\.0), [80, 140])
    }

    func testNoCueWhenInRange() {
        var coach = IntensityCoach(zones: zones)
        XCTAssertTrue(run(&coach, heartRate: 135, from: 0, to: 179).isEmpty)
    }

    func testSlowDownDuringEasyOnlyAfterLongerGrace() {
        var coach = IntensityCoach(zones: zones)
        let cues = run(&coach, heartRate: 120, from: 180, to: 359)
        XCTAssertEqual(cues.first?.1, .slowDown)
        XCTAssertEqual(cues.first?.0, 180 + 90 + 20)
    }
}

final class TempoCoachTests: XCTestCase {
    let plan = IntervalPlan.standard
    // 速歩下限 130, 速歩上限 145, 緩歩上限 100
    let zones = HeartRateZones(restingHeartRate: 60, maxHeartRate: 160)

    private func run(_ coach: inout TempoCoach, heartRate: Double, from: Int, to: Int) -> [(Int, HapticCue)] {
        var changes: [(Int, HapticCue)] = []
        for t in from...to {
            let now = TimeInterval(t)
            if let position = plan.position(at: now),
               let change = coach.update(heartRate: heartRate, position: position, now: now) {
                changes.append((t, change))
            }
        }
        return changes
    }

    func testPulseInterval() {
        let coach = TempoCoach(zones: nil)
        XCTAssertEqual(coach.pulseInterval(for: .brisk), 120 / 116, accuracy: 0.0001)
        XCTAssertEqual(coach.pulseInterval(for: .easy), 120 / 96, accuracy: 0.0001)
    }

    func testFixedTempoWithoutZones() {
        var coach = TempoCoach(zones: nil)
        XCTAssertTrue(run(&coach, heartRate: 90, from: 0, to: 179).isEmpty)
        XCTAssertEqual(coach.briskCadence, 116)
    }

    func testBriskTempoRisesWhenHeartRateIsLow() {
        var coach = TempoCoach(zones: zones)
        let changes = run(&coach, heartRate: 110, from: 0, to: 179)
        // 60秒は待ち、その後30秒ごと: 60, 90, 120, 150
        XCTAssertEqual(changes.map(\.0), [60, 90, 120, 150])
        XCTAssertTrue(changes.allSatisfy { $0.1 == .speedUp })
        XCTAssertEqual(coach.briskCadence, 132)
    }

    func testBriskTempoIsCarriedToNextSetAndClamped() {
        var coach = TempoCoach(zones: zones)
        _ = run(&coach, heartRate: 110, from: 0, to: 1799)
        XCTAssertEqual(coach.briskCadence, 140) // 上限
    }

    func testTempoStaysWhenInRange() {
        var coach = TempoCoach(zones: zones)
        XCTAssertTrue(run(&coach, heartRate: 135, from: 0, to: 179).isEmpty)
    }

    func testEasyTempoDropsWhenHeartRateStaysHigh() {
        var coach = TempoCoach(zones: zones)
        let changes = run(&coach, heartRate: 120, from: 180, to: 359)
        XCTAssertEqual(changes.first?.0, 270)
        XCTAssertTrue(changes.allSatisfy { $0.1 == .slowDown })
        XCTAssertLessThan(coach.easyCadence, 96)
    }
}
