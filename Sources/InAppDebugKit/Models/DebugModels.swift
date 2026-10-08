//
//  DebugModels.swift
//  InAppDebugKit
//
//  Log entry models: API request, crash, screen and socket event.
//

import Foundation

// MARK: - API REQUEST
struct DebugApiRequest: Identifiable, Codable, Equatable {
    let id: UUID
    var url: String
    var method: String
    var scheme: String
    var host: String
    var path: String
    var query: String?
    var requestHeaders: [String: String]
    var requestBody: String?
    var startedAt: Date

    var status: Int?
    var responseHeaders: [String: String] = [:]
    var responseBody: String?
    var responseSize: Int = 0
    var duration: TimeInterval?
    var error: String?
    var curl: String

    var isFinished: Bool { status != nil || error != nil }
    var isFailure: Bool { error != nil || (status ?? 0) >= 400 }

    /// "200 GET /api/user/profile"
    var summaryLine: String {
        let code = status.map(String.init) ?? (error == nil ? "..." : "ERR")
        return "\(code) \(method) \(path)"
    }
}

// MARK: - CRASH
struct DebugCrashEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var time: Date
    var kind: String          /// "NSException" / "Signal SIGSEGV" / ...
    var reason: String
    var className: String     /// first meaningful frame of the app's own code
    var stackTrace: String
    var lastScreen: String?
    var lastApiCalls: [String]
    var appVersion: String
    var isViewed: Bool = false
}

// MARK: - SCREEN
struct DebugScreenEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var time: Date
}

// MARK: - SOCKET
public enum DebugSocketDirection: String, Codable {
    case send = "SEND"
    case receive = "RECEIVE"
    case connect = "CONNECT"
    case disconnect = "DISCONNECT"
    case error = "ERROR"
}

struct DebugSocketEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var time: Date
    var direction: DebugSocketDirection
    var name: String          /// the event "type" when the payload is JSON
    var data: String
    var url: String?
}
