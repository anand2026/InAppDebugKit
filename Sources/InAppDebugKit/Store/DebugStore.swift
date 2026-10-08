//
//  DebugStore.swift
//  InAppDebugKit
//
//  In-memory store for the debug tools. API, screen and socket
//  logs live for the session; crashes are persisted to disk so they survive the crash itself.
//

import Foundation
import Combine

final class DebugStore: ObservableObject {

    static let shared = DebugStore()

    // MARK: LIMITS
    private var maxApiRequests: Int { InAppDebug.configuration.maxApiRequests }
    private var maxScreens: Int { InAppDebug.configuration.maxScreens }
    private var maxSocketEvents: Int { InAppDebug.configuration.maxSocketEvents }

    // MARK: PUBLISHED STATE (main thread only)
    @Published private(set) var apiRequests: [DebugApiRequest] = []
    @Published private(set) var screens: [DebugScreenEvent] = []
    @Published private(set) var socketEvents: [DebugSocketEvent] = []
    @Published private(set) var crashes: [DebugCrashEvent] = []

    /// Fires for every finished API call; the bubble flashes green / red on it.
    let apiFinished = PassthroughSubject<DebugApiRequest, Never>()

    var unseenCrashCount: Int { crashes.filter { !$0.isViewed }.count }

    private init() {
        crashes = DebugCrashStorage.loadAll()
    }

    // MARK: - API
    func addApiRequest(_ request: DebugApiRequest) {
        onMain {
            self.apiRequests.insert(request, at: 0)
            if self.apiRequests.count > self.maxApiRequests {
                self.apiRequests.removeLast(self.apiRequests.count - self.maxApiRequests)
            }
        }
    }

    func updateApiRequest(_ request: DebugApiRequest) {
        onMain {
            if let index = self.apiRequests.firstIndex(where: { $0.id == request.id }) {
                self.apiRequests[index] = request
            } else {
                self.apiRequests.insert(request, at: 0)
            }
            DebugBreadcrumbs.recordApi(request.summaryLine)
            self.apiFinished.send(request)
        }
    }

    func clearApiRequests() {
        onMain { self.apiRequests.removeAll() }
    }

    // MARK: - SCREENS
    func addScreen(_ name: String) {
        onMain {
            /// SwiftUI re-appears the same host a lot (tab switches, sheets) - skip exact repeats
            if self.screens.first?.name == name { return }
            self.screens.insert(DebugScreenEvent(id: UUID(), name: name, time: Date()), at: 0)
            if self.screens.count > self.maxScreens {
                self.screens.removeLast(self.screens.count - self.maxScreens)
            }
        }
    }

    func clearScreens() {
        onMain { self.screens.removeAll() }
    }

    // MARK: - SOCKETS
    func addSocketEvent(_ event: DebugSocketEvent) {
        onMain {
            self.socketEvents.insert(event, at: 0)
            if self.socketEvents.count > self.maxSocketEvents {
                self.socketEvents.removeLast(self.socketEvents.count - self.maxSocketEvents)
            }
        }
    }

    func clearSocketEvents() {
        onMain { self.socketEvents.removeAll() }
    }

    // MARK: - CRASHES
    func markCrashViewed(_ crash: DebugCrashEvent) {
        onMain {
            guard let index = self.crashes.firstIndex(where: { $0.id == crash.id }),
                  !self.crashes[index].isViewed else { return }
            self.crashes[index].isViewed = true
            DebugCrashStorage.save(self.crashes[index])
        }
    }

    func clearCrashes() {
        onMain {
            self.crashes.removeAll()
            DebugCrashStorage.deleteAll()
        }
    }

    func clearAll() {
        clearApiRequests()
        clearScreens()
        clearSocketEvents()
        clearCrashes()
    }

    // MARK: - HELPERS
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - BREADCRUMBS
/// Plain values the crash handler can read without touching the main-thread store.
/// Reads from a crashing thread are best-effort by design.
enum DebugBreadcrumbs {
    private static let lock = NSLock()
    private(set) static var lastScreen: String?
    private(set) static var lastApiCalls: [String] = []

    static func recordScreen(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        lastScreen = name
    }

    static func recordApi(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lastApiCalls.insert(line, at: 0)
        if lastApiCalls.count > 5 { lastApiCalls.removeLast() }
    }
}

// MARK: - CRASH FILE STORAGE
enum DebugCrashStorage {

    static var directory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("InAppDebugKit/Crashes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func save(_ crash: DebugCrashEvent) {
        guard let dir = directory, let data = try? JSONEncoder().encode(crash) else { return }
        try? data.write(to: dir.appendingPathComponent("\(crash.id.uuidString).json"), options: .atomic)
    }

    static func loadAll() -> [DebugCrashEvent] {
        guard let dir = directory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(DebugCrashEvent.self, from: Data(contentsOf: $0)) }
            .sorted { $0.time > $1.time }
    }

    static func deleteAll() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
