import SwiftUI

struct DNSView: View {
    @Environment(AppSettings.self) private var settings
    @FocusState private var customFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        Screen(title: "DNS") {
            VStack(alignment: .leading, spacing: 12) {
                SlidingSegmented(options: DNSTransport.allCases, selection: $settings.prefs.dnsTransport) { $0.title }
                Caption(text: transportNote)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)

                GroupCard {
                    ForEach(Array(DNSPreset.allCases.enumerated()), id: \.element) { index, preset in
                        if index > 0 { RowDivider(leading: 16) }
                        CheckRow(title: preset.title(settings.lang),
                                 subtitle: preset == .custom ? nil : preset.endpoint(settings.prefs.dnsTransport),
                                 selected: settings.prefs.dnsPreset == preset) {
                            guard settings.prefs.dnsPreset != preset else { return }
                            Haptics.select()
                            withAnimation(Motion.spring) { settings.prefs.dnsPreset = preset }
                            if preset == .custom { customFocused = true }
                        }
                    }
                }

                if settings.prefs.dnsPreset == .custom {
                    GroupCard {
                        TextField(customPrompt, text: $settings.prefs.customDNS)
                            .font(.system(size: 16, design: .monospaced))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($customFocused)
                            .submitLabel(.done)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Caption(text: settings.t("DNS-запросы идут внутри туннеля — провайдер их не видит.",
                                         "DNS queries go inside the tunnel, so your ISP can't see them."))
                    .padding(.horizontal, 4)
            }
        }
    }

    private var transportNote: String {
        switch settings.prefs.dnsTransport {
        case .doh: return settings.t("DNS поверх HTTPS — запросы выглядят как обычный веб-трафик.",
                                     "DNS over HTTPS — queries look like regular web traffic.")
        case .dot: return settings.t("DNS поверх TLS, порт 853.", "DNS over TLS, port 853.")
        case .udp: return settings.t("Обычный DNS без шифрования — быстрее, но заметнее.",
                                     "Plain DNS without encryption — faster, but visible.")
        }
    }

    private var customPrompt: String {
        switch settings.prefs.dnsTransport {
        case .doh: return "https://dns.example.com/dns-query"
        case .dot: return "dns.example.com"
        case .udp: return "1.1.1.1"
        }
    }
}
