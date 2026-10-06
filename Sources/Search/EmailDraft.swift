import SwiftUI
import AppKit

struct EmailDraft: Equatable {
    var recipient = ""
    var subject = ""
    var body = ""

    static func isCommand(_ input: String) -> Bool {
        let text = HomeTool.phrase(input)
        return HomeTool.captures(#"^(?:(?:send|write|draft|compose)(?: me)? (?:an? )?(?:email|e-mail)(?:\s|$)|(?:email|e-mail)\s+to\s|(?:email|e-mail)\s+.+?\s+(?:saying|that says)\b)"#, text) != nil
    }

    init(input: String, selectedBody: String? = nil, selectedRecipient: String? = nil) {
        let text = String(input.prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?:please\s+)?(?:(?:can|could|would) you\s+)?(?:please\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        var rest = text.replacingOccurrences(of: #"^(?:(?:send|write|draft|compose)(?: me)? (?:an? )?)?(?:email|e-mail)\s*(?:to\s+)?"#,
                                            with: "", options: [.regularExpression, .caseInsensitive])
        if let match = HomeTool.captures(#"^(.*?)\s+(?:that says|saying|to say|with (?:the )?message)\s*:?\s*(.*)$"#, rest) {
            rest = match[1]; body = match[2]
        }
        if let match = HomeTool.captures(#"^(.*?)\s+(?:with (?:the )?subject|subject:)\s*(.*)$"#, rest) {
            rest = match[1]; subject = match[2]
        }
        // Names remain visible for editing; never guess an address from a name.
        recipient = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !Self.isCommand(text) {
            recipient = HomeTool.captures(#"\b(?:write|send a message) to (.+?) (?:by|via) email\b"#, text)?[1] ?? ""
        }
        if let selectedBody, body.isEmpty { body = selectedBody }
        if let selectedRecipient, recipient.isEmpty { recipient = selectedRecipient }
    }

    var validRecipient: Bool {
        recipient.count <= 254 && recipient.rangeOfCharacter(from: .controlCharacters) == nil && HomeTool.captures(#"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$"#, recipient) != nil
    }
    var mailURL: URL? {
        guard validRecipient, subject.count <= 300, body.count <= 10000,
              subject.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        var url = URLComponents()
        url.scheme = "mailto"
        // Encode separators so recipient/body text cannot create extra mail headers.
        guard let encoded = recipient.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "@.-_+"))) else { return nil }
        url.percentEncodedPath = encoded
        url.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return url.url
    }
}

struct EmailComposer: View {
    let input: String
    let selectedBody: String?
    let selectedRecipient: String?
    @State private var draft: EmailDraft
    @State private var message = ""

    init(input: String, selectedBody: String? = nil, selectedRecipient: String? = nil) {
        self.input = input
        self.selectedBody = selectedBody
        self.selectedRecipient = selectedRecipient
        _draft = State(initialValue: EmailDraft(input: input, selectedBody: selectedBody, selectedRecipient: selectedRecipient))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("To · email address", text: $draft.recipient).accessibilityLabel("Email recipient")
            TextField("Subject", text: $draft.subject).accessibilityLabel("Email subject")
            TextEditor(text: $draft.body).frame(height: 85).border(Palette.hairline).accessibilityLabel("Email message")
            HStack {
                Pill("Continue in Mail", filled: true) {
                    guard let url = draft.mailURL else { return }
                    message = NSWorkspace.shared.open(url) ? "Draft opened in your mail app. Review it there and press Send." : "No mail app could open this draft. You can copy it instead."
                }.disabled(draft.mailURL == nil)
                Pill("Copy draft") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("To: \(draft.recipient)\nSubject: \(draft.subject)\n\n\(draft.body)", forType: .string)
                    message = "Draft copied"
                }
            }
            Text(message.isEmpty ? (!draft.recipient.isEmpty && !draft.validRecipient ? "Enter an email address for \(draft.recipient)." : "Review here, then continue in your mail app to send. Nothing is sent automatically.") : message)
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13)).textFieldStyle(.roundedBorder)
        .onChange(of: input) { _, _ in draft = EmailDraft(input: input, selectedBody: selectedBody, selectedRecipient: selectedRecipient); message = "" }
    }
}

struct InboxCard: View {
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your inbox isn’t connected yet").font(.system(size: 15, weight: .medium))
            Text("Live messages need a connected email account. For now, open Mail or write a draft here.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Pill("Open Mail") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail"), NSWorkspace.shared.open(url) { message = "Opened Mail" }
                else { message = "Mail isn’t available on this Mac." }
            }
            if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted) }
        }
    }
}
