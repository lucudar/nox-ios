import SwiftUI

struct RoutesView: View {
    @Environment(AppSettings.self) private var settings

    @State private var editing: RouteRule?
    @State private var creating = false

    var body: some View {
        Screen(title: settings.t("Маршруты", "Routes"), trailing: {
            CircleButton(action: {
                Haptics.tap()
                creating = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Ink.primary)
            }
            .accessibilityLabel(settings.t("Добавить правило", "Add rule"))
        }) {
            VStack(alignment: .leading, spacing: 12) {
                if settings.rules.isEmpty {
                    Caption(text: settings.t("Правил нет — в режиме «Правила» весь трафик пойдёт через VPN.",
                                             "No rules — in Rules mode all traffic goes through the VPN."))
                        .padding(.horizontal, 4)
                } else {
                    GroupCard {
                        ForEach(Array(settings.rules.enumerated()), id: \.element.id) { index, rule in
                            if index > 0 { RowDivider(leading: 16) }
                            Button {
                                editing = rule
                            } label: {
                                RuleRow(rule: rule)
                            }
                            .buttonStyle(RowPressStyle())
                            .contextMenu { menu(for: rule, at: index) }
                        }
                    }
                }

                Caption(text: settings.t("Правила проверяются сверху вниз, срабатывает первое совпадение. Удержите правило, чтобы переместить или удалить. iOS не даёт VPN-приложениям направлять трафик по приложениям — только по доменам и IP.",
                                         "Rules are checked top to bottom; the first match wins. Long-press a rule to move or delete it. iOS doesn't let VPN apps route per app — only by domain and IP."))
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                if settings.prefs.mode != .rules {
                    Caption(text: settings.t("Сейчас включён режим «\(settings.prefs.mode.title(.ru))» — правила не применяются.",
                                             "Mode is set to \(settings.prefs.mode.title(.en)) — rules are not applied."))
                        .padding(.horizontal, 4)
                }
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, isNew: false) { updated in
                if let i = settings.rules.firstIndex(where: { $0.id == updated.id }) {
                    settings.rules[i] = updated
                }
            } onDelete: {
                delete(rule)
            }
            .environment(settings)
            .tint(settings.accentColor)
            .fontDesign(settings.fontDesign)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $creating) {
            RuleEditor(rule: RouteRule(kind: .suffix, value: "", action: .proxy), isNew: true) { rule in
                withAnimation(Motion.spring) { settings.rules.insert(rule, at: 0) }
            }
            .environment(settings)
            .tint(settings.accentColor)
            .fontDesign(settings.fontDesign)
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func menu(for rule: RouteRule, at index: Int) -> some View {
        if index > 0 {
            Button {
                move(rule, by: -1)
            } label: {
                Label(settings.t("Выше", "Move up"), systemImage: "arrow.up")
            }
        }
        if index < settings.rules.count - 1 {
            Button {
                move(rule, by: 1)
            } label: {
                Label(settings.t("Ниже", "Move down"), systemImage: "arrow.down")
            }
        }
        Button(role: .destructive) {
            delete(rule)
        } label: {
            Label(settings.t("Удалить", "Delete"), systemImage: "trash")
        }
    }

    private func move(_ rule: RouteRule, by offset: Int) {
        guard let i = settings.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let j = i + offset
        guard settings.rules.indices.contains(j) else { return }
        Haptics.select()
        withAnimation(Motion.spring) { settings.rules.swapAt(i, j) }
    }

    private func delete(_ rule: RouteRule) {
        Haptics.rigid()
        withAnimation(Motion.spring) { settings.rules.removeAll { $0.id == rule.id } }
    }
}

private struct RuleRow: View {
    let rule: RouteRule

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.value)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rule.kind.title(settings.lang))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            ActionPill(action: rule.action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

struct ActionPill: View {
    let action: RouteRule.Action

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Text(action.title(settings.lang))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private var color: Color {
        switch action {
        case .proxy: return settings.accentColor
        case .direct: return Ink.secondary
        case .block: return PingColor.bad.color
        }
    }
}

/// Add / edit a single rule.
struct RuleEditor: View {
    let isNew: Bool
    let onSave: (RouteRule) -> Void
    var onDelete: (() -> Void)?

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RouteRule
    @FocusState private var valueFocused: Bool

    init(rule: RouteRule, isNew: Bool, onSave: @escaping (RouteRule) -> Void, onDelete: (() -> Void)? = nil) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: rule)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(settings.t("Тип", "Type"), selection: $draft.kind) {
                        ForEach(RouteRule.Kind.allCases) { kind in
                            Text(kind.title(settings.lang)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField(prompt, text: $draft.value)
                        .font(.system(size: 16, design: .monospaced))
                        .keyboardType(draft.kind == .ip ? .numbersAndPunctuation : .URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($valueFocused)
                } footer: {
                    Text(hint)
                }
                .listRowBackground(settings.elevatedColor)

                Section {
                    Picker(settings.t("Действие", "Action"), selection: $draft.action) {
                        ForEach(RouteRule.Action.allCases) { action in
                            Text(action.title(settings.lang)).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(settings.t("Действие", "Action"))
                }
                .listRowBackground(settings.elevatedColor)

                if !isNew, let onDelete {
                    Section {
                        Button(settings.t("Удалить правило", "Delete rule"), role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(settings.elevatedColor)
                }
            }
            .scrollContentBackground(.hidden)
            .background(settings.surfaceColor.ignoresSafeArea())
            .navigationTitle(isNew ? settings.t("Новое правило", "New rule") : settings.t("Правило", "Rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? settings.t("Добавить", "Add") : settings.t("Готово", "Done")) { save() }
                        .fontWeight(.semibold)
                        .disabled(normalized.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(settings.surfaceColor)
        .onAppear { valueFocused = isNew }
    }

    private var normalized: String {
        let v = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.kind == .ip ? v : v.lowercased()
    }

    private var prompt: String {
        switch draft.kind {
        case .domain: return "example.com"
        case .suffix: return ".example.com"
        case .keyword: return "google"
        case .ip: return "10.0.0.0/8"
        case .geosite: return "category-ads-all"
        case .geoip: return "ru"
        }
    }

    private var hint: String {
        switch draft.kind {
        case .domain: return settings.t("Только этот домен, без поддоменов.", "This exact domain only.")
        case .suffix: return settings.t("Домен и все его поддомены.", "The domain and all its subdomains.")
        case .keyword: return settings.t("Любой домен, в котором есть это слово.", "Any domain containing the word.")
        case .ip: return settings.t("Адрес или подсеть в формате CIDR.", "An address or a CIDR subnet.")
        case .geosite: return settings.t("Категория из базы geosite: ru, google, category-ads-all…", "A geosite category: ru, google, category-ads-all…")
        case .geoip: return settings.t("Код страны или private для локальной сети.", "A country code, or private for the local network.")
        }
    }

    private func save() {
        guard !normalized.isEmpty else { return }
        var rule = draft
        rule.value = normalized
        Haptics.success()
        onSave(rule)
        dismiss()
    }
}
