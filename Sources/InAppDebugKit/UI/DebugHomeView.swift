//
//  DebugHomeView.swift
//  InAppDebugKit
//
//  Debug Tools home menu.
//

import SwiftUI

struct DebugHomeView: View {

    @ObservedObject private var store = DebugStore.shared
    @State private var path: [DebugDestination]
    @State private var showClearConfirmation = false

    init(initialDestination: DebugDestination = .home) {
        switch initialDestination {
        case .home:
            _path = State(initialValue: [])
        case .crash:
            _path = State(initialValue: [.crashes, initialDestination])
        default:
            _path = State(initialValue: [initialDestination])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section(dbg("Logs")) {
                    row(.apiRequests, icon: "network", title: "API Requests", count: store.apiRequests.count,
                        highlight: store.apiRequests.filter(\.isFailure).count)
                    row(.crashes, icon: "exclamationmark.triangle", title: "Crashes", count: store.crashes.count,
                        highlight: store.unseenCrashCount)
                    row(.screens, icon: "rectangle.stack", title: "Screens", count: store.screens.count)
                    row(.sockets, icon: "bolt.horizontal", title: "Socket Events", count: store.socketEvents.count)
                }

                Section(dbg("App")) {
                    NavigationLink {
                        DebugSettingsView()
                    } label: {
                        Label(dbg("Settings & App Info"), systemImage: "gearshape")
                    }
                    NavigationLink {
                        DebugUserDefaultsView()
                    } label: {
                        Label(dbg("User Defaults"), systemImage: "list.bullet.rectangle")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label(dbg("Clear all logs"), systemImage: "trash")
                    }
                }
            }
            .navigationTitle(dbg(InAppDebug.configuration.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(dbg("Close")) { InAppDebug.dismiss() }
                }
            }
            .navigationDestination(for: DebugDestination.self) { destination in
                switch destination {
                case .home: EmptyView()
                case .apiRequests: DebugApiRequestsView()
                case .crashes: DebugCrashListView()
                case .crash(let id): DebugCrashDetailView(crashId: id)
                case .screens: DebugScreensView()
                case .sockets: DebugSocketEventsView()
                }
            }
            .confirmationDialog(dbg("Clear API, screen, socket and crash logs?"), isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button(dbg("Clear all"), role: .destructive) { store.clearAll() }
            }
        }
    }

    private func row(_ destination: DebugDestination, icon: String, title: String, count: Int, highlight: Int = 0) -> some View {
        NavigationLink(value: destination) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if highlight > 0 {
                    Text(verbatim: "\(highlight)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                }
                Text(verbatim: "\(count)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - DISMISS
extension InAppDebug {
    static func dismiss() {
        var controller = UIApplication.debugTopViewController()
        while let current = controller, !(current is DebugHostingController) {
            controller = current.presentingViewController
        }
        controller?.dismiss(animated: true)
    }
}
