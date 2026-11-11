import Foundation
import HealthKit
import Observation
import TrotWalkCore

/// ワークアウトの結果（終了画面に出すもの）。
struct WorkoutSummary: Equatable {
    var totalTime: TimeInterval
    var briskTime: TimeInterval
    var distanceMeters: Double?
}

/// HealthKit のワークアウトセッションを動かし、時間に合わせて振動を鳴らす。
/// 記録は屋外ウォーキングとして Fitness と Health に保存される。
@MainActor
@Observable
final class WorkoutManager: NSObject {
    enum State: Equatable {
        case idle
        case preparing
        case running
        case paused
        case ending
        case finished
    }

    private(set) var state: State = .idle
    private(set) var settings = WalkSettings()
    private(set) var elapsed: TimeInterval = 0
    private(set) var heartRate: Double?
    private(set) var distanceMeters: Double?
    private(set) var zones: HeartRateZones?
    private(set) var summary: WorkoutSummary?
    private(set) var errorMessage: String?

    var position: IntervalPosition? { settings.plan.position(at: elapsed) }

    let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var schedule: CueSchedule?
    @ObservationIgnored private var coach: IntensityCoach?
    @ObservationIgnored private var lastTick: TimeInterval = 0
    @ObservationIgnored private var currentSegment: IntervalSegment?
    @ObservationIgnored private var currentSegmentStart: Date?
    private let haptics = HapticPlayer()

    // MARK: - 権限

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        let toRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKCharacteristicType(.dateOfBirth),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: toShare, read: toRead)
        } catch {
            errorMessage = "ヘルスケアへのアクセスを確認できませんでした"
        }
    }

    // MARK: - 操作

    func start(with settings: WalkSettings) async {
        guard state == .idle else { return }
        state = .preparing
        errorMessage = nil
        self.settings = settings
        elapsed = 0
        lastTick = 0
        heartRate = nil
        distanceMeters = nil
        summary = nil

        await requestAuthorization()

        zones = settings.intensityGuideEnabled ? await HealthProfile.zones(store: healthStore) : nil
        coach = zones.map { IntensityCoach(zones: $0) }
        schedule = settings.cueSchedule

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            try await builder.addMetadata([
                HKMetadataKeyIndoorWorkout: false,
                MetadataKey.briskSeconds: settings.briskDuration,
                MetadataKey.easySeconds: settings.easyDuration,
                MetadataKey.plannedSets: settings.sets,
            ])

            currentSegment = settings.plan.segments.first
            currentSegmentStart = startDate
            state = .running
            haptics.play(.briskStart)
            startTicker()
        } catch {
            errorMessage = "ワークアウトを開始できませんでした"
            session?.end()
            cleanUp()
            state = .idle
        }
    }

    func togglePause() {
        switch state {
        case .running:
            session?.pause()
            haptics.play(.paused)
        case .paused:
            session?.resume()
            haptics.play(.resumed)
        default:
            break
        }
    }

    /// 途中で終える、またはプランが終わったときに呼ぶ。記録は保存される。
    func end() {
        guard state == .running || state == .paused else { return }
        state = .ending
        ticker?.cancel()
        recordCurrentSegment(endingAt: Date())
        session?.end()
    }

    /// 終了画面を閉じてスタートに戻る。
    func reset() {
        guard state == .finished else { return }
        summary = nil
        state = .idle
    }

    // MARK: - 時間の進行

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard state == .running, let builder else { return }
        // elapsedTime は一時停止中の時間を含まない
        let now = builder.elapsedTime
        elapsed = now
        defer { lastTick = now }

        if let cue = schedule?.cue(from: lastTick, to: now) {
            if cue == .finished {
                haptics.play(.finished)
                end()
                return
            }
            haptics.play(cue)
        } else if let position, let heartRate,
                  let cue = coach?.evaluate(heartRate: heartRate, position: position, now: now) {
            haptics.play(cue)
        }

        if let position, position.segment != currentSegment {
            let date = Date()
            recordCurrentSegment(endingAt: date)
            currentSegment = position.segment
            currentSegmentStart = date
        }
    }

    /// 速歩・緩歩の区間を、ワークアウトのセグメントとして残す。
    private func recordCurrentSegment(endingAt end: Date) {
        guard let builder, let segment = currentSegment, let start = currentSegmentStart, end > start else { return }
        let event = HKWorkoutEvent(
            type: .segment,
            dateInterval: DateInterval(start: start, end: end),
            metadata: [
                MetadataKey.phase: segment.phase.rawValue,
                MetadataKey.setNumber: segment.setNumber,
            ]
        )
        builder.addWorkoutEvents([event]) { _, _ in }
        currentSegment = nil
        currentSegmentStart = nil
    }

    private func finishWorkout(at date: Date) async {
        guard let builder else { return }
        let total = builder.elapsedTime
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
        } catch {
            errorMessage = "記録の保存に失敗しました"
        }
        summary = WorkoutSummary(
            totalTime: total,
            briskTime: settings.plan.briskTime(upTo: total),
            distanceMeters: distanceMeters
        )
        cleanUp()
        state = .finished
    }

    private func cleanUp() {
        ticker?.cancel()
        ticker = nil
        session = nil
        builder = nil
        schedule = nil
        coach = nil
        currentSegment = nil
        currentSegmentStart = nil
    }

    // MARK: - デリゲートから

    fileprivate func sessionChanged(to newState: HKWorkoutSessionState, date: Date) {
        switch newState {
        case .running where state == .paused:
            state = .running
        case .paused where state == .running:
            state = .paused
        case .ended:
            Task { await finishWorkout(at: date) }
        default:
            break
        }
    }

    fileprivate func sessionFailed() {
        errorMessage = "ワークアウトが中断されました"
        if state == .running || state == .paused {
            end()
        }
    }

    fileprivate func updateStatistics(heartRate: Double?, distance: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let distance { distanceMeters = distance }
    }
}

enum MetadataKey {
    static let phase = "TrotWalkPhase"
    static let setNumber = "TrotWalkSet"
    static let briskSeconds = "TrotWalkBriskSeconds"
    static let easySeconds = "TrotWalkEasySeconds"
    static let plannedSets = "TrotWalkPlannedSets"
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.sessionChanged(to: toState, date: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.sessionFailed() }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var heartRate: Double?
        var distance: Double?
        if collectedTypes.contains(HKQuantityType(.heartRate)) {
            heartRate = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
                .mostRecentQuantity()?.doubleValue(for: .beatsPerMinute)
        }
        if collectedTypes.contains(HKQuantityType(.distanceWalkingRunning)) {
            distance = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter())
        }
        guard heartRate != nil || distance != nil else { return }
        Task { @MainActor in self.updateStatistics(heartRate: heartRate, distance: distance) }
    }
}
