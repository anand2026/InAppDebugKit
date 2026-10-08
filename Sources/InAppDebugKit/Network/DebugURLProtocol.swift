//
//  DebugURLProtocol.swift
//  InAppDebugKit
//
//  Network capture. Every HTTP(S) request to a captured host is replayed through an internal
//  session so request/response/timing can be recorded.
//
//  Coverage:
//   - URLSession.shared                                    -> URLProtocol.registerClass
//   - any custom URLSession (Alamofire, Ktor Darwin, …)  -> swizzled URLSessionConfiguration.default
//  WebSocket frames are not HTTP; the app logs them with `InAppDebug.logSocket(...)`.
//

import Foundation

// MARK: - INSTALL
enum DebugNetworkCapture {
    static func install() {
        URLProtocol.registerClass(DebugURLProtocol.self)
        URLSessionConfiguration.debugSwizzleDefaultConfigurations()
    }

    static func shouldCapture(_ request: URLRequest) -> Bool {
        guard InAppDebug.isStarted,
              let url = request.url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        if InAppDebug.captureAllHosts { return true }
        return isCapturedHost(url.host ?? "", in: InAppDebug.configuration.capturedHosts)
    }

    /// `host` matches when it equals a configured host or is a subdomain of one. Empty list = all.
    static func isCapturedHost(_ host: String, in hosts: [String]) -> Bool {
        guard !hosts.isEmpty else { return true }
        let host = host.lowercased()
        return hosts.map { $0.lowercased() }.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

// MARK: - URL PROTOCOL
final class DebugURLProtocol: URLProtocol {

    fileprivate static let handledKey = "com.inappdebugkit.handled"

    private var dataTask: URLSessionDataTask?
    private var record: DebugApiRequest?
    private var receivedData = Data()
    private var response: URLResponse?
    private var isStopped = false
    private let stateLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool {
        guard property(forKey: handledKey, in: request) == nil else { return false }
        return DebugNetworkCapture.shouldCapture(request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

        /// Upload tasks and Ktor hand the body over as a stream; read it once so it can be both
        /// logged and sent.
        /// Order matters: setting `httpBodyStream` (even to nil) clears `httpBody`, so drop the
        /// stream first and then set the data.
        if mutable.httpBody == nil, let stream = mutable.httpBodyStream {
            let body = Self.readAll(stream)
            mutable.httpBodyStream = nil
            mutable.httpBody = body
        }

        let outgoing = mutable as URLRequest
        let url = outgoing.url
        let entry = DebugApiRequest(
            id: UUID(),
            url: url?.absoluteString.removingPercentEncoding ?? url?.absoluteString ?? "",
            method: outgoing.httpMethod ?? "GET",
            scheme: url?.scheme ?? "",
            host: url.map { u in u.port.map { "\(u.host ?? ""):\($0)" } ?? (u.host ?? "") } ?? "",
            path: url?.path ?? "",
            query: url?.query?.removingPercentEncoding,
            requestHeaders: DebugFormatter.redacted(outgoing.allHTTPHeaderFields ?? [:]),
            requestBody: DebugFormatter.bodyString(outgoing.httpBody, contentType: outgoing.value(forHTTPHeaderField: "Content-Type")),
            startedAt: Date(),
            curl: DebugFormatter.curl(for: outgoing, body: outgoing.httpBody, headers: DebugFormatter.redacted(outgoing.allHTTPHeaderFields ?? [:]))
        )
        record = entry
        DebugStore.shared.addApiRequest(entry)

        dataTask = DebugURLSessionRouter.shared.startTask(with: outgoing, for: self)
    }

    override func stopLoading() {
        stateLock.lock()
        isStopped = true
        stateLock.unlock()
        dataTask?.cancel()
    }

    private var stopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return isStopped
    }

    // MARK: ROUTER CALLBACKS
    fileprivate func didReceive(response: URLResponse) {
        self.response = response
        guard !stopped else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    fileprivate func didReceive(data: Data) {
        receivedData.append(data)
        guard !stopped else { return }
        client?.urlProtocol(self, didLoad: data)
    }

    fileprivate func didComplete(error: Error?) {
        if !stopped {
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        finishRecord(error: error)
    }

    private func finishRecord(error: Error?) {
        guard var entry = record else { return }
        let http = response as? HTTPURLResponse
        entry.status = http?.statusCode
        entry.responseHeaders = DebugFormatter.redacted(DebugFormatter.headers(http?.allHeaderFields))
        entry.responseBody = DebugFormatter.bodyString(receivedData, contentType: http?.value(forHTTPHeaderField: "Content-Type"))
        entry.responseSize = receivedData.count
        entry.duration = Date().timeIntervalSince(entry.startedAt)
        if let error {
            entry.error = (error as NSError).code == NSURLErrorCancelled ? "Cancelled" : error.localizedDescription
        }
        record = entry
        DebugStore.shared.updateApiRequest(entry)
    }

    private static func readAll(_ stream: InputStream) -> Data {
        var data = Data()
        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        stream.open()
        defer { stream.close() }
        /// Don't gate on `hasBytesAvailable`: Ktor's NSInputStream reports false until its producer
        /// has written, so the body read as empty. `read` blocks until data or EOF (0) / error (-1).
        while true {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - INTERNAL SESSION
/// One session for all intercepted requests; routes delegate callbacks back to the owning protocol.
private final class DebugURLSessionRouter: NSObject, URLSessionDataDelegate {

    static let shared = DebugURLSessionRouter()

    private let lock = NSLock()
    private var handlers: [Int: DebugURLProtocol] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = configuration.protocolClasses?.filter { ObjectIdentifier($0) != ObjectIdentifier(DebugURLProtocol.self) }
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let queue = OperationQueue()
        queue.name = "com.inappdebugkit.network"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    func startTask(with request: URLRequest, for handler: DebugURLProtocol) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        lock.lock()
        handlers[task.taskIdentifier] = handler
        lock.unlock()
        task.resume()
        return task
    }

    private func handler(for task: URLSessionTask, remove: Bool = false) -> DebugURLProtocol? {
        lock.lock(); defer { lock.unlock() }
        return remove ? handlers.removeValue(forKey: task.taskIdentifier) : handlers[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        handler(for: dataTask)?.didReceive(response: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handler(for: dataTask)?.didReceive(data: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handler(for: task, remove: true)?.didComplete(error: error)
    }
}

// MARK: - URLSessionConfiguration SWIZZLE
extension URLSessionConfiguration {

    private static var debugSwizzled = false

    /// Same trick netfox/Wormholy use: every configuration handed out by `.default` / `.ephemeral`
    /// gets the debug protocol first, so sessions we don't own (Ktor Darwin) are covered too.
    static func debugSwizzleDefaultConfigurations() {
        guard !debugSwizzled else { return }
        debugSwizzled = true
        exchange(NSSelectorFromString("defaultSessionConfiguration"), #selector(debug_defaultSessionConfiguration))
        exchange(NSSelectorFromString("ephemeralSessionConfiguration"), #selector(debug_ephemeralSessionConfiguration))
    }

    private static func exchange(_ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getClassMethod(URLSessionConfiguration.self, original),
              let replacementMethod = class_getClassMethod(URLSessionConfiguration.self, replacement) else {
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    /// After the exchange these call the original implementation.
    @objc dynamic private class func debug_defaultSessionConfiguration() -> URLSessionConfiguration {
        debug_defaultSessionConfiguration().debugInjectingProtocol()
    }

    @objc dynamic private class func debug_ephemeralSessionConfiguration() -> URLSessionConfiguration {
        debug_ephemeralSessionConfiguration().debugInjectingProtocol()
    }

    private func debugInjectingProtocol() -> URLSessionConfiguration {
        var classes = protocolClasses ?? []
        if !classes.contains(where: { ObjectIdentifier($0) == ObjectIdentifier(DebugURLProtocol.self) }) {
            classes.insert(DebugURLProtocol.self, at: 0)
        }
        protocolClasses = classes
        return self
    }
}
