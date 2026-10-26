import SwiftUI
import WebKit

/// The small sign-in line on an app card.
struct AppSignInTag: View {
    @Environment(\.duovaTheme) private var theme
    let status: AppSignInStatus

    private var tint: Color {
        switch status {
        case .signedIn: theme.success
        case .mfaNeeded: DuovaPalette.amber
        case .failed: theme.danger
        default: theme.textSecondary
        }
    }

    var body: some View {
        if status != .unknown {
            HStack(spacing: 4) {
                if status == .checking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: status.symbol)
                }
                Text(status.title)
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Sign-in status and actions for one app, in its detail card: the saved
/// login (opened as its own card) and signing in yourself. Duova makes the
/// automatic tries by itself; there's nothing to retry here.
struct AppSignInSection: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(AppSignInCenter.self) private var center
    let service: Service
    let openSavedLogin: () -> Void

    @State private var showSheet = false

    private var status: AppSignInStatus { center.status(for: service.id) }
    private var support: AppLoginRecipe.Support? { center.recipe(for: service.id)?.support }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(support == .automatic ? "Automatic sign-in" : "Sign-in")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                AppSignInTag(status: status == .unknown ? .notSignedIn : status)
            }

            if support == .automatic {
                Button(action: openSavedLogin) {
                    Label("Saved Login", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
                .controlSize(.large)
                .morphSource("login.\(service.id.rawValue)")
            }

            if status == .mfaNeeded {
                ProminentActionButton(title: "Finish sign-in", isWorking: false) { showSheet = true }
            } else if support != .unavailable {
                Button { showSheet = true } label: {
                    Label("Sign in yourself", systemImage: "safari.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
                .foregroundStyle(theme.onAccent)
                .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
                .controlSize(.large)
            }

            if status == .signedIn {
                HStack {
                    Spacer()
                    Button("Sign out", role: .destructive) {
                        Task { await center.signOut(of: service.id) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                }
            }

            Text(footer)
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous))
        .pageSheet(isPresented: $showSheet) { AppSignInSheet(service: service) }
    }

    private var footer: String {
        switch support {
        case .automatic:
            String(localized: "Duova signs in with your saved login. Codes always come to you.")
        case .manual:
            String(localized: "Sign in yourself here. Duova keeps the session encrypted.")
        case .unavailable, nil:
            String(localized: "This app doesn't allow signing in inside Duova.")
        }
    }
}

/// The app's real login page, for finishing a code step or signing in by hand.
/// Closes by itself once the app is signed in.
struct AppSignInSheet: View {
    @Environment(\.closeSheet) private var closeSheet
    @Environment(\.duovaTheme) private var theme
    @Environment(AppSignInCenter.self) private var center
    let service: Service

    @State private var runner: WebLoginRunner?

    var body: some View {
        Group {
            if let runner {
                WebViewHost(webView: runner.webView)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    "Can't sign in here", systemImage: "nosign",
                    description: Text("\(service.name) doesn't allow signing in inside Duova."))
            }
        }
        .task {
            runner = center.beginInteractive(service.id)
            while !Task.isCancelled, runner != nil {
                try? await Task.sleep(for: .seconds(1.5))
                if await center.completeInteractive(service.id) {
                    closeSheet()
                    return
                }
            }
        }
        .onDisappear { center.endInteractive(service.id) }
    }
}

/// Shows an existing web view (which may have been loading off screen).
private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
