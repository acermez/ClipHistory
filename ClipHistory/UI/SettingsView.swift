import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let monitor: PasteboardMonitor
    let onClearHistory: () -> Void

    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var accessibilityAllowed = AXIsProcessTrusted()
    @State private var clipboardDenied = false
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Open history", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Picker("Keep up to", selection: $settings.historyLimit) {
                    ForEach(AppSettings.limitChoices, id: \.self) { Text("\($0) items").tag($0) }
                }
                Button("Clear history…", role: .destructive, action: onClearHistory)
            } header: {
                Text("History")
            } footer: {
                Text("Pinned items are never removed.")
                    .foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in setOpenAtLogin(enabled) }
                if let loginError {
                    Text(loginError).foregroundStyle(.red).font(.caption)
                }
            }
            Section {
                permissionRow(
                    title: "Accessibility",
                    detail: "Pastes the item for you when you press Return.",
                    ok: accessibilityAllowed,
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                permissionRow(
                    title: "Paste from other apps",
                    detail: "Lets the app read what you copy. Set it to Allow.",
                    ok: !clipboardDenied,
                    url: "x-apple.systempreferences:com.apple.preference.security")
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshStatus)
        .onReceive(refresh) { _ in refreshStatus() }
    }

    private func permissionRow(title: String, detail: String, ok: Bool, url: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if ok {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Open Settings") {
                    if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                }
            }
        }
    }

    private func refreshStatus() {
        accessibilityAllowed = AXIsProcessTrusted()
        clipboardDenied = monitor.accessDenied
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
