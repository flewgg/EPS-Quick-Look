import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var updaterController: AppUpdaterController
    @AppStorage(
        PreviewTemporaryStorage.temporaryCleanupIntervalDefaultsKey,
        store: UserDefaults(suiteName: PreviewTemporaryStorage.appGroupIdentifier)
    ) private var temporaryCleanupIntervalRawValue = TemporaryCleanupIntervalOption.defaultOption.rawValue

    private var selectedCleanupIntervalOption: TemporaryCleanupIntervalOption {
        TemporaryCleanupIntervalOption(rawValue: temporaryCleanupIntervalRawValue) ?? .defaultOption
    }

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updaterController.automaticallyChecksForUpdates },
            set: { updaterController.setAutomaticallyChecksForUpdates($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            heroSection

            Form {
                Section("General") {
                    Picker(selection: $temporaryCleanupIntervalRawValue) {
                        ForEach(TemporaryCleanupIntervalOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    } label: {
                        Text("Temporary File Cleanup")
                        Text("Preview and thumbnail temp files older than \(selectedCleanupIntervalOption.title.lowercased()) are removed automatically.")
                    }
                    .pickerStyle(.menu)
                }

                Section("About") {
                    LabeledContent("Release Notes") {
                        Link("flew.gg/eps-quick-look/changelog", destination: AppLink.changelog.url)
                    }

                    LabeledContent("Contact") {
                        Link("contact@flew.gg", destination: AppLink.contact.url)
                    }
                }
            }
            .formStyle(.grouped)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: 620, height: 500)
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 124, height: 124)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Bundle.main.appName)
                        .font(.title.weight(.semibold))

                    Text("Version \(Bundle.main.versionWithBuild)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Check for Updates...") {
                        updaterController.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!updaterController.canCheckForUpdates)

                    Button("Send Feedback") {
                        NSWorkspace.shared.open(AppLink.feedback.url)
                    }
                    .buttonStyle(.bordered)

                    Button("Join Discord") {
                        NSWorkspace.shared.open(AppLink.discord.url)
                    }
                    .buttonStyle(.bordered)
                }

                Toggle("Automatically check for updates", isOn: automaticUpdatesBinding)
                    .toggleStyle(.checkbox)

                HStack(spacing: 8) {
                    Text(Bundle.main.copyright)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("|")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)

                    Button {
                        openWindow(id: ManagedWindow.acknowledgements.id)
                    } label: {
                        Text("Acknowledgements")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }
                .tint(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.bottom, 12)
    }
}
