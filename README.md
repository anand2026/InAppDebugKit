# InAppDebugKit

In-app debug tools for iOS: inspect **API requests**, **crashes**, **screens** and **WebSocket events** right on the device, from a floating bubble. No Xcode, no proxy.

- **API Requests**: every HTTP(S) call made through `URLSession` (and libraries built on it: Alamofire, Moya, Apollo, Ktor's Darwin engine…). URL, method, headers, request/response body (pretty JSON), status, duration, size, and a ready-to-run cURL. Search, Errors / Slow filters, copy and share.
- **Crashes**: Swift traps (force unwrap, `fatalError`, index out of range), Objective-C exceptions and fatal signals are saved to disk. On the next launch you get a "Crash recorded" alert with the reason, the last screen, the last 5 API calls and the stack trace. Crashes are passed on to any previously installed handler (e.g. Firebase Crashlytics).
- **Screens**: a timeline of every screen shown. SwiftUI views get their real names, including pushed screens and sheets.
- **Socket Events**: connect / send / receive / close / error, logged from your socket code.
- **Floating bubble**: shows the request count, flashes green/red per call, turns red after a crash. Tap to open, long-press for quick actions, drag to move.
- **Settings & App Info**, a **UserDefaults** viewer and **Clear all logs**.

Requires **iOS 16+**, Swift 5.9+.

## Installation

Swift Package Manager: **File → Add Package Dependencies…** and enter this repository's URL, or in `Package.swift`:

```swift
.package(url: "https://github.com/anand2026/InAppDebugKit.git", from: "1.0.0")
```

## Setup

**1. Start it** at the very beginning of `application(_:didFinishLaunchingWithOptions:)`, before any network request. Sessions created earlier are not captured.

```swift
import InAppDebugKit

InAppDebug.start(.init(
    isEnabled: {
        #if DEBUG
        return true
        #else
        return false
        #endif
    },
    capturedHosts: ["api.myapp.com"],      // empty = capture every host
    redactedHeaders: ["Authorization"],    // shown as •••• in the inspector and cURL
    appInfo: { [("Environment", "Staging"), ("User id", Session.userId)] },
    title: "MyApp Debug Tools"
))
```

`isEnabled` is checked once. When it returns `false`, nothing is installed, swizzled or shown, so production users are unaffected. You can use any runtime flag (e.g. a QA build setting) instead of `#if DEBUG`.

**2. Show the bubble** once your window is visible (e.g. in `SceneDelegate`):

```swift
window.makeKeyAndVisible()
InAppDebug.attach(to: windowScene)
```

**3. (Optional) Log socket events** from your WebSocket code. WebSocket frames are not HTTP, so they can't be captured automatically:

```swift
InAppDebug.logSocket(.connect, name: "connected", url: url.absoluteString)
InAppDebug.logSocket(.send, data: jsonString, url: url.absoluteString)      // name read from "type" / "event" / "name"
InAppDebug.logSocket(.receive, data: text, url: url.absoluteString)
InAppDebug.logSocket(.disconnect, name: "closed (\(code.rawValue))", url: url.absoluteString)
InAppDebug.logSocket(.error, name: "error", data: error.localizedDescription, url: url.absoluteString)
```

**4. (Optional) Name screens** that have no controller of their own (tabs inside a `TabView`, overlays, popups):

```swift
HomeTab().debugScreen("HomeTab")
```

**5. (Optional) Open it from your own debug menu:** `InAppDebug.present()`.

## Configuration

| Option | Default | |
|---|---|---|
| `isEnabled` | (required) | Return `false` in production. |
| `capturedHosts` | `[]` (all) | Hosts to capture; subdomains included. Keep it to your own API to leave third-party SDK traffic untouched. |
| `redactedHeaders` | `[]` | Header values masked in the UI and cURL. The real request is not changed. |
| `appInfo` | `[]` | Extra rows for Settings & App Info. |
| `title` | `"Debug Tools"` | Sheet and menu title. |
| `showsBubble` | `true` | Users can also hide it from Settings. |
| `maxApiRequests` / `maxScreens` / `maxSocketEvents` | 500 / 300 / 1000 | In-memory log sizes. |

## How it works

- **Network**: a `URLProtocol` is registered for `URLSession.shared`, and `URLSessionConfiguration.default` / `.ephemeral` are swizzled so sessions created later (Alamofire, Ktor…) include it too. Each captured request is replayed through an internal session and the response is passed back to the app unchanged.
- **Screens**: `UIViewController.viewDidAppear` is swizzled. The view name is read from the SwiftUI hosting controller, including the real view inside `AnyView`, `.sheet` and `.fullScreenCover`.
- **Crashes**: `NSSetUncaughtExceptionHandler` plus signal handlers (SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE). The report is written to `Application Support/InAppDebugKit/Crashes`, then the previous handler is called.

## Limitations: read before using

- **Debug / QA only.** Uses method swizzling and replays network requests. Keep `isEnabled` false in App Store builds. SPM can't link a package to the Debug configuration only, so the code is in the release binary but inactive.
- **SSL certificate pinning**: requests to captured hosts are sent by the package's own session, so the app's pinning delegate does not run for them. Exclude pinned hosts via `capturedHosts`.
- **Custom session delegates** (redirect handling, auth challenges, task metrics) of captured requests are not called the way they normally would be.
- **Upload progress**: request bodies are read up front, so upload progress callbacks may jump straight to 100%.
- **Background `URLSession`s** are not captured (iOS doesn't allow it).
- **Sessions created before `start(_:)`**, or ones that replace `protocolClasses` themselves, are not captured.
- **WebSockets** need manual `logSocket(...)` calls. Binary frames aren't logged unless you log them.
- **Logs are in memory**, except crashes, and reset on relaunch.
- **Redaction covers headers only**, not body content.
- **Other network debuggers** (Pulse, netfox, Wormholy, Atlantis) swizzle the same APIs. Use one at a time.
- **Release builds** show unsymbolicated stack frames (module + offset). Use your crash reporter for symbolicated traces.
- The "Crash recorded" alert is shown 2 s after `attach`. If your app replaces the window's root view controller right after launch, the alert may be dismissed with it; the crash is still listed under Crashes and the bubble shows "!".

## Example

`Example/InAppDebugKitExample.xcodeproj` is a small app that exercises every feature: requests (GET / POST / 404 / redacted header / uncaptured host), socket events, pushed and presented screens, and a crash button.

## License

MIT. See [LICENSE](LICENSE).
