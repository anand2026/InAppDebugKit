//
//  DebugScreenSocketViews.swift
//  InAppDebugKit
//
//  Screen timeline + socket event list / detail.
//

import SwiftUI

// MARK: - SCREENS
struct DebugScreensView: View {
    @ObservedObject private var store = DebugStore.shared

    var body: some View {
        Group {
            if store.screens.isEmpty {
                DebugEmptyState(icon: "rectangle.stack", message: "No screens logged yet.")
            } else {
                List(store.screens) { screen in
                    HStack {
                        Text(screen.name).font(.system(size: 14, design: .monospaced))
                        Spacer()
                        Text(DebugFormatter.timeFormatter.string(from: screen.time))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(dbg("Screens"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { store.clearScreens() } label: { Image(systemName: "trash") }
                    .disabled(store.screens.isEmpty)
            }
        }
    }
}

// MARK: - SOCKETS
struct DebugSocketEventsView: View {
    @ObservedObject private var store = DebugStore.shared
    @State private var searchText = ""

    private var events: [DebugSocketEvent] {
        guard !searchText.isEmpty else { return store.socketEvents }
        let query = searchText.lowercased()
        return store.socketEvents.filter {
            $0.name.lowercased().contains(query) || $0.data.lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if events.isEmpty {
                DebugEmptyState(icon: "bolt.horizontal", message: store.socketEvents.isEmpty
                                ? "No socket events yet." : "No events match.")
            } else {
                List(events) { event in
                    NavigationLink {
                        DebugSocketEventDetailView(event: event)
                    } label: {
                        DebugSocketEventRow(event: event)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: Text(verbatim: "Event name or payload"))
        .navigationTitle(dbg("Socket Events"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { store.clearSocketEvents() } label: { Image(systemName: "trash") }
                    .disabled(store.socketEvents.isEmpty)
            }
        }
    }
}

private struct DebugSocketEventRow: View {
    let event: DebugSocketEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.name).font(.system(size: 14, weight: .semibold, design: .monospaced))
                if !event.data.isEmpty {
                    Text(event.data)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(verbatim: "\(event.direction.rawValue) · \(DebugFormatter.timeFormatter.string(from: event.time))")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    private var icon: String {
        switch event.direction {
        case .send: return "arrow.up.circle.fill"
        case .receive: return "arrow.down.circle.fill"
        case .connect: return "link.circle.fill"
        case .disconnect: return "xmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch event.direction {
        case .send: return .blue
        case .receive: return .green
        case .connect: return .teal
        case .disconnect: return .gray
        case .error: return .red
        }
    }
}

struct DebugSocketEventDetailView: View {
    let event: DebugSocketEvent

    private var prettyData: String {
        event.data.data(using: .utf8).flatMap(DebugFormatter.prettyJSON) ?? event.data
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    DebugKeyValueRow(key: "Event", value: event.name)
                    DebugKeyValueRow(key: "Direction", value: event.direction.rawValue)
                    DebugKeyValueRow(key: "Time", value: DebugFormatter.dateTimeFormatter.string(from: event.time))
                    DebugKeyValueRow(key: "URL", value: event.url)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

                DebugCodeBlock(title: "Payload", text: prettyData)
            }
            .padding()
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: "\(event.direction.rawValue) \(event.name)\n\(prettyData)") {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}
