import SwiftUI

/// Try the microphone before a trip (ADR-0018): shows which mic is used and what it heard.
struct MicCheckView: View {
    @Environment(SettingsStore.self) private var store
    @State private var state: CheckState = .idle
    @State private var micName: String?
    @State private var audio = AudioSessionController()

    private enum CheckState: Equatable {
        case idle, asking, listening, heard(String), nothing, failed(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: state == .listening ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state == .listening)
            if let micName { Label("Using: \(micName)", systemImage: "mic.fill").font(Theme.body) }
            Text(message)
                .font(Theme.title)
                .multilineTextAlignment(.center)
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
        .navigationTitle("Mic check")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { audio.deactivate() }
    }

    private var message: String {
        switch state {
        case .idle: "Tap the button, then say something."
        case .asking: "Asking for permission…"
        case .listening: "Listening… say something!"
        case .heard(let text): "Heard: \"\(text)\""
        case .nothing: "I didn't hear anything. Try speaking louder or closer."
        case .failed(let reason): reason
        }
    }

    private func check() async {
        if !SystemSpeechListener.hasPermission {
            state = .asking
            guard await SystemSpeechListener.requestPermission() else {
                state = .failed("Microphone or speech permission is off. Turn it on in the Settings app → BuckleUp Quiz.")
                return
            }
        }
        guard let listener = SystemSpeechListener() else {
            state = .failed("On-device speech recognition isn't available on this iPhone, so answers will be read out.")
            return
        }
        do {
            micName = try audio.activateForVoice(duckOthers: store.settings.duckOthers, mic: store.settings.micPreference)
            state = .listening
            let heard = try await listener.listen(for: 5, hints: ["A", "B", "C", "true", "false"])
            state = heard.first.map(CheckState.heard) ?? .nothing
        } catch {
            state = .failed("Couldn't use the microphone. Is another app using it?")
        }
        audio.deactivate()
    }
}
