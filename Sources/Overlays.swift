import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - Copied Toast

struct CopiedToast: View {
    @EnvironmentObject private var lang: L10n
    @ObservedObject private var pasteQueue = PasteQueue.shared
    let copiedId: UUID?

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                    Text(pasteQueue.isActive ? lang.tr("pasting") : lang.tr("pasted"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.green).shadow(color: .black.opacity(0.25), radius: 8, y: 4))
                Spacer()
            }.padding(.bottom, 40)
        }
        .allowsHitTesting(false).transition(.opacity).animation(.easeOut(duration: 0.2), value: copiedId)
    }
}

// MARK: - Download Overlay

struct DownloadOverlay: View {
    @EnvironmentObject private var lang: L10n
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(lang.tr("downloading"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("v\(updater.latestVersion)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 20, y: 8))
        }
    }
}

// MARK: - Quit Confirm

struct QuitConfirm: View {
    @EnvironmentObject private var lang: L10n
    @Binding var show: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).onTapGesture { show = false }
            VStack(spacing: 14) {
                Image(systemName: "power").font(.system(size: 24)).foregroundColor(.secondary)
                Text(lang.tr("quit_title")).font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 12) {
                    Button(action: { show = false }) {
                        Text(lang.tr("cancel")).font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(width: 80).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                    }.buttonStyle(.plain)
                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Text(lang.tr("quit_btn")).font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 80).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red)).foregroundColor(.white)
                    }.buttonStyle(.plain)
                }
            }.padding(24)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 20, y: 8))
        }.transition(.opacity)
    }
}

// MARK: - Settings Overlay

struct SettingsOverlay: View {
    @EnvironmentObject private var lang: L10n
    @ObservedObject var updater: UpdateChecker
    @Binding var show: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).onTapGesture { show = false }
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "gearshape").font(.system(size: 12))
                    Text(lang.tr("settings")).font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Button(action: { show = false }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        SettingsRow(title: lang.tr("launch_login"), subtitle: lang.tr("launch_login_sub")) {
                            Toggle("", isOn: Binding(
                                get: { SMAppService.mainApp.status == .enabled },
                                set: { val in try? val ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                            )).toggleStyle(.switch).controlSize(.small)
                        }

                        Divider().padding(.horizontal, 16)

                        SettingsRow(title: lang.tr("autopaste"), subtitle: checkAccessibility() ? lang.tr("enabled") : lang.tr("needed"),
                                    color: checkAccessibility() ? .green : .orange) {
                            HStack(spacing: 6) {
                                if checkAccessibility() {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green).font(.system(size: 14))
                                }
                                Button(lang.tr("enable")) { requestAccessibility() }
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                                .foregroundColor(.white)
                                .buttonStyle(.plain)
                            }
                        }

                        Divider().padding(.horizontal, 16)

                        SettingsRow(title: lang.tr("updates"),
                                    subtitle: updater.isChecking ? lang.tr("checking") :
                                    (updater.hasUpdate ? String(format: lang.tr("available"), updater.latestVersion) : lang.tr("up_to_date")),
                                    color: updater.isChecking ? .secondary : (updater.hasUpdate ? .orange : .green)) {
                            if updater.isChecking {
                                ProgressView().controlSize(.mini)
                            } else if updater.hasUpdate {
                                Button(lang.tr("update_btn")) { updater.downloadAndUpdate() }
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                                .foregroundColor(.white)
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { updater.checkForUpdates() }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(0.08)))
                                .foregroundColor(.secondary)
                            }
                        }

                        SettingsRow(title: lang.tr("language"), subtitle: "") {
                            Picker("", selection: Binding(
                                get: { lang.language },
                                set: { lang.set($0) }
                            )) {
                                ForEach(AppLanguage.allCases, id: \.self) { l in
                                    Text(l.label).tag(l)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        Divider().padding(.horizontal, 16)

                        SettingsRow(title: lang.tr("version"), subtitle: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6") {
                            EmptyView()
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(width: 340, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 20, y: 8))
        }.transition(.opacity)
    }
}

// MARK: - Update Error Toast

struct UpdateErrorToast: View {
    @EnvironmentObject private var lang: L10n
    let error: String
    @ObservedObject var updater: UpdateChecker
    @State private var visible = true

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(errorText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.red).shadow(color: .black.opacity(0.25), radius: 8, y: 4))
                Spacer()
            }.padding(.bottom, 40)
        }
        .allowsHitTesting(true)
        .onTapGesture { updater.updateError = nil }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                updater.updateError = nil
            }
        }
    }

    private var errorText: String {
        switch error {
        case "network_error": return lang.tr("err_network")
        case "download_failed": return lang.tr("err_download")
        case "corrupt_download": return lang.tr("err_corrupt")
        case "unzip_failed": return lang.tr("err_unzip")
        case "invalid_bundle": return lang.tr("err_bundle")
        case "version_not_newer": return lang.tr("err_version")
        case "update_failed": return lang.tr("err_update")
        default: return lang.tr("err_update")
        }
    }
}

// MARK: - Settings Row

struct SettingsRow<V: View>: View {
    let title: String
    let subtitle: String
    var color: Color = .secondary
    @ViewBuilder let value: () -> V

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium, design: .rounded))
                Text(subtitle).font(.system(size: 10, design: .rounded))
                    .foregroundColor(color)
            }
            Spacer()
            value()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
