import PhotosUI
import SwiftUI

/// Edit name, email and profile photo. Changing the email asks for the account
/// password, because the email is part of how you sign in.
struct EditProfileView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.closeSheet) private var closeSheet
    @Environment(AuthController.self) private var auth

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingPhoto: Data?
    @State private var pendingPreview: UIImage?
    @State private var removePhoto = false
    @State private var message: String?
    @State private var isSaving = false
    @State private var didLoad = false

    private var account: DuovaAccount? { auth.account }
    private var emailChanged: Bool {
        EmailNormalizer.normalize(email) != (account?.email ?? "")
    }
    private var nameChanged: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != (account?.name ?? "")
    }
    private var photoChanged: Bool { pendingPhoto != nil || removePhoto }
    private var hasChanges: Bool { emailChanged || nameChanged || photoChanged }
    private var canSave: Bool {
        guard hasChanges, !isSaving else { return false }
        if emailChanged { return EmailNormalizer.isValid(EmailNormalizer.normalize(email)) && !password.isEmpty }
        return true
    }

    private var displayedPhoto: UIImage? {
        if removePhoto { return nil }
        return pendingPreview ?? auth.avatar
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Edit Profile") {
                photoSection

                SettingsGroup(title: "Name") {
                    FormFieldRow(symbol: "person.fill") {
                        TextField("Full name", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                    }
                }

                if auth.accountHasPassword {
                    SettingsGroup(
                        title: "Email",
                        footer: emailChanged
                            ? "Enter your current password to confirm the new email. You'll use the new email to sign in."
                            : "This is the email you sign in with."
                    ) {
                        FormFieldRow(symbol: "envelope.fill") {
                            TextField("Email", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        if emailChanged {
                            FormFieldRow(symbol: "lock.fill") {
                                SecureField("Current password", text: $password)
                                    .textContentType(.password)
                            }
                        }
                    }
                } else if let account {
                    SettingsGroup(
                        title: "Email",
                        footer: "This account signs in without a password, so its email can't be changed here."
                    ) {
                        SettingsValueRow(title: "Email", value: account.displayEmail)
                    }
                }

                if let message {
                    FormMessage(text: message, kind: .error)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeSheet() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .onAppear {
            guard !didLoad, let account else { return }
            didLoad = true
            name = account.name
            email = account.email
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onChange(of: email) { _, _ in message = nil }
    }

    // MARK: Photo

    private var photoSection: some View {
        VStack(spacing: 14) {
            AvatarView(initials: account?.initials ?? "D", image: displayedPhoto, size: 112)
                .overlay { photoStatus }
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(displayedPhoto == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo.on.rectangle")
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))

                if displayedPhoto != nil {
                    Button(role: .destructive) {
                        pendingPhoto = nil
                        pendingPreview = nil
                        pickerItem = nil
                        removePhoto = true
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .frame(minHeight: 44)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.roundedRectangle(radius: DuovaMetrics.cornerRadius))
                }
            }
            Text("A photo is optional. Without one, Duova shows your initials.")
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var photoStatus: some View {
        if pickerItem != nil && pendingPreview == nil && !removePhoto {
            RoundedRectangle(cornerRadius: DuovaMetrics.cornerRadius, style: .continuous).fill(.black.opacity(0.35))
                .overlay { ProgressView().tint(.white) }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = AvatarProcessor.prepare(data),
              let image = UIImage(data: prepared)
        else {
            message = String(localized: "That photo couldn't be loaded. Choose a different one.")
            pickerItem = nil
            return
        }
        pendingPhoto = prepared
        pendingPreview = image
        removePhoto = false
    }

    // MARK: Save

    private func save() {
        guard canSave else { return }
        isSaving = true
        message = nil
        Task {
            defer { isSaving = false }
            do {
                if nameChanged { try auth.updateName(name) }
                if emailChanged { try await auth.changeEmail(to: email, password: password) }
                if let pendingPhoto {
                    try auth.setAvatar(pendingPhoto)
                } else if removePhoto {
                    try auth.setAvatar(nil)
                }
                closeSheet()
            } catch let error as AuthError {
                message = error.errorDescription
            } catch {
                message = String(localized: "Something went wrong. Try again.")
            }
        }
    }
}

/// Change the account password. Requires the current one.
struct ChangePasswordView: View {
    @Environment(\.closeSheet) private var closeSheet
    @Environment(AuthController.self) private var auth

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var message: String?
    @State private var isSaving = false

    private var mismatch: Bool { !confirm.isEmpty && confirm != new }
    private var canSave: Bool {
        !current.isEmpty && new.count >= PasswordPolicy.minimumLength && confirm == new && !isSaving
    }

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Change Password") {
                SettingsGroup(title: "Current password") {
                    FormFieldRow(symbol: "lock.fill") {
                        SecureField("Current password", text: $current)
                            .textContentType(.password)
                    }
                }
                SettingsGroup(
                    title: "New password",
                    footer: "Use at least \(PasswordPolicy.minimumLength) characters. Your password is never stored, only a salted one-way hash."
                ) {
                    FormFieldRow(symbol: "lock.rotation") {
                        SecureField("New password", text: $new)
                            .textContentType(.newPassword)
                    }
                    FormFieldRow(symbol: "checkmark.shield.fill") {
                        SecureField("Confirm new password", text: $confirm)
                            .textContentType(.newPassword)
                    }
                }
                if mismatch {
                    FormMessage(text: String(localized: "The new passwords don't match."), kind: .error)
                }
                if let message {
                    FormMessage(text: message, kind: .error)
                }
                ProminentActionButton(title: "Update Password", isWorking: isSaving, action: save)
                    .disabled(!canSave)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeSheet() }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        message = nil
        Task {
            defer { isSaving = false }
            do {
                try await auth.changePassword(current: current, new: new)
                closeSheet()
            } catch let error as AuthError {
                message = error.errorDescription
            } catch {
                message = String(localized: "Something went wrong. Try again.")
            }
        }
    }
}

/// Permanently deletes the Duova account and all data stored for it on this device.
struct DeleteAccountView: View {
    @Environment(\.duovaTheme) private var theme
    @Environment(\.closeSheet) private var closeSheet
    @Environment(AuthController.self) private var auth

    @State private var password = ""
    @State private var message: String?
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Delete Account") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("This can't be undone", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(theme.danger)
                    Text("Deleting your Duova account permanently erases your profile, photo, favorites, preferences and sign-in details from this device. It doesn't delete your accounts on other services.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .duovaGlassCard()

                if auth.accountHasPassword {
                    SettingsGroup(title: "Confirm with your password") {
                        FormFieldRow(symbol: "lock.fill") {
                            SecureField("Account password", text: $password)
                                .textContentType(.password)
                        }
                    }
                }

                if let message {
                    FormMessage(text: message, kind: .error)
                }

                ProminentActionButton(title: "Delete My Account", isWorking: isDeleting, isDestructive: true, action: delete)
                    .disabled((auth.accountHasPassword && password.isEmpty) || isDeleting)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeSheet() }.disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func delete() {
        isDeleting = true
        message = nil
        Task {
            defer { isDeleting = false }
            if !auth.accountHasPassword {
                switch await auth.deletePasswordlessAccount() {
                case .success, .cancelled: break
                case .unavailable:
                    message = String(localized: "Set a device passcode to confirm deleting this account.")
                case .failed(let reason):
                    message = reason
                }
                return
            }
            guard !password.isEmpty else { return }
            do {
                try await auth.deleteAccount(password: password)
            } catch let error as AuthError {
                message = error.errorDescription
            } catch {
                message = String(localized: "Something went wrong. Try again.")
            }
        }
    }
}
