//
//  DebugCrashViews.swift
//  InAppDebugKit
//
//  Crash list + crash detail.
//

import SwiftUI

struct DebugCrashListView: View {
    @ObservedObject private var store = DebugStore.shared

    var body: some View {
        Group {
            if store.crashes.isEmpty {
                DebugEmptyState(icon: "checkmark.shield", message: "No crashes recorded.")
            } else {
                List(store.crashes) { crash in
                    NavigationLink(value: DebugDestination.crash(crash.id)) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(crash.isViewed ? Color.clear : Color.red)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(crash.kind).font(.subheadline.bold())
                                Text(crash.className)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(2)
                                Text(verbatim: "\(DebugFormatter.dateTimeFormatter.string(from: crash.time)) · v\(crash.appVersion)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(dbg("Crashes"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { store.clearCrashes() } label: { Image(systemName: "trash") }
                    .disabled(store.crashes.isEmpty)
            }
        }
    }
}

struct DebugCrashDetailView: View {
    let crashId: UUID
    @ObservedObject private var store = DebugStore.shared

    private var crash: DebugCrashEvent? {
        store.crashes.first { $0.id == crashId }
    }

    var body: some View {
        Group {
            if let crash {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            DebugKeyValueRow(key: "Type", value: crash.kind)
                            DebugKeyValueRow(key: "Reason", value: crash.reason)
                            DebugKeyValueRow(key: "Where", value: crash.className)
                            DebugKeyValueRow(key: "Time", value: DebugFormatter.dateTimeFormatter.string(from: crash.time))
                            DebugKeyValueRow(key: "App version", value: crash.appVersion)
                            DebugKeyValueRow(key: "Last screen", value: crash.lastScreen)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

                        DebugCodeBlock(title: "Last API calls", text: crash.lastApiCalls.joined(separator: "\n"))
                        DebugCodeBlock(title: "Stack trace", text: crash.stackTrace)
                    }
                    .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareText(crash)) { Image(systemName: "square.and.arrow.up") }
                    }
                }
                .onAppear { store.markCrashViewed(crash) }
            } else {
                DebugEmptyState(icon: "questionmark", message: "This crash was cleared.")
            }
        }
        .navigationTitle(dbg("Crash"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shareText(_ crash: DebugCrashEvent) -> String {
        """
        💥 \(crash.kind)
        Reason: \(crash.reason)
        Where: \(crash.className)
        Time: \(DebugFormatter.dateTimeFormatter.string(from: crash.time))
        App version: \(crash.appVersion)
        Last screen: \(crash.lastScreen ?? "-")

        Last API calls:
        \(crash.lastApiCalls.joined(separator: "\n"))

        Stack trace:
        \(crash.stackTrace)
        """
    }
}
