//
//  DebugScreenTracker.swift
//  InAppDebugKit
//
//  Screen tracking. SwiftUI apps have no base controller to hook, so this does two things:
//   1. swizzles `viewDidAppear` and reads the SwiftUI view name out of the hosting controller:
//      - root swaps:          UIHostingController<HomeView>                  -> "HomeView"
//      - NavigationLink push: NavigationStackHostingController<AnyView>      -> unwrapped -> "Profile"
//      - .sheet / cover:      PresentationHostingController<AnyView>         -> unwrapped -> "SettingsView"
//   2. `.debugScreen("Name")` for what has no controller of its own: TabView tabs (one generic
//      TabHostingController) and in-place overlays / popups / drawers.
//

import UIKit
import SwiftUI

enum DebugScreenTracker {

    private static var swizzled = false

    static func install() {
        guard !swizzled,
              let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewDidAppear(_:))),
              let replacement = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.debug_viewDidAppear(_:))) else {
            return
        }
        swizzled = true
        method_exchangeImplementations(original, replacement)
    }

    /// SwiftUI building blocks that are never a screen of their own (`Tree` = a NavigationStack's root content).
    private static let nonScreenViewNames: Set<String> = [
        "AnyView", "EmptyView", "Optional", "Tree", "TupleView", "Group",
        "VStack", "HStack", "ZStack", "NavigationStack", "NavigationView", "ScrollView", "List", "Color", "Text"
    ]

    fileprivate static func track(_ controller: UIViewController) {
        guard InAppDebug.isStarted, !isInsideDebugTools(controller) else { return }
        let rawName = String(describing: type(of: controller))

        /// SwiftUI screen: any `…HostingController<Content>`.
        if rawName.contains("HostingController<") {
            if let name = hostedViewName(controller, rawName: rawName) {
                InAppDebug.logScreen(name)
            }
            return
        }

        /// Anything else must be a controller written in the app or a third-party SDK. Apple's own
        /// (keyboard bar, share sheet, search, SwiftUI's tab / navigation containers…) is noise.
        let isAppleClass = Bundle(for: type(of: controller)).bundleIdentifier?.hasPrefix("com.apple.") ?? false
        guard !isAppleClass, !rawName.hasPrefix("_") else { return }
        /// Embedded inside a SwiftUI view (UIViewControllerRepresentable, e.g. the screenshot-protection
        /// wrapper or a camera preview) - part of that screen, which is already logged.
        if let parent = controller.parent, String(describing: type(of: parent)).contains("HostingController") { return }
        InAppDebug.logScreen(rawName)
    }

    /// Pushed screens and sheets are hosted as `…HostingController<AnyView>`. AnyView keeps the real
    /// view in its `storage` (`AnyViewStorage<ModifiedContent<Profile, …>>`), so read the type from there.
    private static func hostedViewName(_ controller: UIViewController, rawName: String) -> String? {
        var typeName = rawName
        if let host = controller as? UIHostingController<AnyView>,
           let storage = Mirror(reflecting: host.rootView).children.first?.value {
            typeName = String(describing: type(of: storage))
        }
        let name = screenName(from: typeName)
        guard !name.isEmpty, !name.hasPrefix("_"), !nonScreenViewNames.contains(name) else { return nil }
        return name
    }

    /// Debug Tools' own screens, sheets and search bar shouldn't fill the app's screen log.
    private static func isInsideDebugTools(_ controller: UIViewController) -> Bool {
        if controller.view.window is DebugBubbleWindow { return true }
        var current: UIViewController? = controller
        while let candidate = current {
            if candidate is DebugHostingController { return true }
            current = candidate.parent ?? candidate.presentingViewController
        }
        return false
    }

    /// "UIHostingController<ModifiedContent<HomeView, _EnvironmentKeyWritingModifier<…>>>" -> "HomeView"
    private static let wrapperPrefixes = [
        "ModifiedContent<", "Optional<", "_ConditionalContent<", "SheetContent<", "FullScreenCoverContent<"
    ]

    static func screenName(from rawName: String) -> String {
        guard let open = rawName.firstIndex(of: "<") else { return rawName }
        var inner = String(rawName[rawName.index(after: open)...].dropLast())
        /// SwiftUI wraps the real view in generic containers: modifiers, optionals, and the presentation
        /// wrapper of `.sheet` (`SheetContent<EarnMoreMoneyView>`). Peel them off to reach the app's view.
        while let wrapper = wrapperPrefixes.first(where: { inner.hasPrefix($0) }) {
            inner = String(inner.dropFirst(wrapper.count))
        }
        /// keep only the first generic argument, without its own generics
        let stopCharacters: Set<Character> = [",", "<", ">"]
        return String(inner.prefix { !stopCharacters.contains($0) }).trimmingCharacters(in: .whitespaces)
    }
}

extension UIViewController {
    @objc dynamic func debug_viewDidAppear(_ animated: Bool) {
        debug_viewDidAppear(animated) /// original implementation after the exchange
        DebugScreenTracker.track(self)
    }
}

// MARK: - MANUAL SCREEN TAG
private struct DebugScreenModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content.onAppear { InAppDebug.logScreen(name) }
    }
}

extension View {
    /// Logs `name` in Debug Tools → Screens when the view appears. No-op in prod builds.
    public func debugScreen(_ name: String) -> some View {
        modifier(DebugScreenModifier(name: name))
    }
}
