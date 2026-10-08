//
//  InAppDebug.swift
//  InAppDebugKit
//
//  In-app debug tools: API inspector, crash viewer, screen log, socket log and a floating
//  bubble to open them.
//

import UIKit
import SwiftUI

public enum InAppDebug {

    // MARK: - CONFIGURATION
    public struct Configuration {
        /// Checked once in `start(_:)`. Return false in production builds - nothing is then
        /// registered, swizzled or shown.
        public var isEnabled: () -> Bool

        /// Hosts whose HTTP(S) traffic is captured, matched as the host itself or any subdomain
        /// (`"example.com"` covers `api.example.com`). Empty = every host.
        public var capturedHosts: [String]

        /// Header values replaced with `••••` in the inspector and in copied cURL (case-insensitive).
        public var redactedHeaders: Set<String>

        /// Extra rows for Settings & App Info (environment, base URL, user id…).
        public var appInfo: () -> [(String, String)]

        /// Title of the Debug Tools sheet and of the bubble's quick-actions menu.
        public var title: String

        /// Whether to show the floating bubble (the user can still hide it from Settings).
        public var showsBubble: Bool

        /// How many entries are kept in memory per log.
        public var maxApiRequests: Int
        public var maxScreens: Int
        public var maxSocketEvents: Int

        public init(
            isEnabled: @escaping () -> Bool,
            capturedHosts: [String] = [],
            redactedHeaders: Set<String> = [],
            appInfo: @escaping () -> [(String, String)] = { [] },
            title: String = "Debug Tools",
            showsBubble: Bool = true,
            maxApiRequests: Int = 500,
            maxScreens: Int = 300,
            maxSocketEvents: Int = 1000
        ) {
            self.isEnabled = isEnabled
            self.capturedHosts = capturedHosts
            self.redactedHeaders = redactedHeaders
            self.appInfo = appInfo
            self.title = title
            self.showsBubble = showsBubble
            self.maxApiRequests = maxApiRequests
            self.maxScreens = maxScreens
            self.maxSocketEvents = maxSocketEvents
        }
    }

    static var configuration = Configuration(isEnabled: { false })
    public private(set) static var isStarted = false

    // MARK: - USER SETTINGS (persisted per device)
    private enum Keys {
        static let bubbleHidden = "inappdebug.bubbleHidden"
        static let captureAllHosts = "inappdebug.captureAllHosts"
    }

    /// When on, `capturedHosts` is ignored and every host is captured. Toggled from Settings.
    public static var captureAllHosts: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.captureAllHosts) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.captureAllHosts) }
    }

    public static var isBubbleHidden: Bool {
        get { !configuration.showsBubble || UserDefaults.standard.bool(forKey: Keys.bubbleHidden) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.bubbleHidden)
            DebugBubbleManager.shared.setHidden(newValue)
        }
    }

    // MARK: - START
    /// Call at the very start of `application(_:didFinishLaunchingWithOptions:)`, before the first
    /// network request: URLSessions created earlier are not captured.
    public static func start(_ configuration: Configuration) {
        guard !isStarted, configuration.isEnabled() else { return }
        self.configuration = configuration
        isStarted = true

        DebugCrashHandler.install()
        DebugNetworkCapture.install()
        DebugScreenTracker.install()
        _ = DebugStore.shared /// loads crashes from the previous session
    }

    /// Shows the floating bubble and the "crash recorded" alert. Call once the main window is
    /// visible (e.g. `SceneDelegate` after `makeKeyAndVisible()`).
    public static func attach(to windowScene: UIWindowScene) {
        guard isStarted else { return }
        DebugBubbleManager.shared.attach(to: windowScene)
        DebugCrashHandler.announcePreviousCrashIfNeeded()
    }

    // MARK: - LOGGING
    /// Adds a screen to the Screens log. Most screens are logged automatically; use this (or the
    /// `.debugScreen(_:)` modifier) for tabs, popups and other views without their own controller.
    public static func logScreen(_ name: String) {
        guard isStarted else { return }
        DebugBreadcrumbs.recordScreen(name)
        DebugStore.shared.addScreen(name)
    }

    /// Adds a WebSocket event to the Socket Events log. Call it from your socket code.
    /// - Parameters:
    ///   - name: event name; when nil it's read from the payload's `type` / `event` / `name`.
    ///   - data: the raw payload (JSON is pretty-printed in the detail screen).
    ///   - url: the socket URL, so events from different sockets can be told apart.
    public static func logSocket(_ direction: DebugSocketDirection, name: String? = nil, data: String = "", url: String? = nil) {
        guard isStarted else { return }
        let eventName = name ?? DebugFormatter.socketEventName(from: data) ?? direction.rawValue.lowercased()
        DebugStore.shared.addSocketEvent(
            DebugSocketEvent(id: UUID(), time: Date(), direction: direction, name: eventName, data: data, url: url)
        )
    }

    // MARK: - PRESENTATION
    /// Opens the Debug Tools sheet (e.g. from your own debug menu).
    public static func present() {
        present(.home)
    }

    static func present(_ destination: DebugDestination) {
        guard isStarted else { return }
        DispatchQueue.main.async {
            guard let top = UIApplication.debugTopViewController() else { return }
            /// already showing - don't stack another copy
            if top is DebugHostingController { return }
            let controller = DebugHostingController(rootView: DebugHomeView(initialDestination: destination))
            /// Bottom sheet: opens at half height, drag (or scroll) up for full height, swipe down to close.
            controller.modalPresentationStyle = .pageSheet
            if let sheet = controller.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = destination == .home ? .medium : .large
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                sheet.preferredCornerRadius = 20
            }
            top.present(controller, animated: true)
        }
    }
}

// MARK: - DESTINATIONS
enum DebugDestination: Hashable {
    case home
    case apiRequests
    case crashes
    case crash(UUID)
    case screens
    case sockets
}

/// Own subclass so `present` can tell the debug UI is already on top; hides the bubble meanwhile.
final class DebugHostingController: UIHostingController<DebugHomeView> {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DebugBubbleManager.shared.setTemporarilyHidden(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            DebugBubbleManager.shared.setTemporarilyHidden(false)
        }
    }
}

// MARK: - TOP VIEW CONTROLLER
extension UIApplication {
    /// Top-most controller of the app's own window (never the bubble window).
    static func debugTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first { !($0 is DebugBubbleWindow) && !$0.isHidden && $0.rootViewController != nil }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
