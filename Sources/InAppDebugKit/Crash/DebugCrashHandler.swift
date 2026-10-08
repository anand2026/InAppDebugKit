//
//  DebugCrashHandler.swift
//  InAppDebugKit
//
//  Crash capture. Records ObjC exceptions and
//  fatal signals (Swift traps like force-unwrap / fatalError / index out of range raise SIGTRAP)
//  to disk, then hands over to whatever handler was installed before (Crashlytics), so crash
//  reporting keeps working.
//
//  Work done inside a signal handler is best-effort: it is not strictly async-signal-safe, which
//  is acceptable for a debug-only tool. Crashlytics stays the source of truth for symbolicated stacks.
//

import UIKit

enum DebugCrashHandler {

    private static var previousExceptionHandler: (@convention(c) (NSException) -> Void)?
    private static var previousSignalActions: [Int32: sigaction] = [:]
    private static var hasRecorded = false

    private static let signals: [Int32: String] = [
        SIGABRT: "SIGABRT", SIGSEGV: "SIGSEGV", SIGBUS: "SIGBUS",
        SIGILL: "SIGILL", SIGTRAP: "SIGTRAP", SIGFPE: "SIGFPE"
    ]

    // MARK: - INSTALL
    static func install() {
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            DebugCrashHandler.record(
                kind: "NSException \(exception.name.rawValue)",
                reason: exception.reason ?? "Unknown reason",
                stack: exception.callStackSymbols
            )
            DebugCrashHandler.previousExceptionHandler?(exception)
        }

        for signalNumber in signals.keys {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { signalNumber in
                DebugCrashHandler.handleSignal(signalNumber)
            }
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0

            var previous = sigaction()
            sigaction(signalNumber, &action, &previous)
            previousSignalActions[signalNumber] = previous
        }
    }

    private static func handleSignal(_ signalNumber: Int32) {
        let name = signals[signalNumber] ?? "SIGNAL \(signalNumber)"
        record(
            kind: "Signal \(name)",
            reason: reason(for: signalNumber),
            stack: Thread.callStackSymbols
        )

        /// Restore the previous handler (Crashlytics / system default) and re-raise.
        if var previous = previousSignalActions[signalNumber] {
            sigaction(signalNumber, &previous, nil)
        } else {
            signal(signalNumber, SIG_DFL)
        }
        raise(signalNumber)
    }

    private static func reason(for signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGTRAP: return "Swift runtime trap (force unwrap of nil, fatalError, index out of range, bad cast…)"
        case SIGABRT: return "Abort (uncaught exception, Kotlin/Native crash, assertion…)"
        case SIGSEGV, SIGBUS: return "Bad memory access"
        case SIGILL: return "Illegal instruction"
        case SIGFPE: return "Arithmetic error"
        default: return "Fatal signal \(signalNumber)"
        }
    }

    // MARK: - RECORD
    private static func record(kind: String, reason: String, stack: [String]) {
        /// An NSException ends in SIGABRT as well - keep only the first, richer record.
        guard !hasRecorded else { return }
        hasRecorded = true

        let crash = DebugCrashEvent(
            id: UUID(),
            time: Date(),
            kind: kind,
            reason: reason,
            className: firstAppFrame(in: stack) ?? kind,
            stackTrace: stack.joined(separator: "\n"),
            lastScreen: DebugBreadcrumbs.lastScreen,
            lastApiCalls: DebugBreadcrumbs.lastApiCalls,
            appVersion: appVersion
        )
        DebugCrashStorage.save(crash)
    }

    /// Frames that are crash plumbing, not the code that crashed.
    /// "13InAppDebugKit" is this package's mangled module prefix, so it matches only the package's
    /// own frames (Swift mangling compresses type names, "DebugCrashHandler" isn't always literal)
    /// and not an app whose name merely starts with InAppDebugKit.
    private static let ignoredFrameMarkers = ["13InAppDebugKit", "DebugCrashHandler", "FIRCLS", "Crashlytics", "_sigtramp"]

    /// First frame from the app binary, skipping the debug tools, Crashlytics (statically linked
    /// into the app binary) and system frames.
    private static func firstAppFrame(in stack: [String]) -> String? {
        let executable = Bundle.main.executableURL?.lastPathComponent ?? ""
        return stack
            .filter { frame in
                frame.contains(executable) && !ignoredFrameMarkers.contains { frame.contains($0) }
            }
            .first
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).joined(separator: " ") }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    // MARK: - NEXT LAUNCH
    /// Shown on the next launch when a crash was recorded.
    static func announcePreviousCrashIfNeeded() {
        guard let crash = DebugStore.shared.crashes.first(where: { !$0.isViewed }) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let top = UIApplication.debugTopViewController() else { return }
            let alert = UIAlertController(
                title: "Crash recorded 💥",
                message: "\(crash.kind)\n\(crash.className)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Later", style: .cancel))
            alert.addAction(UIAlertAction(title: "View", style: .default) { _ in
                InAppDebug.present(.crash(crash.id))
            })
            top.present(alert, animated: true)
        }
    }
}
