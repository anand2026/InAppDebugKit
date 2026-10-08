//
//  DebugBubble.swift
//  InAppDebugKit
//
//  Floating, draggable bubble that opens the debug tools. Lives in its own small UIWindow so it
//  survives root-view-controller swaps and shows above sheets / full-screen covers.
//
//  Tap        -> Debug Tools home
//  Long press -> quick actions (last request, clear logs, hide bubble)
//  Flashes green / red on every finished API call; turns red with "!" after a crash.
//

import UIKit
import Combine

// MARK: - MANAGER
final class DebugBubbleManager {

    static let shared = DebugBubbleManager()

    private var window: DebugBubbleWindow?
    private var isTemporarilyHidden = false

    func attach(to scene: UIWindowScene) {
        guard window == nil else { return }
        let bubbleWindow = DebugBubbleWindow(windowScene: scene)
        window = bubbleWindow
        updateVisibility()
    }

    func setHidden(_ hidden: Bool) {
        DispatchQueue.main.async { self.updateVisibility() }
    }

    /// Hidden while the Debug Tools screen itself is on screen.
    func setTemporarilyHidden(_ hidden: Bool) {
        isTemporarilyHidden = hidden
        updateVisibility()
    }

    private func updateVisibility() {
        window?.isHidden = InAppDebug.isBubbleHidden || isTemporarilyHidden
    }
}

// MARK: - WINDOW
final class DebugBubbleWindow: UIWindow {

    private static let size: CGFloat = 56
    private static let positionKey = "debugtools.bubblePosition"

    private let bubbleView = DebugBubbleView()
    private var dragOffset: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        backgroundColor = .clear

        let controller = DebugBubbleRootController()
        rootViewController = controller
        controller.view.addSubview(bubbleView)
        bubbleView.frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)

        frame = initialFrame(in: windowScene.screen.bounds)
        setupGestures()
        bind()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Never steal key status from the app window.
    override var canBecomeKey: Bool { false }

    // MARK: POSITION
    private func initialFrame(in screen: CGRect) -> CGRect {
        let size = Self.size
        if let saved = UserDefaults.standard.string(forKey: Self.positionKey) {
            let point = NSCoder.cgPoint(for: saved)
            return CGRect(x: point.x, y: point.y, width: size, height: size)
        }
        return CGRect(x: screen.width - size - 8, y: screen.height * 0.6, width: size, height: size)
    }

    private func snapToEdge() {
        guard let screen = windowScene?.screen.bounds else { return }
        let insets = windowScene?.windows.first(where: { !($0 is DebugBubbleWindow) })?.safeAreaInsets ?? .zero
        let size = Self.size
        let x = frame.midX < screen.midX ? 8 : screen.width - size - 8
        let minY = insets.top + 8
        let maxY = screen.height - insets.bottom - size - 8
        let y = min(max(frame.minY, minY), maxY)
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.frame.origin = CGPoint(x: x, y: y)
        }
        UserDefaults.standard.set(NSCoder.string(for: CGPoint(x: x, y: y)), forKey: Self.positionKey)
    }

    // MARK: GESTURES
    private func setupGestures() {
        bubbleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap)))
        bubbleView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(onPan(_:))))
        bubbleView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:))))
    }

    @objc private func onTap() {
        InAppDebug.present(DebugStore.shared.unseenCrashCount > 0 ? .crashes : .home)
    }

    @objc private func onPan(_ gesture: UIPanGestureRecognizer) {
        guard let screenSpace = windowScene?.screen.coordinateSpace else { return }
        /// The window itself moves, so track the finger in screen coordinates.
        let finger = convert(gesture.location(in: self), to: screenSpace)
        switch gesture.state {
        case .began:
            dragOffset = CGPoint(x: finger.x - frame.origin.x, y: finger.y - frame.origin.y)
        case .changed:
            frame.origin = CGPoint(x: finger.x - dragOffset.x, y: finger.y - dragOffset.y)
        default:
            snapToEdge()
        }
    }

    @objc private func onLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let top = UIApplication.debugTopViewController() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let sheet = UIAlertController(title: InAppDebug.configuration.title, message: lastRequestLine, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "API Requests", style: .default) { _ in InAppDebug.present(.apiRequests) })
        sheet.addAction(UIAlertAction(title: "Socket Events", style: .default) { _ in InAppDebug.present(.sockets) })
        sheet.addAction(UIAlertAction(title: "Clear logs", style: .destructive) { _ in
            DebugStore.shared.clearApiRequests()
            DebugStore.shared.clearSocketEvents()
            DebugStore.shared.clearScreens()
        })
        sheet.addAction(UIAlertAction(title: "Hide bubble", style: .default) { _ in InAppDebug.isBubbleHidden = true })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(sheet, animated: true)
    }

    private var lastRequestLine: String? {
        DebugStore.shared.apiRequests.first.map { "Last: \($0.summaryLine)" }
    }

    // MARK: STORE BINDING
    private func bind() {
        let store = DebugStore.shared
        store.$apiRequests
            .combineLatest(store.$crashes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests, crashes in
                self?.bubbleView.update(count: requests.count, hasCrash: crashes.contains { !$0.isViewed })
            }
            .store(in: &cancellables)

        store.apiFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                self?.bubbleView.flash(success: !request.isFailure)
            }
            .store(in: &cancellables)
    }
}

// MARK: - ROOT CONTROLLER
private final class DebugBubbleRootController: UIViewController {
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }
}

// MARK: - BUBBLE VIEW
private final class DebugBubbleView: UIView {

    private let iconLabel = UILabel()
    private let countLabel = UILabel()
    private let crashBadge = UILabel()
    private var hasCrash = false

    private var restingColor: UIColor {
        hasCrash ? .systemRed : UIColor(white: 0.12, alpha: 0.9)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 28
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        backgroundColor = restingColor
        accessibilityLabel = "Debug tools"

        iconLabel.text = "🐞"
        iconLabel.font = .systemFont(ofSize: 18)
        iconLabel.textAlignment = .center

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.adjustsFontSizeToFitWidth = true

        crashBadge.text = "!"
        crashBadge.font = .systemFont(ofSize: 12, weight: .heavy)
        crashBadge.textColor = .systemRed
        crashBadge.backgroundColor = .white
        crashBadge.textAlignment = .center
        crashBadge.layer.cornerRadius = 9
        crashBadge.clipsToBounds = true
        crashBadge.isHidden = true

        [iconLabel, countLabel, crashBadge].forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconLabel.frame = CGRect(x: 0, y: 8, width: bounds.width, height: 22)
        countLabel.frame = CGRect(x: 6, y: 30, width: bounds.width - 12, height: 14)
        crashBadge.frame = CGRect(x: bounds.width - 18, y: -2, width: 18, height: 18)
    }

    func update(count: Int, hasCrash: Bool) {
        self.hasCrash = hasCrash
        countLabel.text = count > 999 ? "999+" : "\(count)"
        crashBadge.isHidden = !hasCrash
        backgroundColor = restingColor
    }

    func flash(success: Bool) {
        layer.removeAllAnimations()
        backgroundColor = success ? .systemGreen : .systemRed
        UIView.animate(withDuration: 0.6, delay: 0.25, options: [.allowUserInteraction]) {
            self.backgroundColor = self.restingColor
        }
    }
}
