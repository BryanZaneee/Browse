import SwiftUI
import AppKit

struct HomeToolsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tools: HomeTools
    let over: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyRevision = 0
    @State private var minutes = 5
    @State private var opened: QuickCard?
    @ObservedObject private var saved = QuickCards.shared

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)).combined(with: .scale(scale: 0.985, anchor: .top))
    }
    private var cardAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0) }
    private var stale: Bool { tools.resultText != browser.typed }
    private var savedCards: [QuickCard] { saved.cards.filter { $0.kind.supported } }
    private var cardVisible: Bool { home && (opened != nil || tools.clock != nil || (eligible && tools.suggestion != nil)) }

    private var reserved: Bool {
        browser.summoning || browser.siteChip != nil || browser.siteOffer != nil
            || (prefs.commandBar && AddressCommand.matching(browser.typed, in: browser) != nil)
            || Keyword.match(browser.typed, in: prefs.keywords) != nil
    }
    private var home: Bool {
        prefs.quickTools && !over && browser.active?.isBlank == true && browser.active?.shy == false && !reserved
    }
    private var eligible: Bool {
        HomeTools.permits(text: browser.typed, enabled: prefs.quickTools,
                          blank: browser.active?.isBlank == true, privateTab: browser.active?.shy != false,
                          over: over, reserved: reserved)
    }
    private var query: Query {
        Query(text: browser.typed, tab: browser.activeID, eligible: eligible && opened == nil, keyRevision: keyRevision, provider: prefs.jevProvider, intelligence: prefs.jevTools)
    }
    private struct Query: Equatable {
        let text: String
        let tab: UUID?
        let eligible: Bool
        let keyRevision: Int
        let provider: AIProvider
        let intelligence: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if home {
                if !savedCards.isEmpty || tools.clock != nil || opened != nil {
                    HStack {
                        if !savedCards.isEmpty {
                            Menu("Saved (\(savedCards.count))") {
                                ForEach(savedCards) { card in
                                    Button { opened = card } label: { Label(card.summary, systemImage: card.kind.symbol) }
                                }
                            }.fixedSize()
                        }
                        Spacer()
                        if tools.clock != nil {
                            Button("Timer") { opened = nil; browser.typed = "timer" }.buttonStyle(.plain)
                        }
                        if opened != nil { Button("Close") { opened = nil }.buttonStyle(.plain) }
                    }
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }

                if opened == nil, browser.typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tools.clock == nil {
                    HomeNotes(saved: saved) { opened = $0 }
                }

                if let clock = tools.clock, opened == nil, tools.suggestion == nil || tools.suggestion?.kind == .timer || tools.suggestion?.kind == .stopwatch {
                    surface {
                        Label(clock.stopwatch ? "Stopwatch" : "Timer", systemImage: "timer")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack {
                                Text(Self.clockText(clock.stopwatch ? clock.shown(at: context.date).rounded(.down) : clock.shown(at: context.date)))
                                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                                    .accessibilityLabel(clock.finished(at: context.date) ? "Timer finished" : "Time remaining or elapsed")
                                Spacer()
                                if clock.finished(at: context.date) {
                                    Text("Done").font(.system(size: 13)).foregroundStyle(Palette.muted)
                                } else {
                                    Pill(clock.started == nil ? "Resume" : "Pause") { tools.clock?.toggle() }
                                }
                                Pill("Reset") { tools.clock = nil }
                            }
                        }
                        Text("Kept while this window is open · no notification")
                            .font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                }
                if let opened {
                    surface {
                        Label(opened.kind.title, systemImage: opened.kind.symbol)
                        QuickCardEditor(card: opened, onNoteSaved: closeNote).id(opened.id)
                    }
                } else if eligible, let tool = tools.suggestion,
                          tools.clock == nil || (tool.kind != .timer && tool.kind != .stopwatch) {
                    surface {
                        HStack {
                            Label(tool.kind.title, systemImage: tool.kind.symbol)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if stale || tools.updating {
                                ProgressView().controlSize(.mini).accessibilityLabel("Updating quick tool")
                            } else {
                                Text(tools.source).font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }
                        if tool.kind == .timer || tool.kind == .stopwatch {
                            HStack {
                                if tool.kind == .timer {
                                    if let seconds = tool.value {
                                        Text(Self.clockText(seconds)).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                                    } else {
                                        Stepper("\(minutes) minutes", value: $minutes, in: 1...1440)
                                            .font(.system(size: 14)).fixedSize()
                                    }
                                } else {
                                    Text("00:00").font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                                }
                                Spacer()
                                Pill("Start", filled: true) {
                                    tools.clock = ToolClock(stopwatch: tool.kind == .stopwatch,
                                                            duration: tool.value ?? Double(minutes * 60), started: Date())
                                }
                                .keyboardShortcut(.return, modifiers: .option)
                            }
                        } else if tool.kind == .email {
                            EmailComposer(input: tool.detail, selectedBody: tool.content, selectedRecipient: tool.recipient)
                        } else if tool.kind == .inbox {
                            InboxCard()
                        } else if tool.kind.isCard {
                            QuickCardEditor(card: QuickCard(kind: tool.kind, input: tool.detail), input: tool.detail, onNoteSaved: closeNote)
                                .id(tool.kind)
                        } else {
                            HStack(spacing: 12) {
                                Text(tool.detail)
                                    .font(.system(size: tool.value == nil ? 13 : 20, weight: .medium))
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: tool.detail)
                                Spacer(minLength: 0)
                                if tool.value != nil {
                                    Pill("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(tool.detail, forType: .string)
                                        browser.announce("Result copied")
                                    }
                                }
                            }
                        }
                        if let footnote = tool.footnote {
                            HStack {
                                Text(footnote).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                if tools.notice != nil, tool.currency != nil {
                                    Pill("Retry") { keyRevision += 1 }
                                }
                            }
                        }
                    }
                    .disabled(stale || tools.updating)
                    .opacity(stale ? 0.65 : 1)
                    .id(tool.kind)
                } else if eligible, let notice = tools.notice {
                    Text(notice).font(.system(size: 11)).foregroundStyle(Palette.faint)
                        .padding(.horizontal, 12)
                }
            }
        }
        .onChange(of: cardVisible, initial: true) { _, visible in tools.showingCard = visible }
        .onDisappear { tools.showingCard = false }
        .animation(cardAnimation, value: tools.suggestion?.kind)
        .animation(cardAnimation, value: opened?.id)
        .animation(cardAnimation, value: tools.clock != nil)
        .onChange(of: prefs.jevTools) { _, _ in tools.invalidate() }
        .onChange(of: prefs.jevProvider) { _, _ in tools.invalidate() }
        .onChange(of: browser.activeID) { _, _ in opened = nil }
        .onChange(of: home) { _, value in if !value { opened = nil } }
        .task(id: query) {
            let q = query
            await tools.update(text: q.text, eligible: q.eligible, key: q.intelligence ? AIKeys.key(for: q.provider) : nil, classify: { text, key in
                try await AIClient.shared.jev(text: text, key: key, provider: q.provider)
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: AIKeys.changed)) { _ in
            tools.invalidate()
            keyRevision += 1
        }
    }

    private func closeNote() {
        opened = nil
        browser.typed = ""
    }

    private func surface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .foregroundStyle(Palette.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
            .transition(cardTransition)
    }

    static func clockText(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct JevSettings: View {
    @ObservedObject var prefs: Preferences
    @State private var pasted = ""
    @State private var hint: String?
    @State private var message: String?

    var body: some View {
        Card {
            Line("Quick tools on the home screen", "Native tools appear as you type, with no AI key required. Currency conversion fetches daily rates using only currency codes. Never in private tabs. Off by default") {
                Switch(on: $prefs.quickTools)
            }
            if prefs.quickTools {
                Rule()
                Line("Understand natural wording with Jev", "Sends eligible home-screen typing to your Jev provider after a short pause to select a tool and its details. Email drafts you edit in the card stay on this Mac. Page AI has separate settings") {
                    Switch(on: $prefs.jevTools)
                }
            }
            if prefs.quickTools && prefs.jevTools {
                Rule()
                Line("Jev provider", "Only this provider receives eligible typing; keys are stored separately") {
                    Picker("Provider", selection: $prefs.jevViaOpenRouter) {
                        Text("TypeSafe").tag(false)
                        Text("OpenRouter").tag(true)
                    }.labelsHidden().frame(width: 140)
                }
                if let hint {
                    Line("Jev API key", "\(hint) · \(Store.testing ? "kept for this test run" : "kept in this Mac’s keychain")") {
                        Pill("Forget") { AIKeys.forget(prefs.jevProvider) }
                    }
                } else if AIKeys.available {
                    Line("Jev API key", "Your own key for the selected provider. Without one, explicit tools still work on this Mac") {
                        HStack {
                            SecureField("API key", text: $pasted).textFieldStyle(.roundedBorder).frame(width: 140)
                                .onSubmit(save)
                            Pill("Save", action: save)
                        }
                    }
                } else {
                    Line("Jev API key", "This unsigned copy cannot keep AI keys. Explicit tools work locally; a named test build can keep a key for the current run") { EmptyView() }
                }
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                Text("Try ‘timer 5 minutes’, ‘18% of 3450’, ‘5 miles in km’, ‘100 USD to EUR’. Return still searches; use the card’s controls. Timers stay in this window until Reset or quit and do not send notifications.")
                    .font(.system(size: 11)).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: prefs.jevProvider) { _, _ in
            pasted = ""; message = nil; hint = AIKeys.hint(for: prefs.jevProvider)
        }
        .onAppear { hint = AIKeys.hint(for: prefs.jevProvider) }
        .onReceive(NotificationCenter.default.publisher(for: AIKeys.changed)) { _ in hint = AIKeys.hint(for: prefs.jevProvider) }
    }

    private func save() {
        let key = pasted
        pasted = ""
        if !prefs.jevViaOpenRouter, key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-or-") {
            message = "Select OpenRouter for an OpenRouter key."
            return
        }
        switch AIKeys.save(key, for: prefs.jevProvider) {
        case .kept: message = Store.testing ? "Key kept for this run." : "Key saved."
        case .unavailable: message = "This copy cannot keep keys."
        case .failed: message = "The key could not be saved."
        }
        hint = AIKeys.hint(for: prefs.jevProvider)
    }
}
