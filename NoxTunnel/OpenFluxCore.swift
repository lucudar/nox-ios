import Foundation
import Libbox

/// The OpenFlux client compiled into the core (core/noxflux). For OpenFlux servers the app sends
/// openflux.json along with the sing-box config; the extension starts the client from it before
/// sing-box, which reaches it through a SOCKS5 port on 127.0.0.1. Without it the client is stopped.
enum OpenFluxCore {
    /// Starts, reconfigures or stops the client to match `config` (openflux.json). A new session
    /// has to bring up the service channel and get an answer from the exit node within
    /// `waitMillis`; otherwise the start fails with a readable reason instead of a tunnel that
    /// drops everything.
    static func apply(_ config: String?, waitMillis: Int64) throws {
        guard let text = config, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            stop()
            return
        }
        let generation = NoxfluxGeneration()
        let began = Date()
        var error: NSError?
        guard NoxfluxStart(text, &error) else {
            var reason = error?.localizedDescription ?? "start failed"
            if reason.lowercased().hasPrefix("openflux: ") { reason.removeFirst("openflux: ".count) }
            throw TunnelFailure("OpenFlux: \(reason)")
        }
        // Same server as before: the running session is kept, nothing to check.
        guard NoxfluxGeneration() != generation else { return }
        let words = Words(text)
        // Some services connect inside Start (Yandex Volga, MAX, Cups.online): the probe gets the rest.
        let spent = Int64(Date().timeIntervalSince(began) * 1000)
        switch Int64(NoxfluxProbe(max(waitMillis - spent, 5_000))) {
        case NoxfluxProbeOK:
            return
        case NoxfluxProbeNoTransport:
            stop()
            throw TunnelFailure(words.noChannel)
        case NoxfluxProbeExitSilent:
            stop()
            throw TunnelFailure(words.exitSilent)
        default:
            throw TunnelFailure("OpenFlux: the client stopped")
        }
    }

    static func stop() {
        if NoxfluxIsRunning() { NoxfluxStop() }
    }

    /// Error texts in the app's language (the extension has no L10n): openflux.json carries
    /// "lang" and the service name.
    private struct Words {
        let ru: Bool
        let service: String

        init(_ json: String) {
            let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
            ru = (object["lang"] as? String) == "ru"
            service = object["service"] as? String ?? "OpenFlux"
        }

        var noChannel: String {
            ru ? "OpenFlux: не удалось подключиться к \(service). Проверьте ссылки на документы (для MAX — токен) и интернет."
               : "OpenFlux: couldn't connect to \(service). Check the document links (MAX: the token) and the internet connection."
        }

        var exitSilent: String {
            ru ? "OpenFlux: \(service) на связи, но выходной узел не отвечает. Он должен быть запущен с теми же документами, кодеком и ключом."
               : "OpenFlux: \(service) is reachable, but the exit node doesn't answer. It must run with the same documents, codec and key."
        }
    }
}
