//
//  DebugComponents.swift
//  InAppDebugKit
//
//  Small building blocks shared by the debug screens.
//

import SwiftUI
import UIKit

// MARK: - NON-LOCALIZED COPY
/// Debug-only UI text. Passing a `String` (not a literal) picks SwiftUI's `StringProtocol`
/// overloads, so Xcode doesn't extract these into Localizable.xcstrings for translation.
func dbg(_ text: String) -> String { text }

// MARK: - CODE BLOCK
/// Monospaced, selectable text with a copy button. Very large bodies are clipped on screen
/// (SwiftUI Text gets slow), but Copy / Share always use the full value.
struct DebugCodeBlock: View {
    let title: String
    let text: String?

    private let maxDisplayedCharacters = 40_000

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                if let text, !text.isEmpty {
                    DebugCopyButton(text: text)
                }
            }
            Group {
                if let text, !text.isEmpty {
                    Text(text.count > maxDisplayedCharacters
                         ? String(text.prefix(maxDisplayedCharacters)) + "\n\n… (copy to see the rest)"
                         : text)
                        .textSelection(.enabled)
                } else {
                    Text(verbatim: "Empty").foregroundColor(.secondary)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        }
    }
}

// MARK: - KEY VALUE
struct DebugKeyValueRow: View {
    let key: String
    let value: String?

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "-")
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DebugHeadersView: View {
    let title: String
    let headers: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                if !headers.isEmpty {
                    DebugCopyButton(text: DebugFormatter.headersText(headers))
                }
            }
            if headers.isEmpty {
                Text(verbatim: "None").font(.footnote).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(headers.keys.sorted(), id: \.self) { key in
                        DebugKeyValueRow(key: key, value: headers[key])
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
            }
        }
    }
}

// MARK: - COPY
struct DebugCopyButton: View {
    let text: String
    var label = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Label(dbg(copied ? "Copied" : label), systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - STATUS BADGE
struct DebugStatusBadge: View {
    let request: DebugApiRequest

    var body: some View {
        Text(request.status.map(String.init) ?? (request.error == nil ? "…" : "ERR"))
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(minWidth: 40)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(color))
    }

    private var color: Color {
        guard request.isFinished else { return .gray }
        if request.error != nil { return .red }
        switch request.status ?? 0 {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        default: return .red
        }
    }
}

// MARK: - EMPTY STATE (ContentUnavailableView is iOS 17+)
struct DebugEmptyState: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundColor(.secondary)
            Text(message).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
