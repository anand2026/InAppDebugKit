//
//  DebugSettingsViews.swift
//  InAppDebugKit
//
//  Debug tools settings, app info and a UserDefaults viewer.
//

import SwiftUI

struct DebugSettingsView: View {

    @State private var bubbleVisible = !InAppDebug.isBubbleHidden
    @State private var captureAllHosts = InAppDebug.captureAllHosts

    private var bubbleBinding: Binding<Bool> {
        Binding(get: { bubbleVisible }, set: { bubbleVisible = $0; InAppDebug.isBubbleHidden = !$0 })
    }

    private var captureAllHostsBinding: Binding<Bool> {
        Binding(get: { captureAllHosts }, set: { captureAllHosts = $0; InAppDebug.captureAllHosts = $0 })
    }
    @State private var cacheCleared = false

    private var captureAllHostsCaption: String {
        let hosts = InAppDebug.configuration.capturedHosts
        return hosts.isEmpty
            ? "All hosts are already captured (no capturedHosts configured)."
            : "Also log third-party SDK traffic. Off = only \(hosts.joined(separator: ", "))."
    }

    private var info: [(String, String)] {
        let bundle = Bundle.main.infoDictionary
        let standard: [(String, String)] = [
            ("App version", bundle?["CFBundleShortVersionString"] as? String ?? "-"),
            ("Build", bundle?["CFBundleVersion"] as? String ?? "-"),
            ("Bundle id", Bundle.main.bundleIdentifier ?? "-"),
            ("iOS", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
            ("Device", UIDevice.current.model)
        ]
        /// App-provided rows (environment, base URL, user id…) come first.
        return InAppDebug.configuration.appInfo() + standard
    }

    var body: some View {
        List {
            Section(dbg("Debug tools")) {
                Toggle(dbg("Show floating bubble"), isOn: bubbleBinding)
                Toggle(isOn: captureAllHostsBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Capture all hosts")
                        Text(verbatim: captureAllHostsCaption)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(dbg("App info")) {
                ForEach(Array(info.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.caption).foregroundColor(.secondary)
                        Text(item.1.isEmpty ? "-" : item.1)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                DebugCopyButton(text: info.map { "\($0.0): \($0.1)" }.joined(separator: "\n"), label: "Copy all")
            }

            Section(dbg("Storage")) {
                Button(dbg(cacheCleared ? "URL cache cleared ✓" : "Clear URL cache")) {
                    URLCache.shared.removeAllCachedResponses()
                    cacheCleared = true
                }
            }
        }
        .navigationTitle(dbg("Settings & App Info"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - USER DEFAULTS
struct DebugUserDefaultsView: View {

    @State private var searchText = ""
    @State private var entries: [(key: String, value: String)] = []

    private var filtered: [(key: String, value: String)] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query) }
    }

    var body: some View {
        List(filtered, id: \.key) { entry in
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.key).font(.caption.bold())
                Text(entry.value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            .contextMenu {
                Button(dbg("Copy value")) { UIPasteboard.general.string = entry.value }
                Button(dbg("Copy key")) { UIPasteboard.general.string = entry.key }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: Text(verbatim: "Key or value"))
        .navigationTitle(dbg("User Defaults"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        /// Only the app's own domain, not the system/global keys.
        let domain = Bundle.main.bundleIdentifier ?? ""
        let values = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        entries = values
            .map { (key: $0.key, value: String(describing: $0.value)) }
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
    }
}
