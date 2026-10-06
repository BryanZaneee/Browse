import Foundation

struct CurrencyConversion: Equatable {
    let amount: Decimal
    let base: String
    let quote: String

    static func parse(_ input: String) -> CurrencyConversion? {
        let text = HomeTool.phrase(input).lowercased()
        guard text.count <= 256 else { return nil }
        let number = #"[-+]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#
        guard let match = HomeTool.captures("^(.+?)\\s+(?:to|in|into|as)\\s+(.+?)$", text),
              let quote = code(match[2]) else { return nil }
        let left = match[1]
        let amountText: String
        let currencyText: String
        if let parts = HomeTool.captures("^(\(number))\\s*(.+)$", left) {
            amountText = parts[1]; currencyText = parts[2]
        } else if let parts = HomeTool.captures("^(.+?)\\s*(\(number))$", left) {
            currencyText = parts[1]; amountText = parts[2]
        } else { return nil }
        guard let base = code(currencyText),
              let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN, abs(NSDecimalNumber(decimal: amount).doubleValue) <= 1e12 else { return nil }
        return CurrencyConversion(amount: amount, base: base, quote: quote)
    }

    static func code(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Ambiguous $ / dollars mean USD and are always labeled USD in the result.
        // Use ISO codes for other dollar currencies; ambiguous ¥ is not guessed.
        let aliases = ["$": "USD", "us$": "USD", "dollar": "USD", "dollars": "USD", "us dollars": "USD",
                       "€": "EUR", "euro": "EUR", "euros": "EUR", "£": "GBP", "pound": "GBP", "pounds": "GBP", "british pounds": "GBP",
                       "yen": "JPY", "japanese yen": "JPY", "rupees": "INR", "indian rupees": "INR", "₹": "INR",
                       "canadian dollars": "CAD", "australian dollars": "AUD", "swiss francs": "CHF", "yuan": "CNY"]
        if let code = aliases[value] { return code }
        let code = value.uppercased()
        return code.count == 3 && Locale.commonISOCurrencyCodes.contains(code) ? code : nil
    }

    var label: String { "\(amount.formatted()) \(base) → \(quote)" }

    func tool(rate: CurrencyRate) -> HomeTool? {
        guard rate.base == base, rate.quote == quote, !rate.rate.isNaN, rate.rate > 0 else { return nil }
        let value = amount * rate.rate
        guard !value.isNaN, NSDecimalNumber(decimal: value).doubleValue.isFinite else { return nil }
        let result = value.formatted(.currency(code: quote))
        return HomeTool(kind: .convert, value: NSDecimalNumber(decimal: value).doubleValue,
                        detail: "\(amount.formatted()) \(base) ≈ \(result) \(quote)",
                        footnote: base == quote ? "Same currency · no exchange needed" : "Daily reference rate · \(rate.date) · Frankfurter", currency: self)
    }
}

struct CurrencyRate: Decodable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal

    func valid(for conversion: CurrencyConversion, now: Date = Date()) -> Bool {
        guard base == conversion.base, quote == conversion.quote, !rate.isNaN, rate > 0,
              NSDecimalNumber(decimal: rate).doubleValue.isFinite,
              HomeTool.captures(#"^\d{4}-\d{2}-\d{2}$"#, date) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let day = formatter.date(from: date) else { return false }
        // Do not silently present old or future rates as current. Weekends/holidays are allowed.
        return day <= now && now.timeIntervalSince(day) <= 10 * 86400
    }
}

@MainActor
final class CurrencyRates {
    static let shared = CurrencyRates()
    private var cache: [String: (CurrencyRate, Date)] = [:]

    func rate(for conversion: CurrencyConversion) async throws -> CurrencyRate {
        let pair = conversion.base + "/" + conversion.quote
        if let (rate, fetched) = cache[pair], Date().timeIntervalSince(fetched) < 3600, rate.valid(for: conversion) { return rate }
        let rate = try await AIClient.shared.currencyRate(for: conversion)
        try Task.checkCancellation()
        if cache.count >= 64 { cache.removeAll() }
        cache[pair] = (rate, Date())
        return rate
    }
}

extension AIClient {
    static func currencyRequest(for conversion: CurrencyConversion) throws -> URLRequest {
        guard CurrencyConversion.code(conversion.base) == conversion.base,
              CurrencyConversion.code(conversion.quote) == conversion.quote,
              let url = URL(string: "https://api.frankfurter.dev/v2/rate/\(conversion.base.lowercased())/\(conversion.quote.lowercased())") else { throw AIError.refusedHost }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Only the currency pair leaves the Mac. No amount, typed phrase or AI key.
        return request
    }

    func currencyRate(for conversion: CurrencyConversion) async throws -> CurrencyRate {
        let request = try Self.currencyRequest(for: conversion)
        let (bytes, response) = try await session.bytes(for: request, delegate: self)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.unreadable }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 16384 else { throw AIError.unreadable }
            data.append(byte)
        }
        let rate = try JSONDecoder().decode(CurrencyRate.self, from: data)
        guard rate.valid(for: conversion) else { throw AIError.unreadable }
        return rate
    }
}
