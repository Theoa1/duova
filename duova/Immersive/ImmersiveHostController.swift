import UIKit
import WebKit

/// Owns the window while a service is launched. It positions the service's
/// primary and companion web views for whichever of the seven layouts the
/// current geometry calls for, and draws nothing of its own except a hairline
/// between two flat panes. No header, no close control, no switcher.
@MainActor
final class ImmersiveHostController: UIViewController {
    let coordinator: ImmersiveCoordinator

    private let separator = UIView()
    private var hinge: HingeState = .unknown
    private var hingeInteraction: UIInteraction?
    private(set) var layout: PostureLayout?
    private var companionAttached = false

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
        separator.backgroundColor = .separator
        separator.isHidden = true

        attach(coordinator.primary.webView)
        view.addSubview(separator)

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
                    if state != self.hinge {
                        self.hinge = state
                        self.view.setNeedsLayout()
                    }
                }
            }
            view.addInteraction(interaction)
            hingeInteraction = interaction
        }
        coordinator.start()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyLayout()
    }

    /// Positions the same web views; never creates or reloads one.
    private func applyLayout() {
        var input = PostureInput(size: view.bounds.size)
        let insets = view.safeAreaInsets
        input.safeTop = insets.top
        input.safeLeading = insets.left
        input.safeBottom = insets.bottom
        input.safeTrailing = insets.right
        input.hinge = hinge
        input.layout = coordinator.expandedLayout
        input.ratio = coordinator.splitRatio
        input.companionWanted = coordinator.companionWanted
        #if DEBUG
        input.override = Self.debugOverride
        #endif

        let resolved = SocialPostureResolver.resolve(input)
        layout = resolved
        coordinator.currentPosture = resolved.posture
        coordinator.companionAvailable = resolved.canShowCompanion

        let primary = coordinator.primary
        primary.webView.frame = resolved.primary
        primary.layoutWidth = resolved.primary.width

        if let companionFrame = resolved.companion, let companion = coordinator.companion {
            if !companionAttached {
                attach(companion.webView)
                companionAttached = true
                view.bringSubviewToFront(separator)
            }
            companion.webView.isHidden = false
            companion.webView.frame = companionFrame
            companion.layoutWidth = companionFrame.width
            // A hairline only on a flat display; a fold needs no drawn divider.
            let showsHairline = resolved.foldGap == nil
            separator.isHidden = !showsHairline
            if showsHairline {
                separator.frame = resolved.isVerticalSplit
                    ? CGRect(x: 0, y: resolved.primary.maxY, width: view.bounds.width, height: SocialPostureResolver.gutter)
                    : CGRect(x: resolved.primary.maxX, y: 0, width: SocialPostureResolver.gutter, height: view.bounds.height)
            }
        } else {
            // Suspended, not discarded: it keeps its page, history and scroll.
            coordinator.companion?.webView.isHidden = true
            separator.isHidden = true
        }
    }

    private func attach(_ webView: WKWebView) {
        webView.autoresizingMask = []
        webView.translatesAutoresizingMaskIntoConstraints = true
        view.insertSubview(webView, at: 0)
    }

    /// Re-run layout when the companion gains or loses content.
    func companionDidChange() {
        view.setNeedsLayout()
    }
}
