import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var engine: MonitorEngine
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LoginItem.setEnabled(enabled) }
                Button("Quit Mac Monitor") { NSApplication.shared.terminate(nil) }
            }

            Section {
                ForEach(Vital.Kind.allCases, id: \.self) { kind in
                    Toggle(kind.rawValue, isOn: shown(kind, in: \.hiddenVitals))
                }
            } header: {
                Text("Vitals")
            } footer: {
                Text("Hidden vitals don't affect the menu bar icon.")
            }

            Section {
                Toggle("Pop up with a sound for new alerts", isOn: $engine.preferences.popUpAlerts)
                Toggle("Restart stuck apps automatically", isOn: $engine.preferences.autoFixStuckApps)
                    .disabled(!engine.preferences.popUpAlerts)
            } header: {
                Text("Pop-ups")
            } footer: {
                Text("Only apps you're not using, after a 10-second countdown you can stop.")
            }

            Section("Alert me when…") {
                ForEach(Alert.Kind.allCases, id: \.self) { kind in
                    Toggle(kind.label, isOn: shown(kind, in: \.disabledAlerts))
                }
            }

            if !engine.preferences.ignoredApps.isEmpty {
                Section("Ignored apps") {
                    ForEach(engine.preferences.ignoredApps.sorted(), id: \.self) { app in
                        HStack {
                            Text(app)
                            Spacer()
                            Button("Stop Ignoring") { engine.unignoreApp(app) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A toggle that's on when `kind` is *not* in the given hidden/disabled set.
    private func shown<Kind: Hashable>(_ kind: Kind, in set: WritableKeyPath<Preferences, Set<Kind>>) -> Binding<Bool> {
        Binding(
            get: { !engine.preferences[keyPath: set].contains(kind) },
            set: { isOn in
                if isOn { engine.preferences[keyPath: set].remove(kind) }
                else { engine.preferences[keyPath: set].insert(kind) }
            }
        )
    }
}
