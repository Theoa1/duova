import SwiftUI

/// The twelve-digit code, large, as both devices show it.
private struct SafetyCodeView: View {
    @Environment(\.duovaTheme) private var theme
    let code: String

    var body: some View {
        Text(code)
            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous))
            .accessibilityLabel(Text("Code \(code)"))
    }
}

/// On a new device: wait for a device that has the keys to approve this one.
struct DeviceLinkView: View {
    @Environment(\.closeSheet) private var closeSheet
    @Environment(\.duovaTheme) private var theme
    @Environment(DeviceKeyring.self) private var keyring

    @State private var confirmStartOver = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        SettingsPage(title: "Approve This Device", showsTitle: true) {
            switch keyring.state {
            case .waitingForApproval(let code):
                Text("Your encrypted data opens only on devices you approve.")
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SafetyCodeView(code: code)
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for approval…")
                        .foregroundStyle(theme.textSecondary)
                }
                .font(.subheadline)
                SettingsGroup(
                    title: "On your other device",
                    footer: "Open Duova there and approve this device. Approve only if the codes match."
                ) {
                    SettingsValueRow(title: "1", value: String(localized: "Open Duova"))
                    SettingsValueRow(title: "2", value: String(localized: "Tap Approve"))
                    SettingsValueRow(title: "3", value: String(localized: "Check the code matches"))
                }
            case .ready:
                FormMessage(text: String(localized: "Device approved. Data unlocked."), kind: .success)
            case .offline:
                FormMessage(text: String(localized: "No connection. Try again."), kind: .error)
            default:
                ProgressView()
            }

            if let message { FormMessage(text: message, kind: .error) }

            if case .waitingForApproval = keyring.state {
                SettingsGroup(
                    footer: "Only if no device with your data is left. Synced settings, saved logins and your synced name are erased."
                ) {
                    SettingsButtonRow(symbol: "arrow.counterclockwise", title: "Lost Your Other Devices?", isDestructive: true) {
                        confirmStartOver = true
                    }
                }
            }
        }
        .confirmationDialog("Start over on this device?", isPresented: $confirmStartOver, titleVisibility: .visible) {
            Button("Erase & Start Over", role: .destructive) { startOver() }
        } message: {
            Text("Data sealed by your other devices is erased for good. This can't be undone.")
        }
        .onChange(of: keyring.state) { _, state in
            if state == .ready {
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    closeSheet()
                }
            }
        }
    }

    private func startOver() {
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do {
                try await keyring.startOver()
            } catch let error as AuthError {
                message = error.errorDescription
            } catch {
                message = String(localized: "Something went wrong. Try again.")
            }
        }
    }
}

/// On a device with the keys: approve (or refuse) a new one.
struct DeviceApprovalView: View {
    @Environment(\.closeSheet) private var closeSheet
    @Environment(\.duovaTheme) private var theme
    @Environment(DeviceKeyring.self) private var keyring
    let device: LinkedDevice

    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        SettingsPage(title: "New Device", showsTitle: true) {
            Text("A device signed in to your account wants your encrypted data.")
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            SafetyCodeView(code: device.safetyCode)
            FormMessage(text: String(localized: "Approve only if the codes match."), kind: .info)
            if let message { FormMessage(text: message, kind: .error) }
            ProminentActionButton(title: "Approve", isWorking: isWorking, action: approve)
            SettingsGroup(footer: "Not yours? Remove it, then change your password.") {
                SettingsButtonRow(symbol: "xmark.shield.fill", title: "Not Mine. Remove It", isDestructive: true) {
                    remove()
                }
            }
        }
        .pageSheetCloseDisabled(isWorking)
    }

    private func approve() {
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            switch await BiometricAuthenticator.authenticate(reason: String(localized: "Approve the new device.")) {
            case .success:
                do {
                    try await keyring.approve(device)
                    closeSheet()
                } catch let error as AuthError {
                    message = error.errorDescription
                } catch {
                    message = String(localized: "Couldn't approve. Try again.")
                }
            case .cancelled:
                break
            case .unavailable:
                message = String(localized: "Set a device passcode first.")
            case .failed(let reason):
                message = reason
            }
        }
    }

    private func remove() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await keyring.remove(device)
                closeSheet()
            } catch {
                message = String(localized: "Couldn't remove. Try again.")
            }
        }
    }
}

/// Profile → Sign-In & Security: every device on the account.
struct DevicesGroup: View {
    @Environment(DeviceKeyring.self) private var keyring
    @State private var approving: LinkedDevice?
    @State private var removing: LinkedDevice?
    @State private var showLink = false

    var body: some View {
        SettingsGroup(
            title: "Devices",
            footer: "A device opens your encrypted data only after you approve it with matching codes. Removing one stops new approvals; to lock out a lost device, use Start Over."
        ) {
            if case .waitingForApproval(let code) = keyring.state {
                SettingsButtonRow(symbol: "lock.shield.fill", title: "Approve This Device", subtitle: "Code \(code)") {
                    showLink = true
                }
            }
            ForEach(keyring.devices) { device in
                if !device.hasAccess && !device.isThisDevice {
                    SettingsButtonRow(symbol: "lock.shield.fill", title: "Approve \(device.label)", subtitle: "Code \(device.safetyCode)") {
                        approving = device
                    }
                } else {
                    SettingsButtonRow(
                        symbol: device.label.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone",
                        title: device.isThisDevice ? "\(device.label) (this device)" : "\(device.label)",
                        subtitle: device.addedAt.map { "Added \($0.formatted(date: .abbreviated, time: .omitted))" }
                    ) {
                        if !device.isThisDevice { removing = device }
                    }
                }
            }
        }
        .task { await keyring.refreshDevices() }
        .pageSheet(item: $approving) { DeviceApprovalView(device: $0) }
        .pageSheet(isPresented: $showLink) { DeviceLinkView() }
        .confirmationDialog(
            "Remove \(removing?.label ?? "")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let device = removing { Task { try? await keyring.remove(device) } }
            }
        } message: {
            Text("It can't be approved again without a new request.")
        }
    }
}
