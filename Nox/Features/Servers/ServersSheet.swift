import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Bottom sheet with the server list: header (Ping, +), Auto, subscription groups and own servers.
struct ServersSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ServerStore.self) private var servers
    @Environment(ConnectionManager.self) private var connection
    @Environment(StatsStore.self) private var stats
    @Environment(BackgroundPhoto.self) private var photo
    @Environment(\.dismiss) private var dismiss

    @State private var menuOpen = false
    @State private var clipboardHint: String?
    @State private var showScanner = false
    @State private var showImporter = false
    @State private var showSubscription = false
    @State private var subscriptionPrefill = ""
    @State private var showManual = false
    @State private var renameTarget: Server?
    @State private var renameText = ""
    @State private var deleteGroupTarget: ServerGroup?
    @State private var refreshing: Set<UUID> = []
    @State private var pingDone = false
    @State private var toast: Toast?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    autoRow
                    ForEach(servers.groups) { group in
                        groupSection(group)
                    }
                    if servers.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 8)
        .overlay {
            if menuOpen {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { setMenu(false) }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                plusButton
                if menuOpen {
                    AddMenu(clipboardHint: clipboardHint,
                            onPaste: paste,
                            onScan: { afterMenu { showScanner = true } },
                            onFile: { afterMenu { showImporter = true } },
                            onSubscription: { afterMenu { subscriptionPrefill = ""; showSubscription = true } },
                            onManual: { afterMenu { showManual = true } })
                        .transition(.scale(scale: 0.86, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .padding(.top, 30)
            .padding(.trailing, 20)
        }
        .toast($toast)
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { code in
                showScanner = false
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    handleImport(code, fileName: nil)
                }
            }
            .environment(settings)
            .preferredColorScheme(.dark)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            importFile(result)
        }
        .sheet(isPresented: $showSubscription) {
            AddSubscriptionView(initialURL: subscriptionPrefill) { count in
                Haptics.success()
                toast = Toast(text: settings.t("Подписка добавлена · \(count)", "Subscription added · \(count)"))
            }
            .environment(settings)
            .environment(servers)
            .tint(settings.accentColor)
            .fontDesign(settings.fontDesign)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showManual) {
            ManualServerView { server in
                let added = servers.addOwn([server])
                if added > 0 {
                    Haptics.success()
                    toast = Toast(text: settings.t("Сервер добавлен", "Server added"))
                } else {
                    toast = Toast(text: settings.t("Такой сервер уже есть", "This server already exists"), isError: true)
                }
            }
            .environment(settings)
            .tint(settings.accentColor)
            .fontDesign(settings.fontDesign)
            .preferredColorScheme(.dark)
        }
        .alert(settings.t("Название сервера", "Server name"), isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(settings.t("Название", "Name"), text: $renameText)
            Button(settings.t("Сохранить", "Save")) {
                if let target = renameTarget {
                    servers.rename(target.id, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                renameTarget = nil
            }
            Button(settings.t("Отмена", "Cancel"), role: .cancel) { renameTarget = nil }
        } message: {
            Text(settings.t("Пустое название — показывать страну", "Leave empty to show the country"))
        }
        .confirmationDialog(settings.t("Удалить подписку?", "Delete subscription?"), isPresented: Binding(
            get: { deleteGroupTarget != nil },
            set: { if !$0 { deleteGroupTarget = nil } }
        ), titleVisibility: .visible) {
            Button(settings.t("Удалить", "Delete"), role: .destructive) {
                if let group = deleteGroupTarget {
                    withAnimation(Motion.spring) { servers.deleteGroup(group.id) }
                }
                deleteGroupTarget = nil
            }
        }
        .onChange(of: servers.pingFinishedAt) { _, value in
            guard value != nil else { return }
            Haptics.success()
            pingDone = true
        }
        .task(id: pingDone) {
            guard pingDone else { return }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            pingDone = false
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(settings.t("Серверы", "Servers"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Ink.primary)
            Spacer(minLength: 8)
            PingCapsule(pinging: servers.isPinging, done: pingDone) {
                Haptics.tap()
                Task { await servers.pingAll() }
            }
            .opacity(servers.isEmpty ? 0.4 : 1)
            .disabled(servers.isEmpty)
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private var plusButton: some View {
        Button {
            Haptics.tap()
            setMenu(!menuOpen)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Ink.primary)
                .rotationEffect(.degrees(menuOpen ? 45 : 0))
                .frame(width: 36, height: 36)
                .background(Circle().fill(settings.elevatedColor))
                .overlay(Circle().strokeBorder(Ink.stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(menuOpen ? settings.t("Закрыть", "Close") : settings.t("Добавить", "Add"))
    }

    // MARK: Auto

    private var autoRow: some View {
        HStack(spacing: 14) {
            BadgeDisc(kind: .auto, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.t("Авто", "Auto"))
                    .font(.system(size: 17))
                    .foregroundStyle(Ink.primary)
                Text(settings.t("Самый быстрый", "Fastest") + " · " + (servers.best?.place(settings.lang) ?? "—"))
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { servers.autoSelect },
                set: { on in
                    Haptics.select()
                    withAnimation(Motion.spring) { servers.setAutoSelect(on) }
                    if on, servers.best == nil { Task { await servers.pingAll() } }
                }
            ))
            .labelsHidden()
            .tint(settings.accentColor)
        }
        .padding(.vertical, 10)
    }

    // MARK: Groups

    private func groupSection(_ group: ServerGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if group.isOwn {
                groupHeader(group)
            } else {
                groupHeader(group)
                    .contextMenu {
                        Button {
                            refresh(group)
                        } label: {
                            Label(settings.t("Обновить", "Refresh"), systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            deleteGroupTarget = group
                        } label: {
                            Label(settings.t("Удалить подписку", "Delete subscription"), systemImage: "trash")
                        }
                    }
            }
            ForEach(Array(group.servers.enumerated()), id: \.element.id) { index, server in
                ServerRow(server: server,
                          selected: !servers.autoSelect && servers.selected?.id == server.id,
                          pending: servers.pending.contains(server.id)) {
                    select(server)
                }
                .contextMenu { rowMenu(server, own: group.isOwn) }
                if index < group.servers.count - 1 {
                    RowDivider(leading: 44)
                }
            }
        }
    }

    private func groupHeader(_ group: ServerGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.title(settings.lang))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ink.secondary)
            Spacer(minLength: 8)
            if !group.isOwn {
                Button {
                    refresh(group)
                } label: {
                    HStack(spacing: 6) {
                        if refreshing.contains(group.id) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Ink.secondary)
                        }
                        Text(group.updatedAt.map { Fmt.relative($0, settings.lang) } ?? settings.t("обновить", "refresh"))
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowMenu(_ server: Server, own: Bool) -> some View {
        Button {
            Task { await servers.ping(server.id) }
        } label: {
            Label(settings.t("Пинг", "Ping"), systemImage: "speedometer")
        }
        Button {
            renameText = server.name
            renameTarget = server
        } label: {
            Label(settings.t("Переименовать", "Rename"), systemImage: "pencil")
        }
        if !server.link.isEmpty {
            Button {
                UIPasteboard.general.string = server.link
                toast = Toast(text: settings.t("Скопировано", "Copied"))
            } label: {
                Label(settings.t("Скопировать ссылку", "Copy link"), systemImage: "doc.on.doc")
            }
        }
        if own {
            Button(role: .destructive) {
                withAnimation(Motion.spring) { servers.delete(server.id) }
            } label: {
                Label(settings.t("Удалить", "Delete"), systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(settings.accentColor)
            Text(settings.t("Пока нет серверов", "No servers yet"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.primary)
            Text(settings.t("Нажмите «+», чтобы вставить ссылку, отсканировать QR, импортировать файл или подписку.",
                            "Tap “+” to paste a link, scan a QR code, import a file or a subscription."))
                .font(.system(size: 14))
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: Actions

    private func select(_ server: Server) {
        Haptics.select()
        withAnimation(Motion.spring) { servers.select(server.id) }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            dismiss()
        }
    }

    private func refresh(_ group: ServerGroup) {
        guard !refreshing.contains(group.id) else { return }
        refreshing.insert(group.id)
        Task {
            do {
                try await servers.refresh(group.id)
                toast = Toast(text: settings.t("Подписка обновлена", "Subscription updated"))
            } catch {
                toast = Toast(text: error.localizedDescription, isError: true)
            }
            refreshing.remove(group.id)
        }
    }

    private func setMenu(_ open: Bool) {
        if open { clipboardHint = ClipboardPeek.hint() }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { menuOpen = open }
    }

    /// Close the menu, then run the action (a sheet can't open while the menu animates).
    private func afterMenu(_ action: @escaping () -> Void) {
        setMenu(false)
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            action()
        }
    }

    private func paste() {
        setMenu(false)
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            Haptics.error()
            toast = Toast(text: settings.t("В буфере ничего нет", "The clipboard is empty"), isError: true)
            return
        }
        ClipboardPeek.remember(text)
        handleImport(text, fileName: nil)
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            toast = Toast(text: settings.t("Не удалось прочитать файл", "Couldn't read the file"), isError: true)
            return
        }
        handleImport(text, fileName: url.lastPathComponent)
    }

    private func handleImport(_ text: String, fileName: String?) {
        switch servers.importText(text, fileName: fileName) {
        case .added(let count):
            Haptics.success()
            toast = Toast(text: settings.t("Добавлено: \(count)", "Added: \(count)"))
        case .duplicates:
            toast = Toast(text: settings.t("Уже есть в списке", "Already in the list"))
        case .subscription(let url):
            subscriptionPrefill = url.absoluteString
            showSubscription = true
        case .nothing:
            Haptics.error()
            toast = Toast(text: settings.t("Не нашёл ссылок или конфигов", "No links or configs found"), isError: true)
        }
    }
}

// MARK: - Clipboard preview without the iOS paste prompt

/// Reading the pasteboard shows a system prompt, so the menu only shows what Nox itself pasted
/// last time (if the clipboard hasn't changed since) or a neutral hint.
@MainActor
enum ClipboardPeek {
    private static var changeCount = -1
    private static var preview: String?

    static func hint() -> String? {
        let board = UIPasteboard.general
        if board.changeCount == changeCount, let preview { return preview }
        return board.hasStrings ? "vless:// · ss:// · hy2:// …" : nil
    }

    static func remember(_ text: String) {
        changeCount = UIPasteboard.general.changeCount
        preview = shorten(text)
    }

    /// "vless://a3f9…@nl-ams-2"
    static func shorten(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        if let r = line.range(of: "://") {
            let scheme = line[..<r.lowerBound]
            let rest = line[r.upperBound...]
            let parts = rest.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                let host = parts[1].split(whereSeparator: { ":/?#".contains($0) }).first.map(String.init) ?? ""
                let shortHost = host.split(separator: ".").first.map(String.init) ?? host
                return "\(scheme)://\(parts[0].prefix(4))…@\(shortHost)"
            }
        }
        return line.count > 30 ? String(line.prefix(30)) + "…" : line
    }
}

// MARK: - Header pieces

struct PingCapsule: View {
    let pinging: Bool
    let done: Bool
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let active = pinging || done
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else {
                        GaugeGlyph(color: active ? settings.accentColor : Ink.primary, swinging: pinging)
                            .transition(.opacity)
                    }
                }
                .frame(width: 16, height: 16)
                Text(settings.t("Пинг", "Ping"))
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(active ? settings.accentColor : Ink.primary)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Capsule().fill(active ? settings.accent.color(0.13) : settings.elevatedColor))
            .overlay(Capsule().strokeBorder(active ? settings.accent.color(0.3) : Ink.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .allowsHitTesting(!pinging)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: done)
        .animation(.easeOut(duration: 0.2), value: pinging)
        .accessibilityLabel(settings.t("Проверить пинг", "Check ping"))
    }
}

// MARK: - Row

struct ServerRow: View {
    let server: Server
    let selected: Bool
    let pending: Bool
    let action: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ServerAvatar(server: server, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName(settings.lang))
                        .font(.system(size: 17))
                        .foregroundStyle(Ink.primary)
                    Text(server.subtitle(settings.lang))
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                ZStack(alignment: .trailing) {
                    if pending {
                        ShimmerBar(width: 40, height: 10, tint: settings.accentColor)
                            .transition(.opacity)
                    } else {
                        PingText(server: server)
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                    }
                }
                .frame(minWidth: 56, alignment: .trailing)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(settings.accentColor)
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.5)
                    .frame(width: 18)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .animation(.easeOut(duration: 0.25), value: pending)
        .animation(Motion.bouncy, value: selected)
    }
}

// MARK: - "+" menu

struct AddMenu: View {
    let clipboardHint: String?
    let onPaste: () -> Void
    let onScan: () -> Void
    let onFile: () -> Void
    let onSubscription: () -> Void
    let onManual: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 0) {
            item(settings.t("Вставить из буфера", "Paste from clipboard"), subtitle: clipboardHint, mono: true,
                 icon: "doc.on.clipboard", action: onPaste)
            RowDivider()
            item(settings.t("Сканировать QR-код", "Scan QR code"), icon: "qrcode.viewfinder", action: onScan)
            RowDivider()
            item(settings.t("Импорт файла", "Import file"), icon: "doc", action: onFile)
            RowDivider()
            item(settings.t("Подписка по ссылке", "Subscription URL"), icon: "link", action: onSubscription)
            Rectangle()
                .fill(Color.black.opacity(0.32))
                .frame(height: 8)
            item(settings.t("Создать вручную", "Create manually"), subtitle: "VLESS, WireGuard, OpenFlux…",
                 icon: "pencil", action: onManual)
        }
        .frame(width: 272)
        .background(shape.fill(settings.elevatedColor))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
    }

    private func item(_ title: String, subtitle: String? = nil, mono: Bool = false, icon: String,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(Ink.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(mono ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13))
                            .foregroundStyle(mono ? settings.accentColor : Ink.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 24)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .padding(.vertical, subtitle == nil ? 0 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
