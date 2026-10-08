//
//  DebugFormatter.swift
//  InAppDebugKit
//

import Foundation

enum DebugFormatter {

    /// Bodies bigger than this are cut in the log (the real request/response is untouched).
    static let maxLoggedBodyBytes = 512 * 1024

    // MARK: - BODY
    static func bodyString(_ data: Data?, contentType: String?) -> String? {
        guard let data, !data.isEmpty else { return nil }

        let type = contentType?.lowercased() ?? ""
        let isBinary = type.hasPrefix("image/") || type.hasPrefix("video/") || type.hasPrefix("audio/")
            || type.contains("octet-stream") || type.contains("protobuf")
        if isBinary {
            return "<\(type) - \(byteCount(data.count))>"
        }
        if type.contains("multipart/form-data") {
            return "<multipart/form-data - \(byteCount(data.count))>"
        }

        let clipped = data.count > maxLoggedBodyBytes ? data.prefix(maxLoggedBodyBytes) : data
        let suffix = data.count > maxLoggedBodyBytes ? "\n\n… truncated (\(byteCount(data.count)) total)" : ""

        if let pretty = prettyJSON(Data(clipped)) {
            return pretty + suffix
        }
        if let text = String(data: clipped, encoding: .utf8) {
            return text + suffix
        }
        return "<binary - \(byteCount(data.count))>"
    }

    static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              object is [Any] || object is [String: Any],
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }

    // MARK: - HEADERS
    static func headers(_ fields: [AnyHashable: Any]?) -> [String: String] {
        var result: [String: String] = [:]
        fields?.forEach { key, value in result["\(key)"] = "\(value)" }
        return result
    }

    static func headersText(_ headers: [String: String]) -> String {
        headers.keys.sorted().map { "\($0): \(headers[$0] ?? "")" }.joined(separator: "\n")
    }

    // MARK: - CURL
    static func curl(for request: URLRequest, body: Data?, headers: [String: String]? = nil) -> String {
        let headers = headers ?? request.allHTTPHeaderFields ?? [:]
        var parts = ["curl -X \(request.httpMethod ?? "GET")"]
        headers.keys.sorted().forEach { key in
            parts.append("-H '\(escape("\(key): \(headers[key] ?? "")"))'")
        }
        if let body, !body.isEmpty, let text = String(data: body, encoding: .utf8) {
            parts.append("--data '\(escape(text))'")
        }
        parts.append("'\(escape(request.url?.absoluteString ?? ""))'")
        return parts.joined(separator: " \\\n  ")
    }

    /// Masks the values of `Configuration.redactedHeaders` (case-insensitive).
    static func redacted(_ headers: [String: String]) -> [String: String] {
        let hidden = Set(InAppDebug.configuration.redactedHeaders.map { $0.lowercased() })
        guard !hidden.isEmpty else { return headers }
        var result = headers
        for key in headers.keys where hidden.contains(key.lowercased()) {
            result[key] = "••••"
        }
        return result
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    // MARK: - MISC
    static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval else { return "-" }
        return interval < 1 ? "\(Int(interval * 1000)) ms" : String(format: "%.2f s", interval)
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, HH:mm:ss"
        return formatter
    }()

    /// Sent:     `{"type": "room_create", ...}`                     -> "room_create"
    /// Received: `{"event": {"name": "updated_game", "type": "on"}}` -> "updated_game"
    static func socketEventName(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let event = json["event"] as? [String: Any], let name = event["name"] as? String {
            return name
        }
        return (json["type"] ?? json["event"] ?? json["name"]) as? String
    }
}
