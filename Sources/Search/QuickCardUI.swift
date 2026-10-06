import SwiftUI
import AppKit

struct QuickCardEditor: View {
    @State var card: QuickCard
    var input: String? = nil
    var onNoteSaved: (() -> Void)? = nil
    @ObservedObject var saved = QuickCards.shared
    @State private var newItem = ""
    @State private var message = ""
    @State private var fieldsHeight: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if card.kind == .note {
                fields
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) { fields }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: QuickCardHeight.self, value: geometry.size.height)
                        })
                        .padding(.vertical, 2)
                }
                .frame(height: min(190, max(30, fieldsHeight + 4)))
                .onPreferenceChange(QuickCardHeight.self) { fieldsHeight = $0 }
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: fieldsHeight)
            }
            HStack {
                Pill(card.kind == .note ? "Save note" : "Save on this Mac", filled: true) {
                    do {
                        try saved.save(card); message = "Saved on this Mac"
                        if card.kind == .note { onNoteSaved?() }
                    }
                    catch { message = "Could not save. Keep this card open; remove a saved card if you have 100." }
                }
                .disabled(card.kind == .note && card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if card.kind != .note {
                    Pill("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                        message = "Copied"
                    }
                }
                if saved.cards.contains(where: { $0.id == card.id }) {
                    Pill(card.kind == .note ? "Delete" : "Delete saved") {
                        do {
                            try saved.delete(card.id); message = "Removed from saved cards"
                            if card.kind == .note { onNoteSaved?() }
                        }
                        catch { message = "Could not remove saved card" }
                    }
                }
            }
            if card.kind != .note || !message.isEmpty {
                Text(message.isEmpty ? "Save to keep this card on this Mac." : message)
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
        .onChange(of: input) { _, value in
            if let value { card = QuickCard(kind: card.kind, input: value) }
        }
        .onChange(of: card) { _, _ in message = card.kind == .note ? "" : "Unsaved changes" }
    }

    @ViewBuilder private var fields: some View {
        switch card.kind {
        case .note:
            TextEditor(text: $card.text).frame(height: 60).scrollContentBackground(.hidden)
                .accessibilityLabel("Note text")
        case .todo:
            ForEach(card.items.indices, id: \.self) { index in
                Toggle(card.items[index], isOn: Binding(get: { card.checked.contains(index) }, set: { value in
                    if value { card.checked.insert(index) } else { card.checked.remove(index) }
                })).toggleStyle(.checkbox)
            }
            HStack {
                TextField("Add item", text: $newItem)
                Pill("Add") {
                    let value = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty, card.items.count < 50 { card.items.append(value); newItem = "" }
                }
            }
        case .reminder, .travel, .countdown:
            TextField(card.kind == .travel ? "Trip / destination" : "Title", text: $card.title)
            dateField("Date", date: $card.date)
            if card.kind == .travel {
                TextField("Origin / transport", text: $card.extra)
                dateField("Return", date: $card.end)
                if let start = card.date, let end = card.end, end < start { Text("Return is before departure").foregroundStyle(.red) }
            }
            if card.kind == .countdown, let date = card.date {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: context.date), to: Calendar.current.startOfDay(for: date)).day ?? 0
                    Text(days == 0 ? "Today" : "\(abs(days)) days \(days < 0 ? "since" : "to go")")
                        .font(.system(size: 26, weight: .medium)).monospacedDigit()
                }
            }
            if card.kind == .reminder {
                Text("Local card · no calendar sync or notification").foregroundStyle(Palette.muted)
            }
        case .expense:
            TextField("What was it for?", text: $card.title)
            HStack {
                TextField("Amount", text: $card.amount)
                TextField("Currency", text: $card.currency).frame(width: 70)
                Picker("Category", selection: $card.category) {
                    ForEach(["Food", "Transport", "Shopping", "Bills", "Entertainment", "Health", "Other"], id: \.self) { Text($0) }
                }
            }
            if !card.amount.isEmpty, Decimal(string: card.amount) == nil { Text("Enter a numeric amount").foregroundStyle(.red) }
        case .contact:
            TextField("Name", text: $card.title)
            TextField("Email", text: $card.text)
            TextField("Phone", text: $card.extra)
        case .link:
            TextField("Title / note", text: $card.title)
            TextField("https://…", text: $card.text)
            if let url = card.validURL { Link("Open bookmark", destination: url) }
            else { Text("Enter an http or https address").foregroundStyle(Palette.muted) }
        case .color:
            HStack {
                ColorPicker("Color", selection: Binding(get: { color }, set: { value in
                    guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
                    card.hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                }), supportsOpacity: false)
                TextField("#RRGGBB", text: $card.hex).frame(width: 110)
            }
            RoundedRectangle(cornerRadius: 8).fill(color).frame(height: 42)
            if !validHex { Text("Use six hex digits, such as #FF6B35").foregroundStyle(Palette.muted) }
        case .timezone:
            zonePicker("From", selection: $card.fromZone)
            zonePicker("To", selection: $card.zone)
            Toggle("Current time", isOn: $card.live)
            if !card.live {
                dateField("Date / time on this Mac", date: $card.date)
                Text("Date picker uses \(TimeZone.current.identifier)").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if card.live || card.date != nil {
                    let date = card.live ? context.date : (card.date ?? context.date)
                    Text("\(formatted(date, zone: card.fromZone)) → \(formatted(date, zone: card.zone))")
                        .font(.system(size: 16, weight: .medium)).monospacedDigit()
                }
            }
        case .random:
            TextField("roll 2d6, flip a coin, or tea, coffee", text: $card.text)
            HStack {
                Text(card.randomResult.isEmpty ? "Ready to choose" : card.randomResult)
                    .font(.system(size: 22, weight: .medium)).textSelection(.enabled)
                Spacer()
                Pill("Pick / roll", filled: true) {
                    card.randomResult = QuickCard.roll(card.text) ?? "Try 2d6, flip a coin, or tea, coffee"
                }
            }
        default: EmptyView()
        }
    }

    private func dateField(_ title: String, date: Binding<Date?>) -> some View {
        HStack {
            if date.wrappedValue != nil {
                DatePicker(title, selection: Binding(get: { date.wrappedValue ?? Date() }, set: { date.wrappedValue = $0 }), displayedComponents: [.date, .hourAndMinute])
                Button("Clear") { date.wrappedValue = nil }.buttonStyle(.plain)
            } else {
                Pill("Choose \(title.lowercased())") { date.wrappedValue = Date() }
            }
        }
    }
    private func zonePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + [selection.wrappedValue])).sorted(), id: \.self) { Text($0).tag($0) }
        }
    }
    private func formatted(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "MMM d, HH:mm z"
        return formatter.string(from: date)
    }
    private var validHex: Bool { HomeTool.captures(#"^#[0-9a-f]{6}$"#, card.hex) != nil }
    private var color: Color {
        guard validHex, let rgb = UInt32(card.hex.dropFirst(), radix: 16) else { return .gray }
        return Color(red: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    private var copyText: String {
        switch card.kind {
        case .color: return card.hex
        case .todo, .poll: return ([card.title] + card.items.enumerated().map { "\(card.checked.contains($0.offset) ? "[x]" : "[ ]") \($0.element)" }).joined(separator: "\n")
        case .goal: return "\(card.title): \(card.current)/\(card.target)"
        case .expense: return "\(card.amount) \(card.currency) · \(card.title) · \(card.category)"
        case .random: return "\(card.text): \(card.randomResult)"
        case .timezone:
            let date = card.live ? Date() : (card.date ?? Date())
            return "\(formatted(date, zone: card.fromZone)) → \(formatted(date, zone: card.zone))"
        case .habit: return card.title + " · " + card.days.sorted().map { Calendar.current.weekdaySymbols[$0 - 1] }.joined(separator: ", ")
        default: return [card.title, card.text, card.extra, card.date?.formatted() ?? "", card.end?.formatted() ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }
}

private struct QuickCardHeight: PreferenceKey {
    static var defaultValue: CGFloat = 120
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}


/// Small saved notes on the idle home screen. Opening one reuses the note editor.
struct HomeNotes: View {
    @ObservedObject var saved: QuickCards
    let open: (QuickCard) -> Void

    var body: some View {
        let notes = saved.cards.filter { $0.kind == .note }
        if !notes.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(notes) { note in
                        Button { open(note) } label: {
                            Text(note.text.isEmpty ? note.title : note.text)
                                .font(.system(size: 13)).foregroundStyle(Palette.ink)
                                .lineLimit(5).multilineTextAlignment(.leading)
                                .frame(width: 144, height: 88, alignment: .topLeading)
                                .padding(12)
                                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit note: \(note.text.isEmpty ? note.title : note.text)")
                        .help("Edit note")
                    }
                }.padding(.vertical, 4)
            }
            .frame(height: 120)
        }
    }
}
