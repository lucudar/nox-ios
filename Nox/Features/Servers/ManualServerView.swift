import SwiftUI

/// "Создать вручную": protocol, address and per-protocol fields → a regular share link /
/// config that goes through the same parser as imported servers.
struct ManualServerView: View {
    let onSave: (Server) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ManualDraft()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(settings.t("Протокол", "Protocol"), selection: $draft.proto) {
                        ForEach(ProxyProtocol.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(settings.elevatedColor)

                serverSection
                parameters
                if draft.proto == .amneziawg { amneziaSection }
                countrySection

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(PingColor.bad.color)
                    }
                    .listRowBackground(settings.elevatedColor)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(settings.surfaceColor.ignoresSafeArea())
            .navigationTitle(settings.t("Новый сервер", "New server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("Сохранить", "Save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!draft.isComplete)
                }
            }
        }
        .presentationBackground(settings.surfaceColor)
        .onChange(of: draft.proto) { old, _ in
            draft.switchProtocol(from: old)
            error = nil
        }
    }

    // MARK: Sections

    private var serverSection: some View {
        Section {
            InputRow(title: settings.t("Название", "Name"), text: $draft.name, prompt: settings.t("Необязательно", "Optional"))
            InputRow(title: settings.t("Адрес", "Address"), text: $draft.host, prompt: "example.com", keyboard: .URL)
            InputRow(title: settings.t("Порт", "Port"), text: $draft.port, prompt: String(draft.proto.defaultPort), keyboard: .numberPad)
        } header: {
            Text(settings.t("Сервер", "Server"))
        } footer: {
            if draft.proto == .openvpn {
                Text(settings.t("Адрес можно не указывать, если в конфиге есть строка remote.",
                                "The address is optional if the config has a remote line."))
            }
        }
        .listRowBackground(settings.elevatedColor)
    }

    @ViewBuilder
    private var parameters: some View {
        switch draft.proto {
        case .vless: vlessSection
        case .vmess: vmessSection
        case .trojan: trojanSection
        case .shadowsocks: shadowsocksSection
        case .hysteria2: hysteriaSection
        case .tuic: tuicSection
        case .wireguard, .amneziawg: wireguardSection
        case .openvpn: openVPNSection
        case .ikev2, .ssh: loginSection
        case .openflux, .custom: tokenSection
        }
    }

    private var vlessSection: some View {
        Section {
            InputRow(title: "UUID", text: $draft.uuid, prompt: "xxxxxxxx-xxxx-…", mono: true)
            Picker(settings.t("Защита", "Security"), selection: $draft.security) {
                ForEach(ManualDraft.Security.allCases) { s in
                    Text(s == .none ? settings.t("Нет", "None") : s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            if draft.security != .none {
                InputRow(title: "SNI", text: $draft.sni, prompt: "www.example.com", keyboard: .URL)
            }
            if draft.security == .reality {
                InputRow(title: "Public key", text: $draft.publicKey, prompt: "pbk", mono: true)
                InputRow(title: "Short ID", text: $draft.shortID, prompt: settings.t("Необязательно", "Optional"), mono: true)
            }
            if draft.security != .none {
                fingerprintPicker
            }
            transportRows
            if draft.transport == .tcp, draft.security != .none {
                Toggle("Vision (xtls-rprx-vision)", isOn: $draft.vision)
            }
        } header: {
            Text("VLESS")
        } footer: {
            if draft.security == .reality {
                Text(settings.t("Public key (pbk), Short ID и SNI берутся из настроек Reality на сервере.",
                                "Public key (pbk), Short ID and SNI come from the server's Reality settings."))
            }
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var vmessSection: some View {
        Section {
            InputRow(title: "UUID", text: $draft.uuid, prompt: "xxxxxxxx-xxxx-…", mono: true)
            transportRows
            Toggle("TLS", isOn: $draft.vmessTLS)
            if draft.vmessTLS {
                InputRow(title: "SNI", text: $draft.sni, prompt: settings.t("Необязательно", "Optional"), keyboard: .URL)
            }
        } header: {
            Text("VMess")
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var trojanSection: some View {
        Section {
            SecretRow(title: settings.t("Пароль", "Password"), text: $draft.password)
            InputRow(title: "SNI", text: $draft.sni, prompt: settings.t("Необязательно", "Optional"), keyboard: .URL)
            transportRows
            insecureToggle
        } header: {
            Text("Trojan")
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var shadowsocksSection: some View {
        Section {
            Picker(settings.t("Шифрование", "Cipher"), selection: $draft.method) {
                ForEach(ManualDraft.ssMethods, id: \.self) { m in
                    Text(m).tag(m)
                }
            }
            .pickerStyle(.menu)
            SecretRow(title: settings.t("Пароль", "Password"), text: $draft.password)
        } header: {
            Text("Shadowsocks")
        } footer: {
            if draft.method.hasPrefix("2022-") {
                Text(settings.t("Для 2022-шифров пароль — ключ в base64 нужной длины.",
                                "For 2022 ciphers the password is a base64 key of the right length."))
            }
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var hysteriaSection: some View {
        Section {
            SecretRow(title: settings.t("Пароль", "Password"), text: $draft.password)
            InputRow(title: "SNI", text: $draft.sni, prompt: settings.t("Необязательно", "Optional"), keyboard: .URL)
            InputRow(title: "Obfs", text: $draft.obfsPassword, prompt: settings.t("Пароль salamander", "Salamander password"))
            insecureToggle
        } header: {
            Text("Hysteria2")
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var tuicSection: some View {
        Section {
            InputRow(title: "UUID", text: $draft.uuid, prompt: "xxxxxxxx-xxxx-…", mono: true)
            SecretRow(title: settings.t("Пароль", "Password"), text: $draft.password)
            InputRow(title: "SNI", text: $draft.sni, prompt: settings.t("Необязательно", "Optional"), keyboard: .URL)
            insecureToggle
        } header: {
            Text("TUIC v5")
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var wireguardSection: some View {
        Section {
            InputRow(title: settings.t("Приватный ключ", "Private key"), text: $draft.privateKey, prompt: "base64", mono: true)
            InputRow(title: settings.t("Адрес в сети", "Tunnel address"), text: $draft.address, prompt: "10.0.0.2/32", keyboard: .numbersAndPunctuation)
            InputRow(title: "DNS", text: $draft.dns, prompt: "1.1.1.1", keyboard: .numbersAndPunctuation)
            InputRow(title: settings.t("Публичный ключ пира", "Peer public key"), text: $draft.peerPublicKey, prompt: "base64", mono: true)
            InputRow(title: "Preshared key", text: $draft.presharedKey, prompt: settings.t("Необязательно", "Optional"), mono: true)
        } header: {
            Text(draft.proto.title)
        } footer: {
            Text(settings.t("Ключи в base64 — как в .conf-файле. Готовый файл проще импортировать через «Из файла».",
                            "Keys are base64, as in a .conf file. A ready file is easier to import via From file."))
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var amneziaSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(ManualDraft.awgKeys, id: \.self) { key in
                    VStack(spacing: 4) {
                        Text(key)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Ink.secondary)
                        TextField(ManualDraft.awgDefaults[key] ?? "0", text: Binding(
                            get: { draft.awg[key] ?? "" },
                            set: { draft.awg[key] = $0 }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, design: .monospaced))
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(settings.surfaceColor))
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text(settings.t("Параметры AmneziaWG", "AmneziaWG parameters"))
        } footer: {
            Text(settings.t("Должны совпадать с настройками сервера.", "Must match the server settings."))
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var openVPNSection: some View {
        Section {
            ConfigEditor(text: $draft.config, placeholder: "client\ndev tun\nremote vpn.example.com 1194\n<ca>…</ca>")
            InputRow(title: settings.t("Логин", "Login"), text: $draft.user, prompt: settings.t("Необязательно", "Optional"))
            SecretRow(title: settings.t("Пароль", "Password"), text: $draft.password)
        } header: {
            HStack {
                Text(settings.t("Конфигурация .ovpn", ".ovpn config"))
                Spacer()
                pasteButton
            }
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var loginSection: some View {
        Section {
            InputRow(title: settings.t("Пользователь", "User"), text: $draft.user, prompt: settings.t("Логин", "Login"))
            SecretRow(title: settings.t("Пароль", "Password"), text: $draft.password)
        } header: {
            Text(draft.proto.title)
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var tokenSection: some View {
        Section {
            if draft.proto == .custom {
                InputRow(title: settings.t("Схема ссылки", "Link scheme"), text: $draft.scheme, prompt: "myproto", mono: true)
            }
            InputRow(title: settings.t("Ключ / токен", "Key / token"), text: $draft.token, prompt: draft.proto == .custom ? settings.t("Необязательно", "Optional") : "", mono: true)
            ConfigEditor(text: $draft.config, placeholder: settings.t("Конфигурация (необязательно)", "Config (optional)"))
        } header: {
            HStack {
                Text(draft.proto.title)
                Spacer()
                pasteButton
            }
        } footer: {
            Text(draft.proto == .custom
                 ? settings.t("Получится ссылка вида схема://ключ@адрес:порт. Конфигурация сохраняется как есть.",
                              "Produces a scheme://key@address:port link. The config is stored as is.")
                 : settings.t("Ключ выдаёт сервер OpenFlux. Конфигурация сохраняется как есть.",
                              "The key comes from the OpenFlux server. The config is stored as is."))
        }
        .listRowBackground(settings.elevatedColor)
    }

    private var countrySection: some View {
        Section {
            Picker(settings.t("Страна", "Country"), selection: $draft.country) {
                Text(settings.t("Определить автоматически", "Detect automatically")).tag("")
                ForEach(Countries.sortedCodes(settings.lang), id: \.self) { code in
                    Text("\(Countries.flagEmoji(code))  \(Countries.name(code, settings.lang) ?? code)").tag(code)
                }
            }
            .pickerStyle(.navigationLink)
        } footer: {
            Text(settings.t("Автоматически — по названию и адресу. Флаг показывается в списке серверов.",
                            "Detected from the name and address. The flag is shown in the server list."))
        }
        .listRowBackground(settings.elevatedColor)
    }

    // MARK: Shared rows

    @ViewBuilder
    private var transportRows: some View {
        Picker(settings.t("Транспорт", "Transport"), selection: $draft.transport) {
            ForEach(ManualDraft.Transport.allCases) { t in
                Text(t.title).tag(t)
            }
        }
        .pickerStyle(.segmented)
        switch draft.transport {
        case .tcp:
            EmptyView()
        case .ws:
            InputRow(title: settings.t("Путь", "Path"), text: $draft.path, prompt: "/", mono: true)
        case .grpc:
            InputRow(title: "serviceName", text: $draft.path, prompt: "grpc", mono: true)
        }
    }

    private var fingerprintPicker: some View {
        Picker("Fingerprint", selection: $draft.fingerprint) {
            ForEach(ManualDraft.fingerprints, id: \.self) { f in
                Text(f).tag(f)
            }
        }
        .pickerStyle(.menu)
    }

    private var insecureToggle: some View {
        Toggle(settings.t("Самоподписанный сертификат", "Self-signed certificate"), isOn: $draft.insecure)
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            guard let text = strings.first else { return }
            draft.config = text
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
    }

    // MARK: Save

    private func save() {
        guard draft.isComplete else { return }
        guard let server = draft.build() else {
            Haptics.error()
            withAnimation(Motion.spring) {
                error = settings.t("Не получилось собрать конфигурацию — проверьте адрес и ключи.",
                                   "Couldn't build the config — check the address and keys.")
            }
            return
        }
        onSave(server)
        dismiss()
    }
}

// MARK: - Rows

/// Short values: "Title ········ value". Long ones (keys, UUID) go under the title in mono.
private struct InputRow: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    var mono = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        if mono {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.secondary)
                field
                    .font(.system(size: 15, design: .monospaced))
            }
            .padding(.vertical, 3)
        } else {
            LabeledContent(title) {
                field
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var field: some View {
        TextField(prompt, text: $text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
    }
}

/// Password with a show / hide eye.
private struct SecretRow: View {
    let title: String
    @Binding var text: String

    @State private var revealed = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Group {
                    if revealed {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Multiline monospaced editor for raw configs.
private struct ConfigEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 140)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Ink.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }
}
