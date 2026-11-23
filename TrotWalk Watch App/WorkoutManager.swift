import CoreLocation
import CoreMotion
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
/// 記録は屋外ウォーキングとして Fitness と Health に保存される（GPS のルートつき）。
/// 終わりの時間は決めず、終えるまで速歩と緩歩をくり返す。
@MainActor
@Observable
final class WorkoutManager: NSObject {
    enum State: Equatable {
        case idle
        case preparing
        /// 開始前のカウントダウン（3, 2, 1）
        case countdown(Int)
        case running
        case paused
        case ending
        case finished
    }

    private(set) var state: State = .idle
    private(set) var settings = WalkSettings()
    private(set) var plan = IntervalPlan.standard
    private(set) var elapsed: TimeInterval = 0
    private(set) var heartRate: Double?
    private(set) var distanceMeters: Double?
    private(set) var zones: HeartRateZones?
    /// 今の歩調テンポ（歩/分）。テンポがオフなら nil。
    private(set) var cadence: Double?
    /// 立ち止まったことで自動的に一時停止しているか
    private(set) var isAutoPaused = false
    private(set) var summary: WorkoutSummary?
    private(set) var errorMessage: String?

    var position: IntervalPosition? { plan.position(at: elapsed) }

    let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var schedule: CueSchedule?
    @ObservationIgnored private var coach: IntensityCoach?
    @ObservationIgnored private var tempo: TempoCoach?
    /// 終了後に回答を反映するまで、最後の速歩テンポを持っておく
    @ObservationIgnored private var finalBriskCadence: Double?
    @ObservationIgnored private var countdownSkipped = false
    @ObservationIgnored private var countdownCancelled = false
    /// 回答を受け付けたか（終了画面で一度だけ聞く）
    private(set) var feedbackRecorded = false
    @ObservationIgnored private var metronome: Task<Void, Never>?
    @ObservationIgnored private var lastTick: TimeInterval = 0
    @ObservationIgnored private var currentSegment: IntervalSegment?
    @ObservationIgnored private var currentSegmentStart: Date?
    private let pedometer = CMPedometer()
    private let locationManager = CLLocationManager()
    @ObservationIgnored private var routeBuilder: HKWorkoutRouteBuilder?
    private let haptics = HapticPlayer()

    // MARK: - 権限

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
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
        plan = settings.plan
        countdownSkipped = false
        countdownCancelled = false
        elapsed = 0
        lastTick = 0
        isAutoPaused = false
        heartRate = nil
        distanceMeters = nil
        summary = nil

        await requestAuthorization()

        let calibration = PersonalCalibration.load()
        zones = settings.intensityGuideEnabled
            ? await HealthProfile.zones(store: healthStore, briskReserve: calibration.briskReserve)
            : nil
        feedbackRecorded = false
        finalBriskCadence = nil
        if settings.tempoEnabled {
            // テンポがオンなら、心拍の目安があるときはテンポそのものを自動調整する
            tempo = TempoCoach(zones: zones, briskStart: calibration.briskStartCadence)
            coach = nil
        } else {
            tempo = nil
            coach = zones.map { IntensityCoach(zones: $0) }
        }
        cadence = tempo?.cadence(for: .brisk)
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

            // 標準のワークアウトアプリと同じく、カウントダウンの間にセンサーを準備する
            session.prepare()
            await runCountdown()
            if countdownCancelled {
                session.end()
                cleanUp()
                state = .idle
                return
            }

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            try await builder.addMetadata([
                HKMetadataKeyIndoorWorkout: false,
                MetadataKey.briskSeconds: settings.briskDuration,
                MetadataKey.easySeconds: settings.easyDuration,
            ])

            currentSegment = plan.segment(index: 0)
            currentSegmentStart = startDate
            state = .running
            haptics.play(.briskStart)
            startTicker()
            startMetronome()
            startRoute()
            if settings.autoPauseEnabled { startAutoPause() }
        } catch {
            errorMessage = "ワークアウトを開始できませんでした"
            session?.end()
            cleanUp()
            state = .idle
        }
    }

    /// カウントダウンを飛ばしてすぐ始める（画面をタップ）
    func skipCountdown() {
        countdownSkipped = true
    }

    /// カウントダウン中にやめる。記録は残さない。
    func cancelCountdown() {
        countdownCancelled = true
    }

    private func runCountdown() async {
        for count in stride(from: 3, through: 1, by: -1) {
            if countdownSkipped || countdownCancelled { return }
            state = .countdown(count)
            haptics.countdownTick()
            // 1秒待つ。途中でタップされたらすぐ抜ける
            for _ in 0..<20 {
                if countdownSkipped || countdownCancelled { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func togglePause() {
        // 手で操作したら、自動の一時停止・再開は次に立ち止まるまで任せない
        isAutoPaused = false
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

    /// 終えるときに呼ぶ。記録は保存される。
    func end() {
        guard state == .running || state == .paused else { return }
        state = .ending
        ticker?.cancel()
        metronome?.cancel()
        pedometer.stopEventUpdates()
        locationManager.stopUpdatingLocation()
        recordCurrentSegment(endingAt: Date())
        session?.end()
    }

    /// 終了画面での「速歩はどうでしたか？」の回答。次回の目安心拍とテンポに反映する。
    func recordFeedback(_ feedback: EffortFeedback?) {
        guard state == .finished, !feedbackRecorded else { return }
        feedbackRecorded = true
        PersonalCalibration.load()
            .updated(feedback: feedback, finalBriskCadence: finalBriskCadence)
            .save()
    }

    /// 終了画面を閉じてスタートに戻る。答えずに閉じた場合も、最後のテンポだけは覚えておく。
    func reset() {
        guard state == .finished else { return }
        recordFeedback(nil)
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

        if let cues = schedule?.cues(from: lastTick, to: now), !cues.isEmpty {
            haptics.play(cues)
        } else if let position, let heartRate,
                  let cue = coach?.evaluate(heartRate: heartRate, position: position, now: now) {
            haptics.play(cue)
        }

        if let position, tempo != nil {
            // テンポの変化は振動の間隔そのもので伝わるので、別の合図は鳴らさない
            tempo?.update(heartRate: heartRate, position: position, now: now)
            cadence = tempo?.cadence(for: position.segment.phase)
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
            if let workout = try await builder.finishWorkout(), let routeBuilder {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            errorMessage = "記録の保存に失敗しました"
        }
        summary = WorkoutSummary(
            totalTime: total,
            briskTime: plan.briskTime(upTo: total),
            distanceMeters: distanceMeters
        )
        finalBriskCadence = tempo?.briskCadence
        cleanUp()
        state = .finished
    }

    /// 歩調テンポの振動を刻む。1歩ごとに1拍で、4歩鳴らして4歩休む。
    /// 間隔は毎拍、今のフェーズとテンポから決め直す。区間が変わったら数え直す。
    private func startMetronome() {
        metronome?.cancel()
        guard tempo != nil else { return }
        metronome = Task { [weak self] in
            let clock = ContinuousClock()
            var next = clock.now
            var beat = 0
            var segmentIndex: Int?
            while !Task.isCancelled {
                guard let current = self?.currentBeat() else {
                    // 一時停止中や切り替え直前。再開したらその時点から刻み直す
                    try? await clock.sleep(for: .milliseconds(250))
                    next = clock.now
                    beat = 0
                    continue
                }
                if current.segmentIndex != segmentIndex {
                    segmentIndex = current.segmentIndex
                    beat = 0
                }
                next = max(next.advanced(by: .seconds(current.interval)), clock.now)
                try? await clock.sleep(until: next)
                if Task.isCancelled { return }
                if self?.currentBeat() != nil, TempoCoach.isPulseBeat(beat) {
                    self?.haptics.tempoTick()
                }
                beat += 1
            }
        }
    }

    /// 今の拍の間隔と区間番号。テンポを鳴らさない時間なら nil。
    private func currentBeat() -> (interval: TimeInterval, segmentIndex: Int)? {
        guard state == .running, let tempo, let position else { return nil }
        // 5秒前の小刻みな振動と混ざらないよう、切り替え直前はテンポを止める
        if settings.switchWarningEnabled, position.remainingInSegment <= CueSchedule.finalWarningLead + 0.5 {
            return nil
        }
        return (interval: tempo.pulseInterval(for: position.segment.phase), segmentIndex: position.segment.index)
    }

    // MARK: - 立ち止まったら自動で一時停止

    private func startAutoPause() {
        guard CMPedometer.isPedometerEventTrackingAvailable() else { return }
        pedometer.startEventUpdates { [weak self] event, _ in
            guard let type = event?.type else { return }
            Task { @MainActor in self?.handlePedometerEvent(type) }
        }
    }

    private func handlePedometerEvent(_ type: CMPedometerEventType) {
        switch type {
        case .pause where state == .running:
            isAutoPaused = true
            session?.pause()
            haptics.play(.paused)
        case .resume where state == .paused && isAutoPaused:
            isAutoPaused = false
            session?.resume()
            haptics.play(.resumed)
        default:
            break
        }
    }

    // MARK: - GPS ルート

    private func startRoute() {
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
    }

    fileprivate func addRoute(_ locations: [CLLocation]) {
        guard let routeBuilder, state == .running else { return }
        // 精度の低い点は捨てる
        let usable = locations.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 50 }
        guard !usable.isEmpty else { return }
        routeBuilder.insertRouteData(usable) { _, _ in }
    }

    private func cleanUp() {
        ticker?.cancel()
        ticker = nil
        metronome?.cancel()
        metronome = nil
        pedometer.stopEventUpdates()
        locationManager.stopUpdatingLocation()
        routeBuilder = nil
        isAutoPaused = false
        tempo = nil
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
}

// MARK: - CLLocationManagerDelegate

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.addRoute(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
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
