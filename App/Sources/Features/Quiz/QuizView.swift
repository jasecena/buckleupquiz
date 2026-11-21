import QuizCore
import SwiftUI

/// The in-game screen: readable, but never required (FEATURES §2.2).
struct QuizView: View {
    let model: ListenSessionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settingsStore
    /// The first time the game goes to the background it keeps playing (so a car trip isn't
    /// interrupted), and the question is asked as soon as the app is back on screen.
    @State private var askAboutBackground = false
    @State private var wentToBackground = false
    /// Score correction after the game: whose score is being edited, and the new value.
    @State private var editingPlayer: String?
    @State private var draftPoints = 0

    var body: some View {
        VStack(spacing: 24) {
            header
            if model.showsScores, model.status != .finished { scoreStrip }
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            controls
        }
        .padding()
        .background(Theme.background.ignoresSafeArea())
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in handle(phase) }
        .alert("Keep playing in the background?", isPresented: $askAboutBackground) {
            Button("Yes, keep playing") { settingsStore.settings.backgroundPlay = true }
            Button("No, pause it") { settingsStore.settings.backgroundPlay = false }
        } message: {
            Text("BuckleUp Quiz can keep playing when you lock the screen or switch apps, which is handy in the car. You can change this later in Settings.")
        }
    }

    /// Background play (Settings → Audio): pause when it's off; ask once when it's never been set.
    private func handle(_ phase: ScenePhase) {
        guard model.status == .playing || model.status == .paused else { return }
        switch phase {
        case .background:
            wentToBackground = true
            if settingsStore.settings.backgroundPlay == false { model.pause() }
        case .active:
            if wentToBackground, settingsStore.settings.backgroundPlay == nil { askAboutBackground = true }
            wentToBackground = false
        default:
            break
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.topicTitle).font(Theme.headline)
                if let turn = model.turn {
                    Text(progressText(turn.number)).font(Theme.body).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.largeTitle)
            }
            .accessibilityLabel("End quiz")
        }
    }

    @ViewBuilder private var content: some View {
        if model.status == .finished {
            VStack(spacing: 20) {
                Image(systemName: model.showsFinalScores ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                if model.showsFinalScores {
                    finalScores
                } else {
                    Text(model.closingMessage ?? Phrases.outroPrefix)
                        .font(Theme.title)
                        .multilineTextAlignment(.center)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(BigButtonStyle())
            }
        } else if let turn = model.turn {
            VStack(spacing: 24) {
                if model.isTurnBased, !turn.player.name.isEmpty {
                    Text("\(turn.player.name)'s turn")
                        .font(Theme.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color(hex: model.playerColors[turn.player.id] ?? "#FF6919")))
                }
                if turn.kind != .new {
                    Label(turn.kind == .ownReview ? "From before" : "Someone else had this one",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(turn.presented.question.question)
                    .font(Theme.question)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if let options = turn.presented.options {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(zip(turn.presented.optionLetters, options)), id: \.0) { letter, option in
                            Text("\(letter): \(option)").font(Theme.headline)
                        }
                    }
                }
                if model.isListening, !model.isDiscussing {
                    listening(for: turn)
                } else if let answer = model.revealedAnswer {
                    VStack(spacing: 8) {
                        if let outcome = model.outcome { outcomeLine(outcome) }
                        Text(answer)
                            .font(Theme.hero)
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                        if let followUp = model.followUp {
                            Text(followUp).font(Theme.body).multilineTextAlignment(.center)
                        }
                        if model.canMark { markButtons(for: turn) }
                    }
                    .transition(.scale.combined(with: .opacity))
                } else if model.isDiscussing {
                    VStack(spacing: 16) {
                        Label("Talk it over", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(Theme.title)
                            .foregroundStyle(Theme.accent)
                        if model.isDiscussionTimed {
                            CountdownRing(remaining: model.thinkRemaining, total: model.thinkTotal)
                                .frame(width: 110, height: 110)
                        }
                        Text(model.isListening ? "No rush. Say \"we're done\" when you're ready to move on."
                             : model.isDiscussionTimed ? "Tap when you're ready, or wait for the timer."
                             : "No rush. Tap when you're ready to move on.")
                            .font(Theme.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button { model.finishDiscussion() } label: {
                            Label("We're done", systemImage: "checkmark")
                        }
                        .buttonStyle(BigButtonStyle())
                    }
                } else if model.isThinking || model.thinkRemaining > 0 {
                    CountdownRing(remaining: model.thinkRemaining, total: model.thinkTotal)
                        .frame(width: 140, height: 140)
                }
            }
            .animation(.spring, value: model.revealedAnswer)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "car.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
                Text("Buckle up…").font(Theme.title)
            }
        }
        if let warning = model.audioWarning {
            Text(warning).font(.footnote).foregroundStyle(.secondary)
        }
        if let mic = model.micName, model.isVoice, model.status != .finished {
            Label("Using: \(mic)", systemImage: "mic.fill").font(.footnote).foregroundStyle(.secondary)
        } else if model.isVoiceOff, model.status != .finished, model.audioWarning == nil {
            // For the grown-ups: listening isn't running, so answers are being read out.
            Label(model.voiceOffHint ?? "Not listening: answers are read out. See Settings → Mic check.",
                  systemImage: "mic.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Voice answers (ADR-0018)

    /// The microphone and the countdown side by side, so it's clear the app is still listening
    /// while the clock runs.
    private func listening(for turn: Turn) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 28) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                CountdownRing(remaining: model.thinkRemaining, total: model.thinkTotal)
                    .frame(width: 88, height: 88)
            }
            Text(turn.player.name.isEmpty ? "Listening…" : "Listening to \(turn.player.name)…")
                .font(Theme.title)
            Text(turn.presented.question.type == .trueFalse ? "Say true or false" : "Say A, B or C, or the answer")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Only a right answer gets a line. Anything else just shows the answer: no ✗, no
    /// "time's up", no "didn't hear you" (ADR-0018).
    @ViewBuilder private func outcomeLine(_ outcome: AnswerOutcome) -> some View {
        if outcome == .correct {
            VStack(spacing: 4) {
                Label("Correct!", systemImage: "star.fill").font(Theme.title).foregroundStyle(.green)
                if let heard = model.heard {
                    Text("Heard: \"\(heard)\"").font(Theme.body).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Live points per player, in turn order.
    private var scoreStrip: some View {
        HStack(spacing: 8) {
            ForEach(model.scoreboard, id: \.player.id) { entry in
                HStack(spacing: 6) {
                    Text(entry.player.name.isEmpty ? "Score" : entry.player.name).lineLimit(1)
                    Text("\(entry.points)").monospacedDigit().fontWeight(.heavy)
                }
                .font(Theme.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color(hex: model.playerColors[entry.player.id] ?? "#FF6919")))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.scoreboard.map { "\($0.player.name) \($0.points) points" }.joined(separator: ", "))
    }

    /// End-of-game scoreboard with any new badges.
    private var finalScores: some View {
        VStack(spacing: 12) {
            ForEach(model.scoreboard, id: \.player.id) { entry in
                HStack(spacing: 12) {
                    Text(entry.rank == 1 && entry.points > 0 ? "🏆" : "\(entry.rank).").frame(width: 36)
                    Text(entry.player.name.isEmpty ? "You" : entry.player.name).font(Theme.title)
                    Spacer()
                    if editingPlayer == entry.player.id {
                        scoreEditor(for: entry)
                    } else {
                        Text("\(entry.points)").font(Theme.title).monospacedDigit()
                        Button {
                            editingPlayer = entry.player.id
                            draftPoints = entry.points
                        } label: {
                            Image(systemName: "pencil.circle.fill").font(.title)
                        }
                        .accessibilityLabel("Edit \(entry.player.name)'s score")
                        .disabled(editingPlayer != nil)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: model.playerColors[entry.player.id] ?? "#FF6919").opacity(0.15)))
            }
            ForEach(model.earnedBadges) { earned in
                Label("\(earned.player.name): \(earned.badge.title)", systemImage: "rosette")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.accent)
            }
            Label("Missed an answer? Tap the pencil to fix a score.", systemImage: "pencil")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .animation(.spring, value: model.scoreboard.map(\.points))
    }

    /// − / + in steps of one answer (10 points), between 0 and the most this player could score.
    private func scoreEditor(for entry: ScoreboardEntry) -> some View {
        let maximum = model.maxPoints(for: entry.player.id)
        return HStack(spacing: 10) {
            Button { draftPoints = max(0, draftPoints - 10) } label: {
                Image(systemName: "minus.circle.fill").font(.title)
            }
            .disabled(draftPoints <= 0)
            .accessibilityLabel("Less")
            Text("\(draftPoints)").font(Theme.title).monospacedDigit().frame(minWidth: 48)
            Button { draftPoints = min(maximum, draftPoints + 10) } label: {
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .disabled(draftPoints >= maximum)
            .accessibilityLabel("More")
            Button("Save") {
                model.setPoints(draftPoints, for: entry.player.id)
                editingPlayer = nil
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// "Got it" / "Not yet" for the player whose turn it is (ADR-0016). Untapped counts as got it.
    private func markButtons(for turn: Turn) -> some View {
        let who = model.isTurnBased && !turn.player.name.isEmpty ? turn.player.name : "You"
        return HStack(spacing: 12) {
            Button { model.mark(.correct) } label: {
                Label("\(who) got it", systemImage: "checkmark")
            }
            .buttonStyle(BigButtonStyle(color: .green, prominent: model.result == .correct))
            .accessibilityAddTraits(model.result == .correct ? .isSelected : [])

            Button { model.mark(.incorrect) } label: {
                Label("Not yet", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(BigButtonStyle(color: .orange, prominent: model.result == .incorrect))
            .accessibilityAddTraits(model.result == .incorrect ? .isSelected : [])
            .accessibilityHint("Asks this question again later so it can be learned")
        }
        .font(Theme.body)
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { model.repeatQuestion() } label: {
                Label("Repeat", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(BigButtonStyle(prominent: false))

            Button { model.togglePause() } label: {
                Label(model.status == .paused ? "Resume" : "Pause",
                      systemImage: model.status == .paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(BigButtonStyle())

            Button { model.skip() } label: {
                Label("Skip", systemImage: "forward.fill")
            }
            .buttonStyle(BigButtonStyle(prominent: false))
        }
        .labelStyle(.iconOnly)
        .font(.title)
        .disabled(model.status == .finished || model.status == .ready)
        .opacity(model.status == .finished ? 0 : 1)
    }

    private func progressText(_ number: Int) -> String {
        if let total = model.questionCount { return "Question \(number) of \(total)" }
        return "Question \(number)"
    }
}
