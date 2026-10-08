//
//  DebugApiRequestViews.swift
//  InAppDebugKit
//
//  API request list + detail (Overview / Request / Response tabs).
//

import SwiftUI

// MARK: - LIST
struct DebugApiRequestsView: View {

    private enum Filter: String, CaseIterable {
        case all = "All"
        case errors = "Errors"
        case slow = "Slow > 2s"
    }

    @ObservedObject private var store = DebugStore.shared
    @State private var searchText = ""
    @State private var filter: Filter = .all

    private var requests: [DebugApiRequest] {
        store.apiRequests.filter { request in
            switch filter {
            case .all: break
            case .errors: guard request.isFailure else { return false }
            case .slow: guard (request.duration ?? 0) > 2 else { return false }
            }
            guard !searchText.isEmpty else { return true }
            let query = searchText.lowercased()
            return request.url.lowercased().contains(query)
                || request.method.lowercased().contains(query)
                || (request.status.map(String.init) ?? "").contains(query)
                || (request.requestBody?.lowercased().contains(query) ?? false)
                || (request.responseBody?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(dbg("Filter"), selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if requests.isEmpty {
                DebugEmptyState(icon: "network", message: store.apiRequests.isEmpty
                                ? "No API calls captured yet.\nUse the app and they'll show up here."
                                : "No requests match.")
            } else {
                List(requests) { request in
                    NavigationLink {
                        DebugApiDetailView(requestId: request.id)
                    } label: {
                        DebugApiRequestRow(request: request)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: Text(verbatim: "URL, status, body…"))
        .navigationTitle(dbg("API Requests"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { store.clearApiRequests() } label: { Image(systemName: "trash") }
                    .disabled(store.apiRequests.isEmpty)
            }
        }
    }
}

struct DebugApiRequestRow: View {
    let request: DebugApiRequest

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DebugStatusBadge(request: request)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(request.method) \(request.path)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .lineLimit(2)
                Text(request.host)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(DebugFormatter.timeFormatter.string(from: request.startedAt))
                    Text(DebugFormatter.duration(request.duration))
                    if request.isFinished {
                        Text(DebugFormatter.byteCount(request.responseSize))
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                if let error = request.error {
                    Text(error).font(.caption2).foregroundColor(.red).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - DETAIL
struct DebugApiDetailView: View {

    private enum Tab: String, CaseIterable {
        case overview = "Overview"
        case request = "Request"
        case response = "Response"
    }

    let requestId: UUID
    @ObservedObject private var store = DebugStore.shared
    @State private var tab: Tab = .overview

    /// Looked up live so an in-flight request fills in when it finishes.
    private var request: DebugApiRequest? {
        store.apiRequests.first { $0.id == requestId }
    }

    var body: some View {
        Group {
            if let request {
                VStack(spacing: 0) {
                    Picker(dbg("Tab"), selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch tab {
                            case .overview: overview(request)
                            case .request: requestTab(request)
                            case .response: responseTab(request)
                            }
                        }
                        .padding([.horizontal, .bottom])
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareText(request)) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            } else {
                DebugEmptyState(icon: "questionmark", message: "This request was cleared.")
            }
        }
        .navigationTitle(dbg(request.map { "\($0.method) \($0.path)" } ?? "Request"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func overview(_ request: DebugApiRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DebugKeyValueRow(key: "URL", value: request.url)
            DebugKeyValueRow(key: "Method", value: request.method)
            DebugKeyValueRow(key: "Status", value: request.status.map(String.init) ?? (request.isFinished ? "-" : "In progress…"))
            DebugKeyValueRow(key: "Error", value: request.error)
            DebugKeyValueRow(key: "Host", value: request.host)
            DebugKeyValueRow(key: "Path", value: request.path)
            DebugKeyValueRow(key: "Query", value: request.query)
            DebugKeyValueRow(key: "Started", value: DebugFormatter.dateTimeFormatter.string(from: request.startedAt))
            DebugKeyValueRow(key: "Duration", value: DebugFormatter.duration(request.duration))
            DebugKeyValueRow(key: "Size", value: DebugFormatter.byteCount(request.responseSize))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

        HStack {
            DebugCopyButton(text: request.url, label: "Copy URL")
            DebugCopyButton(text: request.curl, label: "Copy cURL")
        }

        DebugCodeBlock(title: "cURL", text: request.curl)
    }

    @ViewBuilder
    private func requestTab(_ request: DebugApiRequest) -> some View {
        DebugHeadersView(title: "Headers", headers: request.requestHeaders)
        DebugCodeBlock(title: "Body", text: request.requestBody)
    }

    @ViewBuilder
    private func responseTab(_ request: DebugApiRequest) -> some View {
        DebugHeadersView(title: "Headers", headers: request.responseHeaders)
        DebugCodeBlock(title: "Body", text: request.responseBody ?? request.error)
    }

    private func shareText(_ request: DebugApiRequest) -> String {
        """
        \(request.method) \(request.url)
        Status: \(request.status.map(String.init) ?? request.error ?? "-")
        Duration: \(DebugFormatter.duration(request.duration))
        Time: \(DebugFormatter.dateTimeFormatter.string(from: request.startedAt))

        ── Request headers ──
        \(DebugFormatter.headersText(request.requestHeaders))

        ── Request body ──
        \(request.requestBody ?? "-")

        ── Response headers ──
        \(DebugFormatter.headersText(request.responseHeaders))

        ── Response body ──
        \(request.responseBody ?? "-")

        ── cURL ──
        \(request.curl)
        """
    }
}
