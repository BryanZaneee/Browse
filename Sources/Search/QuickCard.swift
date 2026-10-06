import Foundation
import Combine

extension HomeToolKind {
    var isCard: Bool { ![.timer, .stopwatch, .calculate, .convert, .split, .email, .inbox, .none].contains(self) }
    var criterion: String {
        switch self {
        case .event: return "Record a meeting, gathering or event with a date or place."
        case .reminder: return "Record something to remember or a task with a due date."
        case .todo: return "Make a checklist or shopping list of tasks or items."
        case .timer: return "Start a duration countdown, focus session or break."
        case .stopwatch: return "Count elapsed time upward."
        case .habit: return "Track a recurring habit on days of the week."
        case .color: return "Choose or inspect a color, such as a hex code."
        case .split: return "Divide a bill equally between people."
        case .expense: return "Record money spent on something."
        case .convert: return "Convert currencies or length, mass or temperature units."
        case .calculate: return "Compute arithmetic or a percentage."
        case .travel: return "Record a trip, destination and travel dates; not search for tickets."
        case .poll: return "Make a poll with named options."
        case .contact: return "Keep a person's name and contact information."
        case .link: return "Save a bookmark with a note."
        case .countdown: return "Count days until a calendar date or event."
        case .timezone: return "See or convert the time in another time zone."
        case .random: return "Roll dice, flip a coin or randomly pick between choices."
        case .goal: return "Track numeric progress toward a target."
        case .note: return "Explicitly save a note or personal thought; not a general question or web search."
        case .email: return "Compose or send an email, write to someone or draft a message for a recipient. Never actually send it."
        case .inbox: return "Read or check my email, inbox or unread messages. The word email alone opens the inbox."
        case .none: return "Web search, navigation, product research, ambiguous input or requests not served by these tools."
        }
    }
    var example: String {
        switch self {
        case .timer: return "timer 5 minutes"
        case .stopwatch: return "stopwatch"
        case .calculate: return "18% of 3450"
        case .convert: return "5 miles in km"
        case .split: return "split $84 between 3"
        default: return title.lowercased()
        }
    }
}

/// Editable values parsed from local or Jev-selected source text, never generated.
struct QuickCard: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: HomeToolKind
    var title = ""
    var text = ""
    var extra = ""
    var date: Date?
    var end: Date?
    var items: [String] = []
    var checked: Set<Int> = []
    var days: Set<Int> = []
    var amount = ""
    var currency = Locale.current.currency?.identifier ?? "USD"
    var category = "Other"
    var current = 0
    var target = 12
    var hex = "#FF6B35"
    var zone = "Asia/Tokyo"
    var fromZone = TimeZone.current.identifier
    var live = true
    var randomResult = ""

    init(kind: HomeToolKind, input: String = "") {
        self.kind = kind
        let source = HomeTool.phrase(String(input.prefix(1000)))
        title = source.replacingOccurrences(of: #"^(?:make a shopping list(?: with| of)?|make a checklist(?: with| of)?|add a note|save a note|set a reminder(?: to)?|track my goal(?: to)?|log an expense|event|remind me to|reminder|checklist|todo|buy|habit|color|expense|trip|poll|contact|bookmark|countdown|days until|timezone|goal|note)\s*:?[ ]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        if [.event, .reminder, .travel, .countdown].contains(kind) {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            date = detector?.firstMatch(in: source, range: NSRange(source.startIndex..., in: source))?.date
        }
        switch kind {
        case .todo, .poll:
            items = Self.options(title)
        case .note: text = title; title = ""
        case .color:
            if let value = HomeTool.captures(#"#([0-9a-f]{6})\b"#, source)?[1] { hex = "#" + value.uppercased() }
        case .expense:
            if let match = HomeTool.captures(#"(?:spent|expense)?\s*([$€£]?)\s*(\d+(?:\.\d{1,2})?)(?:\s+on\s+(.+))?"#, source) {
                amount = match[2]
                if !match[3].isEmpty { title = match[3] }
                if let code = ["$": "USD", "€": "EUR", "£": "GBP"][match[1]] { currency = code }
            }
        case .contact:
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.link.rawValue)
            for match in detector?.matches(in: source, range: NSRange(source.startIndex..., in: source)) ?? [] {
                if let phone = match.phoneNumber { extra = phone }
                if let url = match.url, url.scheme == "mailto" { text = String(url.absoluteString.dropFirst(7)) }
            }
        case .link:
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            if let url = detector?.firstMatch(in: source, range: NSRange(source.startIndex..., in: source))?.url,
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") { text = url.absoluteString }
        case .habit:
            if source.localizedCaseInsensitiveContains("every day") || source.localizedCaseInsensitiveContains("every morning") { days = Set(1...7) }
            if source.localizedCaseInsensitiveContains("weekday") { days = Set(2...6) }
        case .goal:
            if let match = HomeTool.captures(#"\b(\d+)\b"#, source), let n = Int(match[1]), (1...1000000).contains(n) { target = n }
            if let match = HomeTool.captures(#"(\d+)\s+done\b"#, source), let n = Int(match[1]) { current = min(target, n) }
        case .timezone:
            let aliases = ["tokyo": "Asia/Tokyo", "london": "Europe/London", "new york": "America/New_York", "pst": "America/Los_Angeles", "ist": "Asia/Kolkata", "utc": "Etc/UTC"]
            let lower = source.lowercased()
            let mentioned = aliases.compactMap { key, value -> (String.Index, String)? in
                lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: key))\\b", options: .regularExpression).map { ($0.lowerBound, value) }
            }.sorted { $0.0 < $1.0 }
            if let last = mentioned.last { zone = last.1 }
            if mentioned.count > 1 { fromZone = mentioned[0].1 }
            if let match = HomeTool.captures(#"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, source),
               let hour = Int(match[1]), (1...12).contains(hour), let from = TimeZone(identifier: fromZone) {
                var calendar = Calendar.current; calendar.timeZone = from
                let minute = Int(match[2]) ?? 0
                if minute < 60 {
                    date = calendar.date(bySettingHour: hour % 12 + (match[3].lowercased() == "pm" ? 12 : 0), minute: minute, second: 0, of: Date())
                    live = false
                }
            }
        case .random: text = source
        default: break
        }
    }

    static func options(_ text: String) -> [String] {
        Array(text.replacingOccurrences(of: #"\s+(?:and|or)\s+"#, with: ",", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(50))
    }

    static func roll(_ text: String) -> String? {
        if text.localizedCaseInsensitiveContains("coin") { return Bool.random() ? "Heads" : "Tails" }
        if let match = HomeTool.captures(#"^(?:roll\s+)?(\d{1,2})?d(\d{1,6})$"#, text.trimmingCharacters(in: .whitespacesAndNewlines)),
           let sides = Int(match[2]), (2...100000).contains(sides) {
            let count = Int(match[1]) ?? 1
            guard (1...20).contains(count) else { return nil }
            let rolls = (0..<count).map { _ in Int.random(in: 1...sides) }
            return rolls.map(String.init).joined(separator: " + ") + (count > 1 ? " = \(rolls.reduce(0, +))" : "")
        }
        let options = options(text.replacingOccurrences(of: #"^(?:pick between|pick|random)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]))
        return options.count >= 2 ? options.randomElement() : nil
    }

    var validURL: URL? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    var summary: String { title.isEmpty ? (text.isEmpty ? kind.title : String(text.prefix(60))) : String(title.prefix(60)) }
}

@MainActor
final class QuickCards: ObservableObject {
    static let shared = QuickCards(defaults: Store.settings)
    @Published private(set) var cards: [QuickCard]
    private let defaults: UserDefaults
    init(defaults: UserDefaults) {
        self.defaults = defaults
        cards = defaults.data(forKey: "jev.saved.cards").flatMap { try? JSONDecoder().decode([QuickCard].self, from: $0) } ?? []
    }
    func save(_ card: QuickCard) throws {
        var next = cards
        if let index = next.firstIndex(where: { $0.id == card.id }) { next[index] = card }
        else {
            guard next.count < 100 else { throw CocoaError(.fileWriteOutOfSpace) }
            next.insert(card, at: 0)
        }
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: "jev.saved.cards")
        cards = next
    }
    func delete(_ id: UUID) throws {
        let next = cards.filter { $0.id != id }
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: "jev.saved.cards")
        cards = next
    }
}
