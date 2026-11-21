import AVFoundation
import QuizCore
import SwiftUI

/// FEATURES §2.5. A parental gate will guard this screen in M6 (FEATURES §5).
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
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
                    Stepper(value: $store.settings.listen.thinkTime, in: ListenSettings.thinkTimeRange, step: 1) {
                        Text("Think time: \(Int(store.settings.listen.thinkTime)) seconds")
                    }
                    Toggle("Fun facts", isOn: $store.settings.listen.funFacts)
                    Toggle("Parent mode (Talk About prompts)", isOn: $store.settings.includeTalkAbout)
                } header: {
                    Text("Questions")
                } footer: {
                    Text("Talk About prompts are open chats with no right answer. Turn them off when kids play alone.")
                }

                Section {
                    Toggle("Lower music instead of stopping it", isOn: $store.settings.duckOthers)
                } header: {
                    Text("Audio")
                } footer: {
                    Text("BuckleUp Quiz plays through your car's Bluetooth or CarPlay audio, and keeps going with the screen locked.")
                }

                Section("Privacy") {
                    Text("BuckleUp Quiz collects no data. There are no ads, no tracking and no accounts.")
                        .font(.footnote)
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
}
