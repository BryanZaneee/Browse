import SwiftUI
import AppKit

// Storage-free fixture boundaries. The renderer compiles the production
// Omnibox, AddressField and design tokens, without starting Browse or WebKit.
struct Suggestion: Identifiable, Equatable {
    enum Kind { case search, visited, known, open, command }
    let key: String
    let title: String
    let url: URL
    let kind: Kind
    var id: String { key }
}

struct SearchSite: Equatable {
    let host: String
    let name: String
}

final class Favicons {
    static let shared = Favicons()
    static func site(_ url: URL) -> String? { url.host }
    func cached(_ site: String) -> NSImage? { nil }
}

@MainActor
final class Browser: ObservableObject {
    struct Tab { var isBlank = true }
    @Published var typed = ""
    @Published var offers: [Suggestion] = []
    @Published var picked: Int?
    @Published var siteChip: SearchSite?
    @Published var siteOffer: SearchSite?
    @Published var ending: String?
    @Published var refusals = 0
    @Published var focusRequest = 0
    var active: Tab? = Tab()
    var completed: String {
        if let picked, offers.indices.contains(picked) { return offers[picked].key }
        return typed + (ending ?? "")
    }
    private(set) var opened: URL?
    func take(_ offer: Suggestion) { opened = offer.url }
    func submit() { opened = offers.first?.url }
    func dismiss() { typed = ""; offers = [] }
    func lockSiteOffer() -> Bool { false }
    func stopCompleting() { ending = nil }
    func walk(_ step: Int) {
        let next = (picked ?? (step > 0 ? -1 : offers.count)) + step
        picked = offers.indices.contains(next) ? next : nil
    }
}
