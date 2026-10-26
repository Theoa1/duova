import Foundation
import FoundationModels

/// One visible control on a login page, as the page analysis describes it.
/// Never includes what's typed in it.
nonisolated struct PageField: Codable, Equatable, Sendable {
    var index: Int
    var tag: String
    var type: String
    var name: String
    var id: String
    var placeholder: String
    var autocomplete: String
    var label: String

    var isPasswordInput: Bool { tag == "input" && type == "password" }
    var isTextInput: Bool { tag == "input" && ["", "text", "email", "tel"].contains(type) }

    var summary: String {
        var parts = ["\(index): \(tag)"]
        if !type.isEmpty { parts.append("type=\(type)") }
        if !name.isEmpty { parts.append("name=\(name)") }
        if !id.isEmpty { parts.append("id=\(id)") }
        if !autocomplete.isEmpty { parts.append("autocomplete=\(autocomplete)") }
        if !placeholder.isEmpty { parts.append("placeholder=\"\(placeholder)\"") }
        if !label.isEmpty { parts.append("text=\"\(label)\"") }
        return parts.joined(separator: " ")
    }
}

/// Which controls the on-device model picked.
@Generable
nonisolated struct LoginFieldChoice {
    @Guide(description: "Index of the field for the email address, username or phone number, or -1 if there is none")
    var identifier: Int
    @Guide(description: "Index of the password field, or -1 if there is none")
    var password: Int
    @Guide(description: "Index of the button that signs in or continues to the next step, or -1 if there is none")
    var submit: Int
}

/// Asks Apple's on-device model (Apple Intelligence) which controls on a login
/// page are the username, password and sign-in button, for pages whose CSS
/// selectors no longer match. Only the controls' descriptions go to the model,
/// never the saved login, and the model runs entirely on this device.
enum LoginFieldFinder {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    static func choose(from fields: [PageField], appName: String) async -> LoginFieldChoice? {
        guard isAvailable, !fields.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: """
            You read the controls on a website's sign-in page and pick the ones used to sign in. \
            Answer only with indexes from the list. Use -1 when no control fits.
            """)
        let prompt = """
            Sign-in page for \(appName). Visible controls:
            \(fields.prefix(60).map(\.summary).joined(separator: "\n"))
            """
        guard let choice = try? await session.respond(to: prompt, generating: LoginFieldChoice.self).content else {
            return nil
        }
        // Trust the model only where its answer is plausible.
        let byIndex = Dictionary(uniqueKeysWithValues: fields.map { ($0.index, $0) })
        var checked = choice
        if let field = byIndex[choice.password], !field.isPasswordInput { checked.password = -1 }
        if byIndex[choice.password] == nil { checked.password = -1 }
        if let field = byIndex[choice.identifier], !field.isTextInput { checked.identifier = -1 }
        if byIndex[choice.identifier] == nil { checked.identifier = -1 }
        if byIndex[choice.submit] == nil { checked.submit = -1 }
        return checked
    }
}
