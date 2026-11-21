import Foundation
import Observation
import QuizCore

/// How players answer (Settings → Answers, ADR-0018).
enum AnswerMode: String, Codable, CaseIterable, Sendable {
    /// The app reads the answer after the think time. No score.
    case listen
    /// Players say their answer; the app judges it and keeps score. Fully hands-free.
    case voice
}

/// What a finished session hands back for saving.
struct SessionSummary {
    /// Leitner boxes for the whole family (ADR-0016).
    var learning: [String: LearningRecord]
    /// This session's scores per player id (voice answers only).
    var stats: [String: PlayerStats]
}

/// A badge someone earned this session.
struct EarnedBadge: Identifiable, Hashable {
    let player: Player
    let badge: Badge
    var id: String { player.id + badge.id }
}

/// Drives a hands-free quiz session (FEATURES §2.2–2.3, §3.2–3.5): plays each question's
/// `ListenScript` steps, and handles pause/resume, skip, repeat, interruptions and remote commands.
///
/// With voice answers (ADR-0018) it listens after each question, judges the reply with
/// `VoiceReply`, says how it went and keeps score for whoever's turn it is. If nobody is
/// heard for three questions in a row, it falls back to reading the answers out.
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
        /// nil when voice answers can't be used (no permission, or no on-device recognition).
        var listener: (any SpeechListening)?
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
    /// Voice answers are on for this session (they switch off if nobody is heard).
    private(set) var isVoice = false
    /// The microphone is open.
    private(set) var isListening = false
    /// What the recogniser heard on this turn.
    private(set) var heard: String?
    /// How this turn's spoken answer went.
    private(set) var outcome: AnswerOutcome?
    /// Live scoreboard (voice answers).
    private(set) var scoreboard: [ScoreboardEntry] = []
    private(set) var earnedBadges: [EarnedBadge] = []
    /// "Using: <car>" — the microphone in use.
    private(set) var micName: String?
    private(set) var closingMessage: String?
    /// Set if the audio session could not be configured; the quiz still runs on the speaker.
    private(set) var audioWarning: String?

    /// Whether the current turn can be marked by tap (Listen mode only; voice is graded by ear).
    var canMark: Bool { !isVoice && revealedAnswer != nil && turn?.presented.question.type.isScored == true }

    /// Scores are shown once anyone has answered out loud.
    var showsScores: Bool { scoreboard.contains { $0.points > 0 } || hasAttempts }

    var questionCount: Int? { session.config.length.limit }

    /// Whether turns are addressed to named players.
    var isTurnBased: Bool { session.config.isTurnBased }

    // MARK: Internals

    @ObservationIgnored private var session: QuizSession
    private let bank: QuestionBank
    private let settings: ListenSettings
    private let duckOthers: Bool
    private let answerMode: AnswerMode
    private let mic: MicPreference
    private let lifetimeStats: [String: PlayerStats]
    private let deps: Dependencies
    @ObservationIgnored private var steps: [SpeechStep] = []
    @ObservationIgnored private var stepIndex = 0
    @ObservationIgnored private var category: Topic.Category?
    @ObservationIgnored private var welcomeBackPending = false
    @ObservationIgnored private var voiceTipPending = false
    @ObservationIgnored private var hasAttempts = false
    /// Players who've already heard "this one's for you" this game.
    @ObservationIgnored private var introducedPlayers: Set<String> = []
    @ObservationIgnored private var feedbackRNG = SystemRandomNumberGenerator()
    @ObservationIgnored private(set) var runner: Task<Void, Never>?
    @ObservationIgnored private var discussionTimer: Task<Void, Never>?
    /// Bumped on every (re)launch so a cancelled runner can't touch the new one's state.
    @ObservationIgnored private var generation = 0

    /// Called once when the session ends (finished or stopped), so boxes and scores can be saved.
    @ObservationIgnored var onFinish: ((SessionSummary) -> Void)?

    /// "#RRGGBB" per player id, for the "Mia's turn" label.
    let playerColors: [String: String]

    init(bank: QuestionBank, config: SessionConfig, settings: ListenSettings, duckOthers: Bool,
         dependencies: Dependencies, answerMode: AnswerMode = .listen, mic: MicPreference = .automatic,
         learning: [String: LearningRecord] = [:], lifetimeStats: [String: PlayerStats] = [:],
         day: Int = LearningDay.number(), playerColors: [String: String] = [:], rng: AnyRandomGenerator = .system()) {
        self.bank = bank
        self.session = QuizSession(bank: bank, config: config, learning: learning, day: day, rng: rng)
        self.playerColors = playerColors
        self.settings = settings
        self.duckOthers = duckOthers
        self.answerMode = answerMode
        self.mic = mic
        self.lifetimeStats = lifetimeStats
        self.deps = dependencies
    }

    var topicTitle: String {
        let names = session.config.topics.compactMap { bank.topic(id: $0)?.name }
        return names.count == 1 ? names[0] : "Mixed topics"
    }

    // MARK: Controls

    func start() {
        guard status == .ready else { return }
        if answerMode == .voice, deps.listener != nil {
            do {
                micName = try deps.audioSession?.activateForVoice(duckOthers: duckOthers, mic: mic)
                isVoice = true
                voiceTipPending = true
            } catch {
                audioWarning = "Couldn't turn on the microphone, so answers will be read out."
                activateForListening()
            }
        } else {
            if answerMode == .voice {
                audioWarning = "Voice answers need microphone and speech permission, so answers will be read out."
            }
            activateForListening()
        }
        deps.audioSession?.onEvent = { [weak self] in self?.handle($0) }
        deps.nowPlaying?.onCommand = { [weak self] in self?.handle($0) }
        deps.nowPlaying?.enable()
        deps.cues.startSession()
        status = .playing
        launchRunner()
    }

    private func activateForListening() {
        do {
            try deps.audioSession?.activateForListening(duckOthers: duckOthers)
        } catch {
            audioWarning = "Couldn't set up car audio. Playing through this device."
        }
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
        discussionTimer?.cancel()
        discussionTimer = nil
        isListening = false
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
            if voiceTipPending {
                voiceTipPending = false
                try await deps.speech.speak(Phrases.voiceTip)
            }
            while !Task.isCancelled {
                if stepIndex >= steps.count {
                    guard loadNextTurn() else {
                        try await finishNaturally()
                        return
                    }
                }
                try await perform(steps[stepIndex], generation: generation)
                guard generation == self.generation, status != .finished else { return }
                stepIndex += 1
            }
        } catch {
            // Cancelled by pause/skip/repeat/stop: state is already set by the caller.
        }
    }

    private func loadNextTurn() -> Bool {
        guard let next = session.advance() else { return false }
        // Listen mode keeps no score; voice turns are recorded once the answer is heard.
        if !isVoice { session.record(.notScored) }
        turn = next
        result = nil
        heard = nil
        outcome = nil
        isDiscussionTimed = false
        revealedAnswer = nil
        followUp = nil
        thinkRemaining = 0
        category = bank.topic(id: next.presented.question.topic)?.category
        let firstTurn = introducedPlayers.insert(next.player.id).inserted
        steps = ListenScript.steps(for: next, category: category, settings: settings,
                                   addressPlayer: session.config.isTurnBased, firstTurnForPlayer: firstTurn,
                                   voiceAnswers: isVoice)
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
                markHeardIfUnmarked()
            }
            if purpose == .followUp { followUp = text }
            try await deps.speech.speak(text)
        case .cue(.think):
            break // the tick runs during `.think`
        case .cue(.listening):
            deps.cues.play(.listening)
        case .think(let seconds):
            try await countdown(seconds: seconds, ticking: true, generation: generation)
        case .listen(let seconds):
            try await listenForAnswer(seconds: seconds, generation: generation)
        case .feedback:
            try await giveFeedback()
        case .discuss(let seconds):
            try await discuss(seconds: seconds, generation: generation)
        case .wait(let seconds):
            try await deps.sleeper.sleep(seconds: seconds)
        }
    }

    /// Heard but not marked counts as right unless someone taps "Not yet" (ADR-0016).
    private func markHeardIfUnmarked() {
        if result == nil, turn?.presented.question.type.isScored == true {
            session.mark(.heard)
            result = .heard
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

    // MARK: Voice answers (ADR-0018)

    /// Half-duplex: speech has finished → short gap → chime → listen, once. If nothing clear is
    /// heard, nothing is said about it: the answer is shared and the game moves on (ADR-0018).
    private func listenForAnswer(seconds: Double, generation: Int) async throws {
        guard isVoice, let listener = deps.listener, let turn else {
            // Voice is off (or the recogniser broke): behave like Listen mode.
            try await countdown(seconds: seconds, ticking: true, generation: generation)
            return
        }
        // Gaps either side of the chime, so the mic doesn't catch the end of the question or
        // the chime itself (Bluetooth speakers lag behind the phone).
        try await deps.sleeper.sleep(seconds: 0.5)
        deps.cues.play(.listening)
        try await deps.sleeper.sleep(seconds: 0.5)
        isListening = true
        let presented = turn.presented
        let started = Date.now
        let transcriptions: [String]
        do {
            transcriptions = try await listener.listen(
                for: seconds, hints: VoiceReply.hints(for: presented),
                isConclusive: { VoiceReply.interpret($0, for: presented).isConclusive })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The mic or recogniser can't be used: quietly carry on reading answers out, but
            // still give the full think time. The reason shows in Settings → Mic check.
            isListening = false
            isVoice = false
            let remaining = seconds - Date.now.timeIntervalSince(started)
            if remaining >= 1 {
                try await countdown(seconds: remaining.rounded(), ticking: true, generation: generation)
            }
            return
        }
        isListening = false
        guard generation == self.generation else { return }

        switch VoiceReply.interpret(transcriptions, for: turn.presented) {
        case .command(let command):
            try await obey(command)
        case .answer(let answerOutcome, let text):
            heard = text
            record(answerOutcome)
        case .garbled, .silence:
            record(.unheard)
        }
    }

    private func record(_ answerOutcome: AnswerOutcome) {
        session.record(answerOutcome)
        outcome = answerOutcome
        if answerOutcome != .unheard { hasAttempts = true }
        scoreboard = session.scoreboard
    }

    /// "Correct! Awesome! That's three in a row!", or just "The answer is… Hobart!"
    private func giveFeedback() async throws {
        guard let turn else { return }
        let presented = turn.presented
        revealedAnswer = presented.answerText
        guard let outcome else {
            // No spoken result (voice fell back mid-turn): read the answer like Listen mode.
            markHeardIfUnmarked()
            try await deps.speech.speak(Phrases.answerReveal(presented, category: category))
            return
        }
        var line = Phrases.feedback(outcome, presented: presented, category: category, using: &feedbackRNG)
        if outcome == .correct, let streak = Phrases.streak(session.scores.stats(for: turn.player.id).currentStreak) {
            line += " " + streak
        }
        try await deps.speech.speak(line)
    }

    /// Spoken game controls (FEATURES §3.3).
    private func obey(_ command: VoiceCommand) async throws {
        switch command {
        case .skip: skip()
        case .repeat: repeatQuestion()
        case .pause:
            try await deps.speech.speak(Phrases.pausedByVoice)
            pause()
        case .stop:
            haltSpeechOnly()
            session.stop()
            try await finishNaturally()
        }
    }

    private func haltSpeechOnly() {
        isListening = false
        if isThinking { deps.cues.stopThinking() }
    }

    /// Talk About: wait for "we're done" (voice), We're done / Next (tap or car button),
    /// or the Parent mode timer, which runs alongside as its own task.
    private func discuss(seconds: Double?, generation: Int) async throws {
        isDiscussionTimed = seconds != nil
        if let seconds {
            discussionTimer?.cancel()
            discussionTimer = Task { [weak self] in
                guard let self else { return }
                // A quiet countdown: no ticking over the chat.
                do { try await self.countdown(seconds: seconds, ticking: false, generation: generation) } catch { return }
                guard generation == self.generation, self.isDiscussing else { return }
                self.finishDiscussion()
            }
        }
        if isVoice, deps.listener != nil { try await listenForDiscussionCommands() }
        while true { try await Task.sleep(for: .seconds(3600)) }
    }

    private func listenForDiscussionCommands() async throws {
        guard let listener = deps.listener else { return }
        let hints = ["we're done", "all done", "finished", "next", "stop", "repeat"]
        while true {
            isListening = true
            let transcriptions: [String]
            do {
                transcriptions = try await listener.listen(
                    for: 30, hints: hints, isConclusive: { VoiceCommand.parse($0) != nil })
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                isListening = false
                return try await Task.sleep(for: .seconds(3600 * 24))
            }
            isListening = false
            guard let command = VoiceCommand.parse(transcriptions) else { continue }
            switch command {
            case .skip: finishDiscussion()
            case .repeat: repeatQuestion()
            case .pause, .stop: try await obey(command)
            }
            return
        }
    }

    // MARK: Ending

    private func restartCurrentQuestion() {
        isDiscussing = false
        stepIndex = steps.firstIndex { if case .say(_, .question) = $0 { true } else { false } } ?? 0
        thinkRemaining = 0
        revealedAnswer = nil
        followUp = nil
    }

    private func finishNaturally() async throws {
        turn = nil
        if hasAttempts {
            // "Mia wins with 80 points! Leo got 60 points! Mia earned the High Five badge!"
            scoreboard = session.scoreboard
            earnedBadges = newlyEarnedBadges()
            closingMessage = ([Phrases.scoreAnnouncement(scoreboard)]
                + earnedBadges.map { Phrases.badgeEarned($0.badge, by: $0.player) }).joined(separator: " ")
        } else {
            closingMessage = Phrases.listenOutro(players: session.config.players)
        }
        if let closingMessage { try await deps.speech.speak(closingMessage) }
        tearDown()
    }

    private func newlyEarnedBadges() -> [EarnedBadge] {
        session.config.players.flatMap { player -> [EarnedBadge] in
            let before = lifetimeStats[player.id] ?? PlayerStats()
            let after = before.adding(session.scores.stats(for: player.id))
            let had = Set(BadgeRules.earned(by: before, topics: bank.topics).map(\.id))
            return BadgeRules.earned(by: after, topics: bank.topics)
                .filter { !had.contains($0.id) }
                .map { EarnedBadge(player: player, badge: $0) }
        }
    }

    private func tearDown() {
        guard status != .finished else { return }
        status = .finished
        discussionTimer?.cancel()
        discussionTimer = nil
        isDiscussing = false
        isListening = false
        if hasAttempts { scoreboard = session.scoreboard }
        onFinish?(SessionSummary(learning: session.learning, stats: session.scores.stats))
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
