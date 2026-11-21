import Foundation
import Observation
import QuizCore

/// Drives a hands-free Listen-mode session (FEATURES §2.2–2.3): plays each question's
/// `ListenScript` steps, and handles pause/resume, skip, repeat, interruptions and remote commands.
///
/// Pausing cancels the running task; resuming re-runs the current step (re-reading the
/// question or continuing the countdown where it left off).
@MainActor
@Observable
final class ListenSessionModel {
    enum Status: Equatable { case ready, playing, paused, finished }

    struct Dependencies {
        var speech: any SpeechOutput
        var cues: any CuePlaying
        var sleeper: any Sleeper = TaskSleeper()
        var audioSession: (any AudioSessionControlling)?
        var nowPlaying: (any NowPlayingUpdating)?
    }

    // MARK: Observable state for the UI

    private(set) var status: Status = .ready
    private(set) var turn: Turn?
    private(set) var revealedAnswer: String?
    private(set) var followUp: String?
    private(set) var thinkTotal: Double = 0
    private(set) var thinkRemaining: Double = 0
    private(set) var isThinking = false
    /// A Talk About prompt is waiting for the family to finish talking.
    private(set) var isDiscussing = false
    /// The current Talk About has a Parent mode timer (shown as a ring).
    private(set) var isDiscussionTimed = false
    /// "Got it" / "Not yet" for the current turn (ADR-0016). nil until the answer is heard.
    private(set) var result: ReviewResult?

    /// Whether the current turn can be marked: a quiz question whose answer has been read.
    var canMark: Bool { revealedAnswer != nil && turn?.presented.question.type.isScored == true }
    private(set) var closingMessage: String?
    /// Set if the audio session could not be configured; the quiz still runs on the speaker.
    private(set) var audioWarning: String?

    var questionCount: Int? { session.config.length.limit }

    /// Whether turns are addressed to named players.
    var isTurnBased: Bool { session.config.isTurnBased }

    // MARK: Internals

    @ObservationIgnored private var session: QuizSession
    private let bank: QuestionBank
    private let settings: ListenSettings
    private let duckOthers: Bool
    private let deps: Dependencies
    @ObservationIgnored private var steps: [SpeechStep] = []
    @ObservationIgnored private var stepIndex = 0
    @ObservationIgnored private var welcomeBackPending = false
    @ObservationIgnored private(set) var runner: Task<Void, Never>?
    /// Bumped on every (re)launch so a cancelled runner can't touch the new one's state.
    @ObservationIgnored private var generation = 0

    /// Called once when the session ends (finished or stopped) with each player's
    /// updated Leitner boxes, so they can be saved.
    @ObservationIgnored var onFinish: (([String: LearningRecord]) -> Void)?

    /// "#RRGGBB" per player id, for the "Mia's turn" label.
    let playerColors: [String: String]

    init(bank: QuestionBank, config: SessionConfig, settings: ListenSettings, duckOthers: Bool,
         dependencies: Dependencies, learning: [String: LearningRecord] = [:], day: Int = LearningDay.number(),
         playerColors: [String: String] = [:], rng: AnyRandomGenerator = .system()) {
        self.bank = bank
        self.session = QuizSession(bank: bank, config: config, learning: learning, day: day, rng: rng)
        self.playerColors = playerColors
        self.settings = settings
        self.duckOthers = duckOthers
        self.deps = dependencies
    }

    var topicTitle: String {
        let names = session.config.topics.compactMap { bank.topic(id: $0)?.name }
        return names.count == 1 ? names[0] : "Mixed topics"
    }

    // MARK: Controls

    func start() {
        guard status == .ready else { return }
        do {
            try deps.audioSession?.activateForListening(duckOthers: duckOthers)
        } catch {
            audioWarning = "Couldn't set up car audio. Playing through this device."
        }
        deps.audioSession?.onEvent = { [weak self] in self?.handle($0) }
        deps.nowPlaying?.onCommand = { [weak self] in self?.handle($0) }
        deps.nowPlaying?.enable()
        deps.cues.startSession()
        status = .playing
        launchRunner()
    }

    func pause() {
        guard status == .playing else { return }
        status = .paused
        haltRunner()
        updateNowPlaying()
    }

    func resume() {
        guard status == .paused else { return }
        status = .playing
        launchRunner()
    }

    func togglePause() { status == .playing ? pause() : resume() }

    /// Moves straight to the next question. During a Talk About chat it means
    /// "we're done talking": the app says "Great chat!" and carries on.
    func skip() {
        guard status == .playing || status == .paused else { return }
        if isDiscussing { return finishDiscussion() }
        haltRunner()
        session.record(.skipped)
        stepIndex = steps.count
        status = .playing
        launchRunner()
    }

    /// Ends a Talk About chat early (or with no timer) and continues with "Great chat!".
    func finishDiscussion() {
        guard isDiscussing, status == .playing || status == .paused else { return }
        haltRunner()
        thinkRemaining = 0
        isDiscussing = false
        stepIndex += 1
        status = .playing
        launchRunner()
    }

    /// "Got it" (`.correct`) or "Not yet" (`.incorrect`) for the player whose turn it is.
    /// A wrong answer sends the question back to box 1 for that player only.
    func mark(_ result: ReviewResult) {
        guard canMark else { return }
        session.mark(result)
        self.result = result
    }

    /// Re-reads the current question from the start.
    func repeatQuestion() {
        guard status == .playing || status == .paused, turn != nil else { return }
        haltRunner()
        restartCurrentQuestion()
        status = .playing
        launchRunner()
    }

    /// Ends the session immediately, without the spoken outro.
    func stop() {
        guard status != .finished else { return }
        haltRunner()
        session.stop()
        tearDown()
    }

    // MARK: Events

    func handle(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            pause()
        case .interruptionEnded(let shouldResume):
            guard status == .paused else { return }
            welcomeBackPending = true
            restartCurrentQuestion()
            if shouldResume { resume() }
        case .outputLost:
            pause()
        }
    }

    func handle(_ command: RemoteCommand) {
        switch command {
        case .play: resume()
        case .pause: pause()
        case .toggle: togglePause()
        case .next: skip()
        case .previous: repeatQuestion()
        }
    }

    // MARK: Runner

    private func launchRunner() {
        runner?.cancel()
        generation += 1
        let current = generation
        runner = Task { [weak self] in await self?.run(generation: current) }
    }

    private func haltRunner() {
        runner?.cancel()
        runner = nil
        deps.speech.stop()
        if isThinking { deps.cues.stopThinking() }
    }

    private func run(generation: Int) async {
        guard !Task.isCancelled, generation == self.generation else { return }
        updateNowPlaying()
        do {
            if welcomeBackPending {
                welcomeBackPending = false
                try await deps.speech.speak(Phrases.welcomeBack)
            }
            while !Task.isCancelled {
                if stepIndex >= steps.count {
                    guard loadNextTurn() else {
                        try await finishNaturally()
                        return
                    }
                }
                try await perform(steps[stepIndex], generation: generation)
                guard generation == self.generation else { return }
                stepIndex += 1
            }
        } catch {
            // Cancelled by pause/skip/repeat/stop: state is already set by the caller.
        }
    }

    private func loadNextTurn() -> Bool {
        guard let next = session.advance() else { return false }
        session.record(.notScored) // Listen mode keeps no score.
        turn = next
        result = nil
        isDiscussionTimed = false
        revealedAnswer = nil
        followUp = nil
        thinkRemaining = 0
        let category = bank.topic(id: next.presented.question.topic)?.category
        steps = ListenScript.steps(for: next, category: category, settings: settings,
                                   addressPlayer: session.config.isTurnBased)
        stepIndex = 0
        updateNowPlaying()
        return true
    }

    private func perform(_ step: SpeechStep, generation: Int) async throws {
        if case .discuss = step { isDiscussing = true } else { isDiscussing = false }
        switch step {
        case .say(let text, let purpose):
            if purpose == .answer {
                revealedAnswer = turn?.presented.answerText ?? text
                // Heard but not marked counts as right unless someone taps "Not yet".
                if result == nil, turn?.presented.question.type.isScored == true {
                    session.mark(.heard)
                    result = .heard
                }
            }
            if purpose == .followUp { followUp = text }
            try await deps.speech.speak(text)
        case .cue(.think):
            break // the tick runs during `.think`
        case .cue(.listening):
            deps.cues.play(.listening)
        case .think(let seconds):
            try await countdown(seconds: seconds, ticking: true, generation: generation)
        case .discuss(let seconds):
            isDiscussionTimed = seconds != nil
            if let seconds {
                // Parent mode timer: a quiet countdown (no ticking over the chat).
                try await countdown(seconds: seconds, ticking: false, generation: generation)
            } else {
                // No limit: only `finishDiscussion()` (or skip, stop, pause) moves on.
                while true { try await Task.sleep(for: .seconds(3600)) }
            }
        case .wait(let seconds):
            try await deps.sleeper.sleep(seconds: seconds)
        }
    }

    private func countdown(seconds: Double, ticking: Bool, generation: Int) async throws {
        if thinkRemaining <= 0 || thinkTotal != seconds {
            thinkTotal = seconds
            thinkRemaining = seconds
        }
        isThinking = ticking
        if ticking { deps.cues.startThinking() }
        defer {
            if generation == self.generation, ticking {
                isThinking = false
                deps.cues.stopThinking()
            }
        }
        let tick = 0.1
        while thinkRemaining > 0 {
            try await deps.sleeper.sleep(seconds: tick)
            guard generation == self.generation else { return }
            thinkRemaining = max(0, thinkRemaining - tick)
        }
    }

    private func restartCurrentQuestion() {
        isDiscussing = false
        stepIndex = steps.firstIndex { if case .say(_, .question) = $0 { true } else { false } } ?? 0
        thinkRemaining = 0
        revealedAnswer = nil
        followUp = nil
    }

    private func finishNaturally() async throws {
        // Listen mode keeps no score, so the outro just cheers the players by name.
        closingMessage = Phrases.listenOutro(players: session.config.players)
        turn = nil
        if let closingMessage { try await deps.speech.speak(closingMessage) }
        tearDown()
    }

    private func tearDown() {
        status = .finished
        isDiscussing = false
        onFinish?(session.learning)
        onFinish = nil
        turn = nil
        if closingMessage == nil { closingMessage = Phrases.outroPrefix }
        deps.cues.endSession()
        deps.nowPlaying?.disable()
        deps.audioSession?.deactivate()
        deps.audioSession?.onEvent = nil
    }

    private func updateNowPlaying() {
        let title = turn.map { "Question \($0.number)" } ?? "BuckleUp Quiz"
        deps.nowPlaying?.update(title: title, subtitle: topicTitle, isPlaying: status == .playing)
    }
}

extension ListenSessionModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
