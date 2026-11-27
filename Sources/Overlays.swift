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
                Label(
                    pasteQueue.isActive ? lang.tr("pasting") : lang.tr("pasted"),
                    systemImage: pasteQueue.isActive ? "arrow.triangle.2.circlepath" : "checkmark"
                )
                .font(ClipStyle.callout.weight(.semibold))
                .foregroundStyle(Color(white: 0.08))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(white: 0.94))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                )
                Spacer()
            }
            .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: copiedId)
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
                ProgressView().controlSize(.regular)
                Text(lang.tr("downloading"))
                    .font(ClipStyle.headline)
                Text("v\(updater.latestVersion)")
                    .font(ClipStyle.caption)
                    .foregroundStyle(ClipStyle.tertiary)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous)
                    .strokeBorder(ClipStyle.border, lineWidth: 0.5)
            )
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
            VStack(spacing: 16) {
                Image(systemName: "power")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ClipStyle.secondary)
                Text(lang.tr("quit_title"))
                    .font(ClipStyle.headline)
                HStack(spacing: 10) {
                    Button(action: { show = false }) {
                        Text(lang.tr("cancel"))
                            .font(ClipStyle.callout)
                            .frame(width: 88).padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(ClipStyle.grouped)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ClipStyle.secondary)

                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Text(lang.tr("quit_btn"))
                            .font(ClipStyle.callout.weight(.semibold))
                            .frame(width: 88).padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(white: 0.88))
                            )
                            .foregroundStyle(Color(white: 0.08))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous)
                    .strokeBorder(ClipStyle.border, lineWidth: 0.5)
            )
        }.transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: show)
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
                    Text(lang.tr("settings"))
                        .font(ClipStyle.headline)
                    Spacer()
                    ClipToolbarButton(systemName: "xmark") { show = false }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

                ClipSeparator().padding(.horizontal, 16)

                ScrollView {
                    VStack(spacing: 0) {
                        SettingsRow(title: lang.tr("launch_login"), subtitle: lang.tr("launch_login_sub")) {
                            Toggle("", isOn: Binding(
                                get: { SMAppService.mainApp.status == .enabled },
                                set: { val in try? val ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                            )).toggleStyle(.switch).controlSize(.small)
                        }

                        Divider().opacity(0.35).padding(.horizontal, 16)

                        SettingsRow(title: lang.tr("autopaste"), subtitle: checkAccessibility() ? lang.tr("enabled") : lang.tr("needed"),
                                    color: checkAccessibility() ? Color(white: 0.7) : Color(white: 0.45)) {
                            HStack(spacing: 6) {
                                if checkAccessibility() {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(white: 0.75)).font(.system(size: 14))
                                }
                                Button(lang.tr("enable")) { requestAccessibility() }
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.22)))
                                .foregroundColor(.white)
                                .buttonStyle(.plain)
                            }
                        }

                        Divider().opacity(0.35).padding(.horizontal, 16)

                        SettingsRow(title: lang.tr("updates"),
                                    subtitle: updater.isChecking ? lang.tr("checking") :
                                    (updater.hasUpdate ? String(format: lang.tr("available"), updater.latestVersion) : lang.tr("up_to_date")),
                                    color: updater.isChecking ? .secondary : (updater.hasUpdate ? Color(white: 0.55) : Color(white: 0.7))) {
                            if updater.isChecking {
                                ProgressView().controlSize(.mini)
                            } else if updater.hasUpdate {
                                Button(lang.tr("update_btn")) { updater.downloadAndUpdate() }
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.22)))
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

                        Divider().opacity(0.35).padding(.horizontal, 16)

                        SettingsRow(title: lang.tr("version"), subtitle: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6") {
                            EmptyView()
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(width: 340, height: 320)
            .background(ClipPanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: ClipStyle.windowRadius, style: .continuous))
        }.transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: show)
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
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(ClipStyle.caption.weight(.medium))
                    .foregroundStyle(ClipStyle.label)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ClipStyle.elevated)
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    )
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
                Text(title).font(ClipStyle.callout.weight(.medium))
                Text(subtitle).font(ClipStyle.caption2)
                    .foregroundStyle(color)
            }
            Spacer()
            value()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
