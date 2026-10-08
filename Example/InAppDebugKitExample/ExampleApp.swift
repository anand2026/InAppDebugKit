//
//  ExampleApp.swift
//  InAppDebugKitExample
//
//  Minimal app showing every InAppDebugKit feature: API capture, sockets, screens, crashes.
//

import UIKit
import SwiftUI
import InAppDebugKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        InAppDebug.start(.init(
            isEnabled: {
                #if DEBUG
                return true
                #else
                return false
                #endif
            },
            capturedHosts: ["jsonplaceholder.typicode.com", "httpbin.org"],
            redactedHeaders: ["Authorization"],
            appInfo: { [("Environment", "Example"), ("Base URL", "https://jsonplaceholder.typicode.com")] },
            title: "Example Debug Tools"
        ))
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ContentView())
        self.window = window
        window.makeKeyAndVisible()
        InAppDebug.attach(to: windowScene)
    }
}

struct ContentView: View {
    @State private var status = "Tap a button"
    @State private var showSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("Network") {
                    Button("GET /posts/1") { get("https://jsonplaceholder.typicode.com/posts/1") }
                    Button("POST /posts (JSON body)") { post() }
                    Button("GET 404") { get("https://jsonplaceholder.typicode.com/this-does-not-exist") }
                    Button("GET with Authorization (redacted)") { getWithAuth() }
                    Button("GET other host (not captured)") { get("https://example.com") }
                }
                Section("Sockets") {
                    Button("Log socket events") { logSocketEvents() }
                }
                Section("Screens") {
                    NavigationLink("Push DetailView") { DetailView() }
                    Button("Present SettingsSheet") { showSheet = true }
                }
                Section("Debug") {
                    Button("Open Debug Tools") { InAppDebug.present() }
                    Button("Crash (force unwrap nil)", role: .destructive) { crash() }
                }
                Section { Text(status).font(.footnote).foregroundColor(.secondary) }
            }
            .navigationTitle("InAppDebugKit")
            .sheet(isPresented: $showSheet) { SettingsSheet() }
        }
    }

    private func get(_ url: String) {
        URLSession.shared.dataTask(with: URL(string: url)!) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async { status = error.map { "Error: \($0.localizedDescription)" } ?? "\(code) \(url)" }
        }.resume()
    }

    private func post() {
        var request = URLRequest(url: URL(string: "https://jsonplaceholder.typicode.com/posts")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": "hello", "userId": 1])
        // A custom session (like Alamofire / Ktor create) is captured too.
        URLSession(configuration: .default).dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async { status = "\(code) POST → \(body.prefix(60))" }
        }.resume()
    }

    private func getWithAuth() {
        var request = URLRequest(url: URL(string: "https://httpbin.org/headers")!)
        request.setValue("Bearer super-secret-token", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async { status = "\(code) httpbin /headers" }
        }.resume()
    }

    private func logSocketEvents() {
        let url = "wss://echo.example.com/socket"
        InAppDebug.logSocket(.connect, name: "connected", url: url)
        InAppDebug.logSocket(.send, data: #"{"type":"join_room","data":{"room":42}}"#, url: url)
        InAppDebug.logSocket(.receive, data: #"{"event":{"name":"room_joined"},"data":{"room":42}}"#, url: url)
        InAppDebug.logSocket(.disconnect, name: "closed (1000)", url: url)
        status = "Logged 4 socket events"
    }

    private func crash() {
        let value: String? = nil
        print(value!)
    }
}

struct DetailView: View {
    var body: some View {
        Text("Detail screen").navigationTitle("Detail")
    }
}

struct SettingsSheet: View {
    var body: some View {
        Text("A sheet - logged as SettingsSheet").padding()
    }
}
