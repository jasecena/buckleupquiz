import AVFoundation
import QuizCore
import SwiftUI

/// FEATURES §2.5. A parental gate will guard this screen in M6 (FEATURES §5).
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(Telemetry.self) private var telemetry
    @Environment(\.dismiss) private var dismiss
    private let voices = SystemSpeechOutput.availableVoices()

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Voice") {
                    Picker("Voice", selection: $store.settings.voiceIdentifier) {
                        Text("Automatic (Australian)").tag(String?.none)
                        ForEach(voices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(Optional(voice.identifier))
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        Slider(value: $store.settings.speechRate, in: 0.25...0.65) {
                            Text("Speaking speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill")
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill")
                        }
                    }
                }

                Section {
                    Picker("Answers", selection: $store.settings.answerMode) {
                        Text("Say them out loud").tag(AnswerMode.voice)
                        Text("Just listen").tag(AnswerMode.listen)
                    }
                    if store.settings.answerMode == .voice {
                        Picker("Microphone", selection: $store.settings.micPreference) {
                            Text("Car or headset if connected").tag(MicPreference.automatic)
                            Text("This iPhone").tag(MicPreference.iPhone)
                        }
                        NavigationLink("Mic check") { MicCheckView() }
                    }
                } header: {
                    Text("Answers")
                } footer: {
                    Text(store.settings.answerMode == .voice
                         ? "After each question there's a beep. Whoever's turn it is says the answer, and the app keeps score. Say \"skip\", \"repeat\", \"pause\" or \"stop\" any time. Speech is understood on this iPhone and never recorded or sent anywhere. If nobody is heard, the app reads the answers out instead."
                         : "The app reads each answer after the think time. No score is kept.")
                }

                Section {
                    Stepper(value: $store.settings.listen.thinkTime, in: ListenSettings.thinkTimeRange, step: 1) {
                        Text("Think time: \(Int(store.settings.listen.thinkTime)) seconds")
                    }
                    Toggle("Fun facts", isOn: $store.settings.listen.funFacts)
                } header: {
                    Text("Questions")
                } footer: {
                    Text("Questions someone gets wrong come back for them later, until they're learned: today, tomorrow, then after 2, 4, 8 and 16 days.")
                }

                Section {
                    Toggle("Talk About prompts", isOn: $store.settings.includeTalkAbout)
                    Picker("Time to talk", selection: $store.settings.listen.talkTime) {
                        ForEach(ListenSettings.talkTimePresets, id: \.self) { preset in
                            Text(Self.talkTimeLabel(preset)).tag(preset)
                        }
                    }
                    .disabled(!store.settings.includeTalkAbout)
                } header: {
                    Text("Parent mode")
                } footer: {
                    Text("Talk About prompts are open questions to chat about together, with no right answer and no score. They have their own timer, separate from think time. With no limit, the quiz waits until you tap \"We're done\" or press next on the car or headphones. Off by default; turn it on when a grown-up is joining in.")
                }

                Section {
                    Toggle("Lower music instead of stopping it", isOn: $store.settings.duckOthers)
                } header: {
                    Text("Audio")
                } footer: {
                    Text("BuckleUp Quiz plays through your car's Bluetooth or CarPlay audio, and keeps going with the screen locked.")
                }

                Section {
                    Toggle("Send anonymous error reports", isOn: $store.settings.shareDiagnostics)
                        .onChange(of: store.settings.shareDiagnostics) { _, on in if !on { telemetry.clear() } }
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("No ads, no tracking and no accounts. Error reports help us fix problems like a microphone that won't start. They hold the app version, iPhone model and what went wrong. Never names, ages, answers, recordings or anything that identifies you.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    static func talkTimeLabel(_ seconds: Double?) -> String {
        guard let seconds else { return "No limit" }
        return seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) min"
    }
}
