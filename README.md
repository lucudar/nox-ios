# Nox — VPN-клиент для iOS

Nox — VPN/прокси-клиент для iPhone на SwiftUI (iOS 17+). Внутри — настоящий туннель: расширение **Packet Tunnel** с ядром **sing-box 1.14** (libbox). Серверы из подписок, ссылок, QR-кодов и файлов, маршрутизация с готовыми пресетами, статистика реального трафика и гибкое оформление.

## Что умеет

- **Главный экран** — большая кнопка подключения, статус, таймер, скорость, внешний IP и страна выхода, задержка. Внизу две кнопки: **Серверы** и **Настройки**.
- **Серверы** — подписки по URL, импорт ссылкой, из буфера обмена, по QR-коду (камера или фото) и из файла, ручное добавление, TCP-пинг в обход туннеля, автовыбор лучшего сервера, группы. Смена сервера при включённом VPN — без разрыва туннеля (горячая перезагрузка ядра).
  - Ссылки: `vless://` (в том числе REALITY), `vmess://`, `trojan://`, `ss://` (включая 2022), `hysteria2://` / `hy2://`, `tuic://`, `wireguard://` / `wg://`, `ssh://` и другие.
  - Файлы: подписки (обычные и base64), конфиги sing-box и Xray (JSON), Clash (YAML), WireGuard `.conf`, OpenVPN `.ovpn`.
- **Маршрутизация** — готовые пресеты, которые работают из коробки:
  - **Россия напрямую** — российские сайты (`.ru`, `.рф`, geosite `category-ru`) и российские IP идут напрямую, остальное через VPN; заблокированное в РФ — всегда через VPN.
  - **Только заблокированное** — через VPN только то, что заблокировано или замедлено в РФ (списки itdoginfo/allow-domains: YouTube, Instagram, Discord, ChatGPT, Telegram и др.), остальное напрямую.
  - **Всё через VPN** — весь трафик, кроме локальной сети.
  - **Только мои правила** — всё напрямую, кроме ваших правил.
  - Плюс блокировка рекламы (geosite `category-ads-all`) и **свои правила**: домен, суффикс, ключевое слово, IP/CIDR, `geosite:*`, `geoip:*` → VPN / напрямую / блок.
  - Списки правил вшиты в приложение (первое подключение работает сразу) и обновляются ядром раз в сутки.
- **DNS** — Cloudflare, Google, Quad9, AdGuard или свой; DoH / DoT / UDP, без утечек (DNS через туннель, российские домены — через локальный DNS в пресетах с прямым трафиком).
- **Kill switch** (весь трафик только через туннель) и **автоподключение** (VPN On Demand).
- **Статистика** — реальный трафик и время подключения по часам за день, неделю и месяц, топ стран и средняя задержка.
- **Логи** — логи приложения и ядра sing-box, подробный режим.
- **Оформление** — пресеты, акцентный цвет, темы, фоны (в том числе своё фото), свечение, анимация кнопки, шрифт, стиль значков и 4 иконки приложения.

## Как это устроено

```
 Nox.app (SwiftUI)                       App Group: group.<bundle id>                NoxTunnel.appex
 ───────────────────                     ───────────────────────────                 ────────────────────────────
 SingBoxConfig собирает JSON  ──write──▶  config.json                    ──read──▶   PacketTunnelProvider
 SingBoxEngine                            RuleSets/*.srs, cache.db                    └─ libbox CommandServer (sing-box)
  └─ NETunnelProviderManager ─start/stop──────────────────────────────────────────▶      ├─ TUN (fd от NEPacketTunnelFlow)
  └─ sendProviderMessage("reload") ───────────────────────────────────────────────▶      ├─ маршрутизация, DNS, rule-set
 CoreAPI ◀── Clash API 127.0.0.1:19090 (трафик, задержка, соединения) ──────────────      └─ outbound: VLESS/VMess/…/WG
 LogsView ◀── box.log, error.txt ◀──────────────────────────────────────────────────── пишет ядро
```

- `Nox/Tunnel/` — сборка конфигурации sing-box из сервера и настроек (`SingBoxConfig`, `SingBoxOutbound`, `RuleSets`, `OpenVPNConfig`).
- `Nox/Core/SingBoxEngine.swift` — профиль VPN (`NETunnelProviderManager`), старт/стоп, горячая перезагрузка, ошибки ядра. `CoreAPI.swift` — клиент Clash API.
- `NoxTunnel/` — расширение: `PacketTunnelProvider` (запуск libbox) и `PlatformInterface` (TUN, маршруты, DNS, мониторинг сети для sing-box).
- `Shared/AppGroup.swift` — общие пути и сообщения между приложением и расширением.
- В симуляторе Packet Tunnel не работает, поэтому там подключается `DemoTunnelEngine`: он проверяет конфиг и показывает сценарий подключения без туннеля.

Исследование ядер (sing-box, Xray-core, mihomo) и план своего ядра — в [`docs/core-research.md`](docs/core-research.md).

## Как собрать

1. Нужны **macOS**, **Xcode 16+** и **Go 1.26** (`brew install go`).
2. Соберите ядро: `bash tools/build_libbox.sh` → `Frameworks/Libbox.xcframework` (sing-box 1.14.2, ~10–20 минут при первой сборке).
3. Скачайте списки правил: `bash tools/fetch_rulesets.sh` → `Nox/Resources/RuleSets/*.srs` (необязательно: без них ядро скачает списки при первом подключении).
4. Откройте `Nox.xcodeproj`. Проект сгенерирован скриптом `tools/gen_project.py` — правьте настройки в нём и перезапускайте.

### Запуск на iPhone

Network Extension требует **платного аккаунта Apple Developer** (с бесплатным Apple ID приложение установится, но VPN не запустится).

1. В настройках проекта (уровень проекта, не таргета) поменяйте `NOX_BUNDLE_ID` с `com.example.nox` на свой, например `com.yourname.nox`. От него берутся ID приложения, расширения (`.tunnel`) и App Group (`group.<id>`).
2. В **Signing & Capabilities** обоих таргетов (Nox и NoxTunnel) выберите свою команду. Возможности App Groups и Network Extensions → Packet Tunnel уже прописаны в `Config/*.entitlements`.
3. Запустите на устройстве (**⌘R**) и разрешите добавление конфигурации VPN.

## Сборка в GitHub Actions

Каждый пуш в `main` собирается на macOS в Xcode 16 (`.github/workflows/build.yml`):

1. ядро `Libbox.xcframework` (gomobile, кэшируется по версии sing-box и скрипту сборки);
2. списки правил;
3. сборка для симулятора и неподписанная сборка для iPhone (приложение + расширение, ad-hoc подпись с entitlements);
4. релиз `v<версия>-<номер сборки>` (например, `v0.6-12`) с пометкой Latest. Хранятся 10 последних сборок.

- `Nox-unsigned.ipa` — для iPhone. Установить можно через Sideloadly, AltStore/SideStore или TrollStore. Для работы VPN нужна подпись сертификатом с правом Network Extension (платный аккаунт разработчика) или TrollStore.
- `Nox-simulator.zip` — для симулятора на Mac с Apple Silicon (демо-движок).

Постоянная ссылка на свежую сборку: `https://github.com/lucudar/nox-ios/releases/latest/download/Nox-unsigned.ipa`.

Номер сборки записывается в приложение и расширение (`CFBundleVersion`), версия — `MARKETING_VERSION` в `tools/gen_project.py`. Иконки рисует `tools/make_icons.py`; если PNG в репозитории нет, workflow сгенерирует и закоммитит их сам.

## Лицензии

Ядро [sing-box](https://github.com/SagerNet/sing-box) распространяется по **GPL-3.0-or-later**; сборки Nox, в которые оно входит, при распространении должны соблюдать условия GPL (в том числе открытый исходный код). Списки правил: [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite), [SagerNet/sing-geoip](https://github.com/SagerNet/sing-geoip), [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains), [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat).
