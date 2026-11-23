import XCTest
@testable import TrotWalkCore

final class IntervalPlanTests: XCTestCase {
    func testSegmentsAlternateWithoutEnd() {
        let plan = IntervalPlan.standard
        XCTAssertEqual(plan.setDuration, 360)
        XCTAssertEqual(plan.segment(index: 0).phase, .brisk)
        XCTAssertEqual(plan.segment(index: 1).phase, .easy)
        XCTAssertEqual(plan.segment(index: 101).start, 50 * 360 + 180)
        XCTAssertEqual(plan.segment(index: 101).setNumber, 51)
        for i in 0..<50 {
            XCTAssertEqual(plan.segment(index: i).end, plan.segment(index: i + 1).start)
        }
    }

    func testPositionMatchesSegments() {
        let plan = IntervalPlan(briskDuration: 120, easyDuration: 180)
        for i in 0..<20 {
            let segment = plan.segment(index: i)
            XCTAssertEqual(plan.position(at: segment.start)?.segment, segment)
            XCTAssertEqual(plan.position(at: segment.start + segment.duration / 2)?.segment, segment)
        }
        XCTAssertEqual(plan.position(at: 130)?.segment.phase, .easy)
        XCTAssertEqual(plan.position(at: 130)?.remainingInSegment, 170)
        XCTAssertNotNil(plan.position(at: 10 * 3600))
        XCTAssertNil(plan.position(at: -1))
    }

    func testBriskTimeUpTo() {
        let plan = IntervalPlan(briskDuration: 120, easyDuration: 180)
        XCTAssertEqual(plan.briskTime(upTo: 0), 0)
        XCTAssertEqual(plan.briskTime(upTo: 60), 60)
        XCTAssertEqual(plan.briskTime(upTo: 200), 120)
        XCTAssertEqual(plan.briskTime(upTo: 330), 150)
        XCTAssertEqual(plan.briskTime(upTo: 900), 360)
    }
}

final class CueScheduleTests: XCTestCase {
    let plan = IntervalPlan(briskDuration: 180, easyDuration: 180)

    func testCuesAroundSwitch() {
        let schedule = CueSchedule(plan: plan, milestone: nil)
        XCTAssertEqual(schedule.cues(from: 0, to: 1), [])
        XCTAssertEqual(schedule.cues(from: 169, to: 170), [.switchSoon])
        XCTAssertEqual(schedule.cues(from: 174, to: 175), [.switchVerySoon])
        XCTAssertEqual(schedule.cues(from: 179, to: 180), [.easyStart])
        XCTAssertEqual(schedule.cues(from: 359, to: 360), [.briskStart])
        // 終わりはなく、ずっと続く
        XCTAssertEqual(schedule.cues(from: 7199, to: 7200), [.briskStart])
    }

    func testLargeJumpReturnsOnlyLatestSwitchCue() {
        let schedule = CueSchedule(plan: plan, milestone: nil)
        XCTAssertEqual(schedule.cues(from: 160, to: 200), [.easyStart])
        XCTAssertEqual(schedule.cues(from: 160, to: 176), [.switchVerySoon])
    }

    func testWarningsCanBeDisabled() {
        let schedule = CueSchedule(plan: plan, warningsEnabled: false, milestone: nil)
        XCTAssertEqual(schedule.cues(from: 165, to: 179), [])
        XCTAssertEqual(schedule.cues(from: 179, to: 180), [.easyStart])
    }

    func testRecommendedMilestoneOnceAlongsideSwitch() {
        let schedule = CueSchedule(plan: plan)
        // 30分ちょうどは速歩の開始とも重なる
        XCTAssertEqual(schedule.cues(from: 1799, to: 1800), [.briskStart, .recommendedReached])
        XCTAssertEqual(schedule.cues(from: 1800, to: 1801), [])
        XCTAssertEqual(schedule.cues(from: 3599, to: 3600), [.briskStart])
    }
}

final class TempoPatternTests: XCTestCase {
    func testFourOnFourOff() {
        let pattern = (0..<16).map(TempoCoach.isPulseBeat)
        XCTAssertEqual(pattern, [true, true, true, true, false, false, false, false,
                                 true, true, true, true, false, false, false, false])
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
        XCTAssertEqual(coach.pulseInterval(for: .brisk), 60 / 116, accuracy: 0.0001)
        XCTAssertEqual(coach.pulseInterval(for: .easy), 60 / 96, accuracy: 0.0001)
        XCTAssertEqual(coach.pulseInterval(for: .brisk, stepsPerPulse: 2), 120 / 116, accuracy: 0.0001)
    }

    func testStartCadenceFromCalibrationIsClamped() {
        XCTAssertEqual(TempoCoach(zones: nil, briskStart: 124).briskCadence, 124)
        XCTAssertEqual(TempoCoach(zones: nil, briskStart: 200).briskCadence, 140)
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

final class PersonalCalibrationTests: XCTestCase {
    func testDefaults() {
        let calibration = PersonalCalibration()
        XCTAssertEqual(calibration.briskReserve, 0.70)
        XCTAssertNil(calibration.briskStartCadence)
    }

    func testEasyRaisesTargetAndKeepsFinalCadence() {
        let next = PersonalCalibration().updated(feedback: .easy, finalBriskCadence: 124)
        XCTAssertEqual(next.briskReserve, 0.73, accuracy: 0.0001)
        XCTAssertEqual(next.briskStartCadence, 124)
    }

    func testHardLowersTargetAndCadence() {
        let next = PersonalCalibration().updated(feedback: .hard, finalBriskCadence: 124)
        XCTAssertEqual(next.briskReserve, 0.67, accuracy: 0.0001)
        XCTAssertEqual(next.briskStartCadence, 120)
    }

    func testNoAnswerOnlyRemembersCadence() {
        let next = PersonalCalibration().updated(feedback: nil, finalBriskCadence: 120)
        XCTAssertEqual(next.briskReserve, 0.70)
        XCTAssertEqual(next.briskStartCadence, 120)
    }

    func testReserveIsClamped() {
        var calibration = PersonalCalibration()
        for _ in 0..<20 { calibration = calibration.updated(feedback: .easy, finalBriskCadence: nil) }
        XCTAssertEqual(calibration.briskReserve, 0.80, accuracy: 0.0001)
        for _ in 0..<20 { calibration = calibration.updated(feedback: .hard, finalBriskCadence: 100) }
        XCTAssertEqual(calibration.briskReserve, 0.60, accuracy: 0.0001)
        XCTAssertEqual(calibration.briskStartCadence, 100)
    }

    func testZonesUseCalibratedReserve() {
        let zones = HeartRateZones(restingHeartRate: 60, maxHeartRate: 160, briskReserve: 0.65)
        XCTAssertEqual(zones.briskLowerBound, 125, accuracy: 0.001)
        XCTAssertEqual(zones.briskUpperBound, 140, accuracy: 0.001)
        XCTAssertEqual(zones.easyUpperBound, 100, accuracy: 0.001)
    }
}
