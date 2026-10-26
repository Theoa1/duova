import SwiftUI

enum ProfileDestination: Hashable {
    case personalInformation
    case signInSecurity
    case sessions
    case appPreferences
    case service(ServiceID)
    case duoLayouts
    case appearance
    case storage
    case about
}

/// Duova's personal control center: who you are, how you sign in, and how the
/// app (and each service in it) behaves. Opening any page here never touches
/// the service workspace you were using.
struct ProfileView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(AuthController.self) private var auth

    @State private var path: [ProfileDestination] = []
    @State private var showEditProfile = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ScrollView {
                    content(wide: geo.size.width >= 700)
                        .padding(.horizontal, DuovaMetrics.screenMargin)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .background { DuovaBackdrop() }
            .navigationTitle("Profile")
            .navigationDestination(for: ProfileDestination.self) { destination in
                switch destination {
                case .personalInformation: PersonalInformationPage()
                case .signInSecurity: SignInSecurityPage()
                case .sessions: SessionsPage()
                case .appPreferences: AppPreferencesPage()
                case .service(let id): ServicePreferencesPage(service: ServiceCatalog.service(id))
                case .duoLayouts: DuoLayoutsPage()
                case .appearance: AppearanceGesturesPage()
                case .storage: StoragePage()
                case .about: AboutPage()
                }
            }
            .pageSheet(isPresented: $showEditProfile) { EditProfileView() }
            .preference(key: ProfileAtRootKey.self, value: path.isEmpty)
            .confirmationDialog("Sign out of Duova?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
            } message: {
                Text("You'll need your email and password to sign in again. Your settings and favorites stay saved, encrypted, on this device.")
            }
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(wide: Bool) -> some View {
        VStack(spacing: 24) {
            header
            if wide {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 24) {
                        accountSection
                        personalizationSection
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 24) {
                        yourSpaceSection
                        supportSection
                        signOutSection
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                accountSection
                personalizationSection
                yourSpaceSection
                supportSection
                signOutSection
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            if let account = auth.account {
                HStack(spacing: 16) {
                    AvatarView(initials: account.initials, image: auth.avatar, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                        Text(account.displayEmail)
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            Button {
                showEditProfile = true
            } label: {
                Text("Edit Profile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
            .controlSize(.large)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .duovaGlassCard()
    }

    // MARK: Sections

    private var accountSection: some View {
        SettingsGroup(title: "Account & Security") {
            SettingsLinkRow(symbol: "person.text.rectangle.fill", title: "Personal Information",
                            subtitle: "Name, email and profile image", value: ProfileDestination.personalInformation)
            SettingsLinkRow(symbol: auth.biometricKind.systemImage, title: "Sign-In & \(auth.biometricKind.title)",
                            subtitle: "Password and App Lock", value: ProfileDestination.signInSecurity)
            SettingsLinkRow(symbol: "iphone.gen3", title: "Devices & Sessions",
                            subtitle: "This device and active sessions", value: ProfileDestination.sessions)
        }
    }

    private var personalizationSection: some View {
        SettingsGroup(title: "Personalization") {
            SettingsLinkRow(symbol: "square.grid.2x2.fill", title: "App Preferences",
                            subtitle: "Defaults and individual app settings", value: ProfileDestination.appPreferences)
            SettingsLinkRow(symbol: "rectangle.split.2x1.fill", title: "Duo Layouts",
                            subtitle: "Default panes, ratios and configurations", value: ProfileDestination.duoLayouts)
            SettingsLinkRow(symbol: "paintpalette.fill", title: "Appearance & Gestures",
                            subtitle: "Theme, motion and interaction", value: ProfileDestination.appearance)
        }
    }

    private var yourSpaceSection: some View {
        SettingsGroup(title: "Your Space") {
            SettingsLinkRow(symbol: "internaldrive.fill", title: "Storage & Cache",
                            subtitle: "Device storage and temporary data", value: ProfileDestination.storage)
        }
    }

    private var supportSection: some View {
        SettingsGroup(title: "Support") {
            SettingsLinkRow(symbol: "info.circle.fill", title: "About Duova",
                            subtitle: "Version, data protection and disclosures", value: ProfileDestination.about)
        }
    }

    private var signOutSection: some View {
        SettingsGroup {
            SettingsButtonRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign Out",
                              isDestructive: true) {
                confirmSignOut = true
            }
        }
    }
}

