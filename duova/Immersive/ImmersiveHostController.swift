import SwiftUI
import UIKit
import WebKit

/// Stable web surfaces with native controls and a reversible workspace dismissal.
@MainActor
final class ImmersiveHostController: UIViewController {
    let coordinator: ImmersiveCoordinator

    var onSuspend: () -> Bool = { false }
    private lazy var navigation = UIHostingController(rootView: InstagramNavigationBar(coordinator: coordinator))
    private lazy var companionNavigation = UIHostingController(rootView: CompanionNavigation(coordinator: coordinator))
    private lazy var status = UIHostingController(rootView: ImmersiveStatusView(coordinator: coordinator))
    private let companionPlaceholder = UILabel()
    private var lastInput: PostureInput?
    private var dismissalSnapshot: UIView?
    private var hiddenForDismissal: [UIView] = []
    private var dismissalOrigin = CGPoint.zero
    private var dismissalDistance: CGFloat = 0
    private var finishingDismissal = false
    private var hinge: HingeState = .unknown
    private var hingeInteraction: UIInteraction?
    private(set) var layout: PostureLayout?
    private weak var observedScene: UIWindowScene?
    private var isVisible = false

    #if DEBUG
    /// `--posture=book` (etc.) in the scheme forces one layout for testing.
    static let debugOverride: SocialPosture? = {
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--posture=") }) else { return nil }
        return SocialPosture(rawValue: String(arg.dropFirst("--posture=".count)))
    }()
    #endif

    init(coordinator: ImmersiveCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [] }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        attach(coordinator.primary.webView)
        install(navigation)
        install(companionNavigation)
        install(status)
        status.view.isHidden = coordinator.phase == .ready
        companionPlaceholder.text = "Choose content above, or tap comments on a post or Reel."
        companionPlaceholder.font = .preferredFont(forTextStyle: .subheadline)
        companionPlaceholder.adjustsFontForContentSizeCategory = true
        companionPlaceholder.textColor = .secondaryLabel
        companionPlaceholder.numberOfLines = 0
        companionPlaceholder.textAlignment = .center
        view.insertSubview(companionPlaceholder, at: 0)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleDismissal(_:)))
        hold.numberOfTouchesRequired = 3
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 20
        view.addGestureRecognizer(hold)
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Return to Splitter", target: self, selector: #selector(accessibleDismiss))
        ]

        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] _, update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let state: HingeState
                    switch update.hinge?.status {
                    case .closed: state = .closed
                    case .partiallyOpen: state = .partiallyOpen
                    case .fullyOpen: state = .fullyOpen
                    default: state = .unknown
                    }
                    self.hinge = state
                    // A changing angle can move reserved regions without changing
                    // the coarse status. Requery the region on every layout pass.
                    self.view.setNeedsLayout()
                }
            }
            view.addInteraction(interaction)
            hingeInteraction = interaction
        }
        coordinator.setSceneActive(false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        observeOwningScene()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        coordinator.setSceneActive(false)
        coordinator.primary.setContentVisible(false)
        coordinator.companion?.setContentVisible(false)
        cancelDismissal()
        stopObservingScene()
    }

    private func observeOwningScene() {
        guard isVisible else { return }
        let scene = view.window?.windowScene
        guard scene !== observedScene else { return }
        stopObservingScene()
        observedScene = scene
        guard let scene else {
            coordinator.setSceneActive(false)
            return
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sceneActivated(_:)),
                           name: UIScene.didActivateNotification, object: scene)
        center.addObserver(self, selector: #selector(sceneDeactivated(_:)),
                           name: UIScene.willDeactivateNotification, object: scene)
        center.addObserver(self, selector: #selector(sceneDeactivated(_:)),
                           name: UIScene.didEnterBackgroundNotification, object: scene)
        coordinator.setSceneActive(scene.activationState == .foregroundActive)
    }

    private func stopObservingScene() {
        guard let observedScene else { return }
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIScene.didEnterBackgroundNotification] {
            NotificationCenter.default.removeObserver(self, name: name, object: observedScene)
        }
        self.observedScene = nil
    }

    @objc private func sceneActivated(_ notification: Notification) {
        guard notification.object as? UIWindowScene === observedScene else { return }
        coordinator.setSceneActive(isVisible)
    }

    @objc private func sceneDeactivated(_ notification: Notification) {
        guard notification.object as? UIWindowScene === observedScene else { return }
        coordinator.setSceneActive(false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        observeOwningScene()
        applyLayout()
    }

    /// Positions the same web views; never creates or reloads one.
    private func applyLayout() {
        guard dismissalSnapshot == nil, !finishingDismissal else { return }
        var input = PostureInput(size: view.bounds.size)
        let insets = view.safeAreaInsets
        input.safeTop = insets.top
        input.safeLeading = insets.left
        input.safeBottom = insets.bottom
        input.safeTrailing = insets.right
        input.hinge = hinge
        input.accessibilityLayout = view.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if #available(iOS 27.1, *) {
            input.divisionRegion = view.reservedRegions(kind: .division)
                .filter { $0.isActive && $0.frame.intersects(view.bounds) }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.frame
        }
        input.layout = coordinator.expandedLayout
        input.ratio = coordinator.splitRatio
        input.companionWanted = true
        #if DEBUG
        input.override = Self.debugOverride
        #endif

        // UIKit may request layout repeatedly while WebKit scrolls. Only geometry
        // or an explicit companion change is allowed to write web-view frames.
        guard lastInput != input else { return }
        lastInput = input
        let resolved = SocialPostureResolver.resolve(input)
        layout = resolved
        if coordinator.currentPosture != resolved.posture {
            coordinator.currentPosture = resolved.posture
        }
        coordinator.companionAvailable = resolved.canShowCompanion

        let safe = view.bounds.inset(by: insets)
        let primaryFrame = resolved.primary
        let controlsFrame = primaryFrame.intersection(safe)
        let barHeight: CGFloat = 64
        let barWidth = min(360, max(0, controlsFrame.width - 16))
        navigation.view.frame = CGRect(x: controlsFrame.midX - barWidth / 2,
                                       y: controlsFrame.maxY - barHeight,
                                       width: barWidth, height: barHeight)
        let pageFrame = CGRect(x: primaryFrame.minX, y: primaryFrame.minY,
                               width: max(0, primaryFrame.width),
                               height: max(0, primaryFrame.height))
        let primary = coordinator.primary
        if primary.webView.frame != pageFrame { primary.webView.frame = pageFrame }
        primary.layoutWidth = pageFrame.width
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: insets.bottom + barHeight + 4, right: 0)
        if primary.webView.scrollView.contentInset != contentInsets {
            primary.webView.scrollView.contentInset = contentInsets
        }
        primary.setContentVisible(isVisible && view.window?.windowScene?.activationState == .foregroundActive)
        coordinator.paneDidBecomeVisible(primary)

        companionNavigation.view.isHidden = resolved.companion == nil
        companionPlaceholder.isHidden = resolved.companion == nil || coordinator.companionStatus == nil
        companionPlaceholder.text = coordinator.companionStatus
        if let frame = resolved.companion {
            let contained = frame.intersection(safe)
            companionNavigation.view.frame = CGRect(x: contained.minX, y: contained.minY,
                                                    width: contained.width, height: 52)
            let content = frame
            companionPlaceholder.frame = content.insetBy(dx: 24, dy: 20)
            if let companion = coordinator.companion {
                if companion.webView.superview !== view { attach(companion.webView) }
                companion.webView.isHidden = false
                companion.setContentVisible(isVisible && coordinator.companionKind != .comments &&
                    view.window?.windowScene?.activationState == .foregroundActive)
                if companion.webView.frame != content { companion.webView.frame = content }
                companion.layoutWidth = content.width
                let companionInsets = UIEdgeInsets(top: insets.top + 56, left: 0, bottom: insets.bottom, right: 0)
                if companion.webView.scrollView.contentInset != companionInsets {
                    companion.webView.scrollView.contentInset = companionInsets
                }
                coordinator.paneDidBecomeVisible(companion)
            }
        } else {
            coordinator.companion?.webView.isHidden = true
            coordinator.companion?.setContentVisible(false)
        }
        view.bringSubviewToFront(companionPlaceholder)
        view.bringSubviewToFront(navigation.view)
        view.bringSubviewToFront(companionNavigation.view)
        status.view.frame = view.bounds
        view.bringSubviewToFront(status.view)
        // The first navigation must see real pane dimensions, not a zero-sized web view.
        if view.bounds.width > 0 && view.bounds.height > 0 { coordinator.start() }
    }

    private func attach(_ webView: WKWebView) {
        webView.clipsToBounds = true
        webView.layer.cornerRadius = 0
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.autoresizingMask = []
        webView.translatesAutoresizingMaskIntoConstraints = true
        view.insertSubview(webView, at: 0)
    }

    /// Re-run layout when the companion gains or loses content.
    func companionDidChange() {
        if dismissalSnapshot == nil { status.view.isHidden = coordinator.phase == .ready }
        lastInput = nil
        view.setNeedsLayout()
    }
    private func install<Content: View>(_ controller: UIHostingController<Content>) {
        addChild(controller)
        controller.view.backgroundColor = .clear
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    @objc private func accessibleDismiss() -> Bool {
        finishDismissal()
        return true
    }

    @objc private func handleDismissal(_ gesture: UILongPressGestureRecognizer) {
        guard !finishingDismissal else { return }
        switch gesture.state {
        case .began:
            guard gesture.numberOfTouches == 3,
                  let snapshot = view.snapshotView(afterScreenUpdates: false) else { return }
            dismissalOrigin = gesture.location(in: view)
            dismissalDistance = 0
            snapshot.frame = view.bounds
            snapshot.isUserInteractionEnabled = false
            snapshot.layer.cornerRadius = 24
            snapshot.clipsToBounds = true
            hiddenForDismissal = view.subviews.filter { !$0.isHidden }
            hiddenForDismissal.forEach { $0.isHidden = true }
            dismissalSnapshot = snapshot
            view.addSubview(snapshot)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if !UIAccessibility.isReduceMotionEnabled {
                UIView.animate(withDuration: 0.18) { snapshot.transform = CGAffineTransform(scaleX: 0.96, y: 0.96) }
            }
        case .changed:
            guard let snapshot = dismissalSnapshot else { return }
            dismissalDistance = max(0, gesture.location(in: view).y - dismissalOrigin.y)
            if !UIAccessibility.isReduceMotionEnabled {
                snapshot.transform = CGAffineTransform(translationX: 0, y: dismissalDistance)
                    .scaledBy(x: 0.96, y: 0.96)
            }
        case .ended:
            if dismissalSnapshot != nil && dismissalDistance >= min(140, view.bounds.height * 0.2) {
                finishDismissal()
            } else { cancelDismissal() }
        case .cancelled, .failed: cancelDismissal()
        default: break
        }
    }

    private func finishDismissal() {
        guard !finishingDismissal else { return }
        finishingDismissal = true
        Task { [weak self] in
            guard let self else { return }
            await coordinator.captureCheckpoint()
            guard isVisible else { finishingDismissal = false; cancelDismissal(); return }
            let finish = { [weak self] in
                guard let self else { return }
                if !onSuspend() {
                    finishingDismissal = false
                    cancelDismissal()
                    let alert = UIAlertController(title: "Couldn’t preserve workspace",
                        message: "Please try again. Your current page is still open.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                }
            }
            guard let snapshot = dismissalSnapshot, !UIAccessibility.isReduceMotionEnabled else { finish(); return }
            UIView.animate(withDuration: 0.22, animations: {
                snapshot.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                    .scaledBy(x: 0.9, y: 0.9)
            }, completion: { _ in finish() })
        }
    }

    private func cancelDismissal() {
        guard let snapshot = dismissalSnapshot else { return }
        dismissalSnapshot = nil
        hiddenForDismissal.forEach { $0.isHidden = false }
        hiddenForDismissal.removeAll()
        status.view.isHidden = coordinator.phase == .ready
        lastInput = nil
        view.setNeedsLayout()
        if UIAccessibility.isReduceMotionEnabled { snapshot.removeFromSuperview(); return }
        UIView.animate(withDuration: 0.18, animations: { snapshot.transform = .identity },
                       completion: { _ in snapshot.removeFromSuperview() })
    }
}
