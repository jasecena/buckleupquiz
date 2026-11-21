import SwiftUI
import UIKit

/// Try the microphone before a trip (ADR-0018): shows which mic is used and what it heard.
/// Known problems show a short fix ("Settings › General › Keyboard › Enable Dictation"),
/// anything else shows the error itself.
struct MicCheckView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var state: CheckState = .idle
    @State private var micName: String?
    @State private var audio = AudioSessionController()

    private enum CheckState: Equatable {
        case idle, asking, listening, heard(String), nothing
        case failed(message: String, guide: FixGuide?)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: icon)
                    .font(.system(size: 96))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state == .listening)
                if let micName { Label("Using: \(micName)", systemImage: "mic.fill").font(Theme.body) }

                if case .failed(let message, let guide) = state {
                    failure(message: message, guide: guide)
                } else {
                    Text(message)
                        .font(Theme.title)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await check() }
                } label: {
                    Label(state == .listening ? "Listening…" : "Test the microphone", systemImage: "mic.fill")
                }
                .buttonStyle(BigButtonStyle())
                .disabled(state == .listening || state == .asking)
                Text("Say something like \"B\" or \"Hobart\". In the car, the car's microphone is used when the phone is connected by Bluetooth. Some cars show a phone-call screen while it's on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Mic check")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { audio.deactivate() }
    }

    private var icon: String {
        switch state {
        case .listening: "waveform.circle.fill"
        case .failed: "mic.slash.circle.fill"
        default: "mic.circle.fill"
        }
    }

    private var message: String {
        switch state {
        case .idle: "Tap the button, then say something."
        case .asking: "Asking for permission…"
        case .listening: "Listening… say something!"
        case .heard(let text): "Heard: \"\(text)\""
        case .nothing: "I didn't hear anything. Try speaking louder or closer."
        case .failed(let message, _): message
        }
    }

    /// A known problem: its name, the raw error small, then the fix as a path.
    @ViewBuilder private func failure(message: String, guide: FixGuide?) -> some View {
        if let guide {
            VStack(spacing: 16) {
                Text(guide.problem)
                    .font(Theme.title)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 10) {
                    Label("To fix", systemImage: "wrench.and.screwdriver.fill")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.accent)
                    Text(guide.path)
                        .font(Theme.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if guide.opensSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open Settings") { openURL(url) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.accent.opacity(0.12)))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            Text(message)
                .font(Theme.title)
                .multilineTextAlignment(.center)
        }
    }

    private func check() async {
        if !SystemSpeechListener.hasPermission {
            state = .asking
            guard await SystemSpeechListener.requestPermission() else {
                state = .failed(message: "Microphone or speech recognition permission is off.", guide: .permissionOff)
                return
            }
        }
        guard let listener = SystemSpeechListener() else {
            state = .failed(message: SystemSpeechListener.lastProblem ?? "On-device speech recognition isn't available.",
                            guide: .noOnDeviceSpeech)
            return
        }
        do {
            micName = try audio.activateForVoice(duckOthers: store.settings.duckOthers, mic: store.settings.micPreference)
            state = .listening
            let heard = try await listener.listen(for: 5, hints: ["A", "B", "C", "true", "false"],
                                                  isConclusive: { !$0.isEmpty })
            state = heard.first.map(CheckState.heard) ?? .nothing
        } catch {
            state = .failed(message: error.localizedDescription, guide: FixGuide.guide(for: error))
        }
        audio.deactivate()
    }
}
