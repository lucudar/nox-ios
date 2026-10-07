import SwiftUI

/// "Подписка по ссылке": URL + optional name → fetch, parse, add as a group.
struct AddSubscriptionView: View {
    var initialURL = ""
    let onAdded: (Int) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(ServerStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var name = ""
    @State private var loading = false
    @State private var error: String?
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $url, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, design: .monospaced))
                        .focused($urlFocused)
                    TextField(settings.t("Название (необязательно)", "Name (optional)"), text: $name)
                } header: {
                    Text(settings.t("Ссылка на подписку", "Subscription URL"))
                } footer: {
                    Text(settings.t("Подойдут base64-подписки, списки ссылок, sing-box / Xray JSON и Clash YAML. Обновить можно из шторки — нажмите на время обновления.",
                                    "Works with base64 subscriptions, link lists, sing-box / Xray JSON and Clash YAML. Refresh it from the sheet by tapping the update time."))
                }
                .listRowBackground(settings.elevatedColor)

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(PingColor.bad.color)
                    }
                    .listRowBackground(settings.elevatedColor)
                }
            }
            .scrollContentBackground(.hidden)
            .background(settings.surfaceColor.ignoresSafeArea())
            .navigationTitle(settings.t("Подписка", "Subscription"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if loading {
                        ProgressView()
                    } else {
                        Button(settings.t("Добавить", "Add")) { add() }
                            .fontWeight(.semibold)
                            .disabled(parsedURL == nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(settings.surfaceColor)
        .onAppear {
            url = initialURL
            urlFocused = initialURL.isEmpty
        }
    }

    private var parsedURL: URL? {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: text), let scheme = u.scheme?.lowercased(),
              scheme == "https" || scheme == "http", u.host != nil else { return nil }
        return u
    }

    private func add() {
        guard let link = parsedURL else { return }
        loading = true
        error = nil
        Task {
            do {
                let count = try await servers.addSubscription(url: link, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                loading = false
                onAdded(count)
                dismiss()
            } catch {
                loading = false
                Haptics.error()
                self.error = error.localizedDescription
            }
        }
    }
}
