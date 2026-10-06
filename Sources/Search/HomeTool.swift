import Foundation

/// Jev chooses a tool. Values and arithmetic always come from the input on this Mac.
enum HomeToolKind: String, Codable, CaseIterable {
    case event, reminder, todo, timer, habit, color, split, expense, convert, calculate, travel, poll, contact, link, countdown, timezone, random, goal, note, stopwatch, email, inbox, none

    // Retain retired identifiers for saved-data decoding and rejected-intent recognition.
    static var supported: [Self] { allCases.filter { ![.split, .event, .habit, .goal, .poll].contains($0) } }
    var supported: Bool { Self.supported.contains(self) }

    var title: String {
        switch self {
        case .timer: return "Timer"
        case .stopwatch: return "Stopwatch"
        case .calculate: return "Calculate"
        case .convert: return "Convert"
        case .split: return "Split a bill"
        case .event: return "Event"
        case .reminder: return "Reminder"
        case .todo: return "Checklist"
        case .habit: return "Habit"
        case .color: return "Color"
        case .expense: return "Expense"
        case .travel: return "Trip"
        case .poll: return "Poll"
        case .contact: return "Contact"
        case .link: return "Bookmark"
        case .countdown: return "Countdown"
        case .timezone: return "Time zone"
        case .random: return "Random"
        case .goal: return "Goal"
        case .note: return "Note"
        case .email: return "Compose email"
        case .inbox: return "Inbox"
        case .none: return "Search"
        }
    }

    var symbol: String {
        switch self {
        case .timer, .stopwatch: return "timer"
        case .calculate: return "equal"
        case .convert: return "arrow.left.arrow.right"
        case .split: return "person.2"
        case .event: return "calendar"
        case .reminder: return "bell"
        case .todo: return "checklist"
        case .habit: return "repeat"
        case .color: return "paintpalette"
        case .expense: return "creditcard"
        case .travel: return "airplane"
        case .poll: return "chart.bar"
        case .contact: return "person.crop.circle"
        case .link: return "link"
        case .countdown: return "calendar.badge.clock"
        case .timezone: return "globe"
        case .random: return "dice"
        case .goal: return "target"
        case .note: return "note.text"
        case .email: return "square.and.pencil"
        case .inbox: return "tray"
        case .none: return "magnifyingglass"
        }
    }
}

struct HomeTool: Equatable {
    let kind: HomeToolKind
    var value: Double?
    var detail: String
    var footnote: String? = nil
    var currency: CurrencyConversion? = nil
    var content: String? = nil
    var recipient: String? = nil

    static func parse(_ kind: HomeToolKind, text: String) -> HomeTool {
        let text = kind == .email ? text : phrase(text)
        switch kind {
        case .timer:
            return HomeTool(kind: kind, value: duration(text), detail: "Choose a duration, then start.")
        case .stopwatch:
            return HomeTool(kind: kind, value: nil, detail: "Count up from zero.")
        case .calculate:
            let value = calculate(text)
            return HomeTool(kind: kind, value: value, detail: value.map(number) ?? "Try 18% of 3450 or (12 + 8) / 2")
        case .convert:
            if let currency = CurrencyConversion.parse(text) {
                return HomeTool(kind: kind, value: nil, detail: currency.label, footnote: "Fetching exchange rate…", currency: currency)
            }
            if let result = conversion(text) { return HomeTool(kind: kind, value: result.value, detail: result.detail) }
            return HomeTool(kind: kind, value: nil, detail: "Try 5 miles in km, 72°F to °C, or 100 USD to EUR")
        case .split:
            let pattern = #"^split\s+(?:(?:a|the)\s+)?([$€£]?)\s*(\d+(?:\.\d+)?)\s+(?:bill\s+)?(?:between|among|by|with)\s+(\d+)\s*(?:people|persons|ways)?[.!?]?\s*$"#
            if let fields = captures(pattern, text.lowercased()),
               let amount = Double(fields[2]), let people = Double(fields[3]),
               amount.isFinite, amount > 0, people > 0, people <= 10000 {
                let share = (amount / people * 100).rounded(.up) / 100
                guard share.isFinite else { return HomeTool(kind: kind, value: nil, detail: "Amount is too large") }
                return HomeTool(kind: kind, value: share, detail: "\(fields[1])\(number(share)) per person · \(Int(people)) people (rounded up to cents)")
            }
            return HomeTool(kind: kind, value: nil, detail: "Try split $84 between 3")
        default:
            return HomeTool(kind: kind, value: nil, detail: text)
        }
    }

    /// Conservative offline matches; a search containing a tool's name stays a search.
    static func local(_ text: String) -> HomeTool? {
        guard let tool = localCandidate(text), tool.kind.supported else { return nil }
        return tool
    }

    private static func localCandidate(_ text: String) -> HomeTool? {
        let t = phrase(text).lowercased()
        if EmailDraft.isCommand(text) { return parse(.email, text: text) }
        if ["email", "mail", "my email", "my inbox", "show my inbox", "show unread email"].contains(t) { return parse(.inbox, text: text) }
        if (captures(#"^(?:i (?:need|want) (?:a )?|(?:set|start) (?:a )?)?(?:timer|stopwatch)\b"#, t) != nil
            && (t.hasSuffix("timer") || t.hasSuffix("stopwatch") || duration(t) != nil))
            || captures(#"^\d+(?:\.\d+)?\s*(?:min(?:ute)?s?|seconds?|hours?)\s+(?:timer|focus|break)$"#, t) != nil
            || (captures(#"^(?:set|start) (?:a )?"#, t) != nil && t.hasSuffix("timer") && duration(t) != nil)
            || t == "pomodoro" {
            return parse(t.contains("stopwatch") ? .stopwatch : .timer, text: text)
        }
        if t.hasPrefix("split "), parse(.split, text: text).value != nil { return parse(.split, text: text) }
        if CurrencyConversion.parse(t) != nil { return parse(.convert, text: t) }
        if conversion(t) != nil { return parse(.convert, text: text) }
        if text.lowercased().hasPrefix("convert ") { return parse(.convert, text: t) }
        if t.hasPrefix("buy "), QuickCard.options(String(t.dropFirst(4))).count > 1 { return parse(.todo, text: text) }
        if calculate(t) != nil, t.contains(where: { "+-*/%()×÷".contains($0) }) || t.hasPrefix("calculate ") {
            return parse(.calculate, text: text)
        }
        for kind in HomeToolKind.allCases where kind != .none {
            if t == kind.rawValue || t == kind.title.lowercased() { return parse(kind, text: "") }
        }
        let prefixes: [(String, HomeToolKind)] = [
            ("make a shopping list ", .todo), ("make a checklist ", .todo), ("add a note", .note), ("save a note", .note),
            ("set a reminder ", .reminder), ("track my goal ", .goal), ("log an expense ", .expense),
            ("event ", .event), ("remind me ", .reminder), ("reminder ", .reminder),
            ("checklist ", .todo), ("todo ", .todo), ("habit ", .habit),
            ("color ", .color), ("spent ", .expense), ("expense ", .expense),
            ("trip ", .travel), ("poll ", .poll),
            ("contact ", .contact), ("bookmark ", .link), ("countdown ", .countdown),
            ("days until ", .countdown), ("time in ", .timezone), ("timezone ", .timezone),
            ("roll ", .random), ("flip a coin", .random), ("pick between ", .random),
            ("goal ", .goal), ("note ", .note)
        ]
        if let match = prefixes.first(where: { t.hasPrefix($0.0) }) { return parse(match.1, text: text) }
        if captures(#"^#[0-9a-f]{6}$"#, t) != nil { return parse(.color, text: text) }
        return nil
    }

    /// Strip conversational framing without changing the values in the request.
    static func phrase(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in [#"^(?:please\s+)?(?:can|could|would) you\s+"#, #"^please\s+"#,
                        #"^(?:what is|what's|how much is)\s+"#, #"^convert\s+"#,
                        #"\s+please[.!?]*$"#, #"[?]+$"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }

    static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    static func duration(_ text: String) -> Double? {
        var t = text.lowercased().replacingOccurrences(of: #"(\d)-(?=[a-z])"#, with: "$1 ", options: .regularExpression)
        // ponytail: small English duration vocabulary; expand only with real input cases.
        let words = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "fifteen": "15", "twenty": "20", "thirty": "30"]
        for (word, value) in words { t = t.replacingOccurrences(of: "\\b\(word)\\b", with: value, options: .regularExpression) }
        t = t.replacingOccurrences(of: "half an hour", with: "30 minutes")
            .replacingOccurrences(of: "an hour", with: "1 hour")
            .replacingOccurrences(of: "a minute", with: "1 minute")
        guard let re = try? NSRegularExpression(pattern: #"(?<![\d.\-])(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#) else { return nil }
        let matches = re.matches(in: t, range: NSRange(t.startIndex..., in: t))
        var seconds = 0.0
        for hit in matches {
            guard let nr = Range(hit.range(at: 1), in: t), let ur = Range(hit.range(at: 2), in: t), let n = Double(t[nr]) else { return nil }
            let unit = t[ur].first
            seconds += n * (unit == "h" ? 3600 : unit == "m" ? 60 : 1)
        }
        if matches.isEmpty, t.contains("pomodoro") { seconds = 1500 }
        guard seconds.isFinite, seconds >= 1, seconds <= 7 * 86400 else { return nil }
        return seconds.rounded()
    }

    static func conversion(_ text: String) -> (value: Double, detail: String)? {
        let units: [String: Dimension] = [
            "km": UnitLength.kilometers, "kilometers": UnitLength.kilometers,
            "m": UnitLength.meters, "meters": UnitLength.meters,
            "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
            "mile": UnitLength.miles, "miles": UnitLength.miles, "mi": UnitLength.miles,
            "ft": UnitLength.feet, "feet": UnitLength.feet, "inches": UnitLength.inches,
            "kg": UnitMass.kilograms, "g": UnitMass.grams, "lb": UnitMass.pounds, "lbs": UnitMass.pounds,
            "pound": UnitMass.pounds, "pounds": UnitMass.pounds, "kilogram": UnitMass.kilograms, "kilograms": UnitMass.kilograms,
            "meter": UnitLength.meters, "metres": UnitLength.meters, "kilometres": UnitLength.kilometers,
            "inch": UnitLength.inches, "centimeters": UnitLength.centimeters,
            "celsius": UnitTemperature.celsius, "fahrenheit": UnitTemperature.fahrenheit,
            "oz": UnitMass.ounces, "c": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit,
            "k": UnitTemperature.kelvin
        ]
        var t = phrase(text).lowercased().replacingOccurrences(of: "°", with: "")
        if let parts = captures(#"^how many ([a-z]+) (?:are )?in (-?\d+(?:\.\d+)?) ([a-z]+)$"#, t) {
            t = "\(parts[2]) \(parts[3]) in \(parts[1])"
        }
        guard let parts = captures(#"^(?:convert\s+)?(-?\d+(?:\.\d+)?)\s*([a-z]+)\s+(?:to|in|into)\s+([a-z]+)\s*[?]?\s*$"#, t),
              let value = Double(parts[1]), value.isFinite,
              let from = units[parts[2]], let to = units[parts[3]], type(of: from) == type(of: to) else { return nil }
        let result = to.converter.value(fromBaseUnitValue: from.converter.baseUnitValue(fromValue: value))
        guard result.isFinite else { return nil }
        return (result, "\(number(value)) \(from.symbol) = \(number(result)) \(to.symbol)")
    }

    /// A bounded arithmetic grammar, never an expression evaluator with method access.
    static func calculate(_ text: String) -> Double? {
        guard text.count <= 256 else { return nil }
        var s = phrase(text).lowercased()
        s = s.replacingOccurrences(of: #"^(?:calculate|calc|what is|what's)\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[=?]+$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d+(?:\.\d+)?)\s*%\s*of\s*"#, with: "($1/100)*", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d+(?:\.\d+)?)\s*%"#, with: "($1/100)", options: .regularExpression)
        s = s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
        var parser = Arithmetic(chars: Array(s))
        guard let value = parser.expression(), parser.finished, value.isFinite else { return nil }
        return value
    }

    private struct Arithmetic {
        let chars: [Character]
        var index = 0
        mutating func skip() { while index < chars.count, chars[index].isWhitespace { index += 1 } }
        var finished: Bool { mutating get { skip(); return index == chars.count } }
        mutating func take(_ c: Character) -> Bool {
            skip()
            guard index < chars.count, chars[index] == c else { return false }
            index += 1
            return true
        }
        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while true {
                if take("+") { guard let rhs = term() else { return nil }; value += rhs }
                else if take("-") { guard let rhs = term() else { return nil }; value -= rhs }
                else { return value }
            }
        }
        mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while true {
                if take("*") { guard let rhs = factor() else { return nil }; value *= rhs }
                else if take("/") { guard let rhs = factor(), rhs != 0 else { return nil }; value /= rhs }
                else { return value }
            }
        }
        mutating func factor() -> Double? {
            if take("-") { return factor().map { -$0 } }
            if take("+") { return factor() }
            if take("(") {
                guard let value = expression(), take(")") else { return nil }
                return value
            }
            skip()
            let start = index
            while index < chars.count, chars[index].isASCII, chars[index].isNumber || chars[index] == "." { index += 1 }
            return Double(String(chars[start..<index]))
        }
    }
}
