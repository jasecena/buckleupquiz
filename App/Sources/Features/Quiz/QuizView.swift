import QuizCore
import SwiftUI

/// The in-game screen: readable, but never required (FEATURES §2.2).
struct QuizView: View {
    let model: ListenSessionModel
    @Environment(\.dismiss) private var dismiss

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
                Image(systemName: model.showsScores ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                if model.showsScores {
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
        }
    }

    // MARK: Voice answers (ADR-0018)

    private func listening(for turn: Turn) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text(turn.player.name.isEmpty ? "Listening…" : "Listening to \(turn.player.name)…")
                .font(Theme.title)
            Text(turn.presented.question.type == .trueFalse ? "Say true or false" : "Say A, B or C, or the answer")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func outcomeLine(_ outcome: AnswerOutcome) -> some View {
        let (text, symbol, color): (String, String, Color) = switch outcome {
        case .correct: ("Correct!", "checkmark.circle.fill", .green)
        case .incorrect: ("Not quite", "xmark.circle.fill", .orange)
        default: ("Time's up", "clock.fill", .secondary)
        }
        VStack(spacing: 4) {
            Label(text, systemImage: symbol).font(Theme.title).foregroundStyle(color)
            if let heard = model.heard {
                Text("Heard: \"\(heard)\"").font(Theme.body).foregroundStyle(.secondary)
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
                HStack {
                    Text(entry.rank == 1 ? "🏆" : "\(entry.rank).").frame(width: 36)
                    Text(entry.player.name.isEmpty ? "You" : entry.player.name).font(Theme.title)
                    Spacer()
                    Text("\(entry.points)").font(Theme.title).monospacedDigit()
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
