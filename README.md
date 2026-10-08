# Nox — VPN-клиент для iOS

Nox — VPN/прокси-клиент для iPhone на SwiftUI (iOS 17+). Внутри — настоящий туннель: расширение **Packet Tunnel** с ядром **sing-box 1.14** (libbox) и встроенным клиентом **[OpenFlux](https://github.com/lucudar/OpenFlux)** — туннелем через российские сервисы (Яндекс Документы, Mail.ru, MAX). Серверы из подписок, ссылок, QR-кодов и файлов, маршрутизация с готовыми пресетами, статистика реального трафика и гибкое оформление.

## Что умеет

- **Главный экран** — большая кнопка подключения, статус, таймер, скорость, внешний IP и страна выхода, задержка. Внизу две кнопки: **Серверы** и **Настройки**.
- **Серверы** — подписки по URL, импорт ссылкой, из буфера обмена, по QR-коду (камера или фото) и из файла, ручное добавление, TCP-пинг в обход туннеля, автовыбор лучшего сервера, группы. Смена сервера при включённом VPN — без разрыва туннеля (горячая перезагрузка ядра).
  - Ссылки: `vless://` (в том числе REALITY), `vmess://`, `trojan://`, `ss://` (включая 2022), `hysteria2://` / `hy2://`, `tuic://`, `wireguard://` / `wg://`, `ssh://`, `openflux://` и другие.
  - Файлы: подписки (обычные и base64), конфиги sing-box и Xray (JSON), Clash (YAML), WireGuard `.conf`, OpenVPN `.ovpn`, профили OpenFlux (JSON).
- **OpenFlux** — трафик идёт внутри Яндекс Документов, Яндекс Волги, Mail.ru, звонков MAX или комнат Cups.online до вашего выходного узла, поэтому работает там, где обычные VPN-протоколы режут. Маршрутизация, DNS и правила — те же, что у остальных серверов (подробнее — [ниже](#openflux)).
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
- **Логи** — логи приложения, ядра sing-box и клиента OpenFlux, подробный режим.
- **Оформление** — пресеты, акцентный цвет, темы, фоны (в том числе своё фото), свечение, анимация кнопки, шрифт, стиль значков и 4 иконки приложения.

## Как это устроено

```
 Nox.app (SwiftUI)                       App Group: group.<bundle id>                NoxTunnel.appex
 ───────────────────                     ───────────────────────────                 ────────────────────────────
 SingBoxConfig собирает JSON  ──write──▶  config.json                    ──read──▶   PacketTunnelProvider
 OpenFluxProfile (+ scrypt)   ──write──▶  openflux.json (только OpenFlux) ──read──▶   ├─ OpenFlux-клиент (core/noxflux)
 SingBoxEngine                            RuleSets/*.srs, cache.db                    │   └─ SOCKS5 127.0.0.1:19091 ◀─┐
  └─ NETunnelProviderManager ─start(конфиги)/stop─────────────────────────────────▶   └─ libbox CommandServer (sing-box)
  └─ sendProviderMessage(конфиги) ────────────────────────────────────────────────▶       ├─ TUN (fd от NEPacketTunnelFlow)
 CoreAPI ◀── Clash API 127.0.0.1:19090 (трафик, задержка, соединения) ──────────────       ├─ маршрутизация, DNS, rule-set
 LogsView ◀── box.log, openflux.log, error.txt ◀───────────────────────────────────       └─ outbound: VLESS/…/WG/socks ┘
```

- `Nox/Tunnel/` — сборка конфигурации sing-box из сервера и настроек (`SingBoxConfig`, `SingBoxOutbound`, `RuleSets`, `OpenVPNConfig`), профиль OpenFlux (`OpenFluxConfig`) и scrypt для его ключа (`Scrypt`).
- `Nox/Core/SingBoxEngine.swift` — профиль VPN (`NETunnelProviderManager`), старт/стоп, горячая перезагрузка, ошибки ядра. `CoreAPI.swift` — клиент Clash API.
- `NoxTunnel/` — расширение: `PacketTunnelProvider` (запуск libbox), `PlatformInterface` (TUN, маршруты, DNS, мониторинг сети для sing-box) и `OpenFluxCore` (запуск и проверка клиента OpenFlux).
- `core/noxflux/` — Go-пакет клиента OpenFlux: транспорт OpenFlux + userspace TCP/IP (gVisor) + локальный SOCKS5 с паролем; собирается в `Libbox.xcframework` вместе с sing-box.
- `Shared/AppGroup.swift` — общие пути и сообщения между приложением и расширением; `Shared/TunnelPayload.swift` — конфиги, которые приложение передаёт расширению прямо в запросе на запуск и в сообщении перезагрузки (файлы в App Group нужны для запуска по требованию).
- В симуляторе Packet Tunnel не работает, поэтому там подключается `DemoTunnelEngine`: он проверяет конфиг и показывает сценарий подключения без туннеля.

Исследование ядер (sing-box, Xray-core, mihomo) и план своего ядра — в [`docs/core-research.md`](docs/core-research.md).

## OpenFlux

[OpenFlux](https://github.com/lucudar/OpenFlux) прячет IP-пакеты в сервис, который не блокируют: документ на Яндекс Диске (Yandex Docs или Volga), документ Mail.ru, звонок MAX или комнату Cups.online. На другой стороне — **ваш выходной узел** OpenFlux (любой VPS за пределами РФ), он выпускает трафик в интернет. Готовых публичных серверов нет: выход нужен свой.

**1. Выходной узел** (Linux/macOS/Windows; `--mode=l4` работает без root):

```
./openflux --role=exit --mode=l4 --transport=yandex --url="https://disk.yandex.ru/i/AAA,https://disk.yandex.ru/i/BBB"
```

Mail.ru — `--transport=mailru --url="https://cloud.mail.ru/public/…"`; MAX — `--transport=oneme --maxToken="<токен аккаунта выхода>"`; Cups.online — `--transport=cupsonline` без `--url` (узел сам создаёт комнаты и печатает их список).

**2. Сервер в Nox:** «Серверы» → «Создать вручную» → OpenFlux. Выберите канал, вставьте те же ссылки на документы **в том же порядке** (для MAX — токен своего аккаунта и ID аккаунта выхода, для Cups.online — список комнат), кодек как на выходе (`batched` — по умолчанию в OpenFlux, `legacy` — если узел запущен с `--codec=legacy`). Под формой показана команда выхода, которая подходит к настройкам. Кнопка вставки понимает ссылку `openflux://`, JSON-профиль, командную строку `openflux …` и просто ссылки на документы.

**Ссылка** (её можно раздавать, импортировать и класть в подписки):

```
openflux://yandex?url=https%3A%2F%2Fdisk.yandex.ru%2Fi%2FAAA&url=https%3A%2F%2Fdisk.yandex.ru%2Fi%2FBBB&codec=batched#Мой выход
openflux://oneme?token=<токен>&uid=<ID выхода>&codec=batched#MAX
```

Каналы: `yandex`, `vyandex` (Volga), `mailru`, `oneme` (MAX), `cupsonline`; синонимы схемы — `flux://`, `ofx://`. Несколько документов (`url=` несколько раз или через запятую) работают как параллельные каналы — быстрее и устойчивее.

**Шифрование** (необязательно): AES-256-GCM поверх канала, как `--encryption-key-file` у выхода — тот же ключ (от 16 символов), в ссылке `key=…`. Ключ выводится через scrypt (32 МБ памяти), поэтому его считает приложение, а в расширение (лимит ≈50 МБ) передаётся только результат. Контекст ключа — строка `--url` выхода: Nox собирает её из документов через запятую без пробелов (для MAX и Cups.online — `http://#`, значение OpenFlux по умолчанию). Если выход запущен с другой строкой `--url`, укажите её в поле «Контекст ключа» (`ctx=` в ссылке).

**Как работает в Nox:** клиент OpenFlux запускается в расширении рядом с sing-box и слушает SOCKS5 на `127.0.0.1:19091` (с паролем, чтобы другие приложения не пользовались им как открытым прокси); sing-box отправляет туда трафик «через VPN». При подключении Nox проверяет весь путь — канал поднялся и выходной узел ответил — и иначе показывает понятную ошибку. Ограничения: только TCP (QUIC сразу отклоняется, и приложения переходят на TCP; DNS идёт по TCP через туннель), без IPv6, скорость ограничена сервисом. Лог клиента — «Настройки» → «Логи» → OpenFlux.

## Как собрать

1. Нужны **macOS**, **Xcode 16+** и **Go 1.26** (`brew install go`).
2. Соберите ядро: `bash tools/build_libbox.sh` → `Frameworks/Libbox.xcframework` (sing-box 1.14.2 + OpenFlux из `core/noxflux`, ~10–20 минут при первой сборке). Скрипт сам скачивает OpenFlux закреплённого коммита (`OPENFLUX_REPO` / `OPENFLUX_REF`); `NOXFLUX_TEST=1` дополнительно прогоняет тесты клиента.
3. Скачайте списки правил: `bash tools/fetch_rulesets.sh` → `Nox/Resources/RuleSets/*.srs` (необязательно: без них ядро скачает списки при первом подключении).
4. Откройте `Nox.xcodeproj`. Проект сгенерирован скриптом `tools/gen_project.py` — правьте настройки в нём и перезапускайте.

### Запуск на iPhone

Network Extension требует **платного аккаунта Apple Developer** (с бесплатным Apple ID приложение установится, но VPN не запустится).

1. В настройках проекта (уровень проекта, не таргета) поменяйте `NOX_BUNDLE_ID` с `com.example.nox` на свой, например `com.yourname.nox`. От него берутся ID приложения, расширения (`.tunnel`) и App Group (`group.<id>`).
2. В **Signing & Capabilities** обоих таргетов (Nox и NoxTunnel) выберите свою команду. Возможности App Groups и Network Extensions → Packet Tunnel уже прописаны в `Config/*.entitlements`.
3. Запустите на устройстве (**⌘R**) и разрешите добавление конфигурации VPN.

## Сборка в GitHub Actions

Каждый пуш в `main` собирается на macOS в Xcode 16 (`.github/workflows/build.yml`):

1. ядро `Libbox.xcframework` (gomobile, кэшируется по версии sing-box, скрипту сборки и коду `core/noxflux`; перед сборкой — тесты клиента OpenFlux);
2. списки правил;
3. сборка для симулятора и неподписанная сборка для iPhone (приложение + расширение, ad-hoc подпись с entitlements);
4. релиз `v<версия>-<номер сборки>` (например, `v0.7-12`) с пометкой Latest. Хранятся 10 последних сборок.

- `Nox-unsigned.ipa` — для iPhone. Установить можно через Sideloadly, AltStore/SideStore или TrollStore. Для работы VPN нужна подпись сертификатом с правом Network Extension (платный аккаунт разработчика) или TrollStore. Если при переподписи App Group переименовали (AltStore/SideStore и другие инструменты), Nox находит её сам — по `ALTAppGroups` или профилю `embedded.mobileprovision`; если группы нет совсем, туннель всё равно работает (конфиги передаются напрямую), но лог ядра виден только во время подключения.
- `Nox-simulator.zip` — для симулятора на Mac с Apple Silicon (демо-движок).

Постоянная ссылка на свежую сборку: `https://github.com/lucudar/nox-ios/releases/latest/download/Nox-unsigned.ipa`.

Номер сборки записывается в приложение и расширение (`CFBundleVersion`), версия — `MARKETING_VERSION` в `tools/gen_project.py`. Иконки рисует `tools/make_icons.py`; если PNG в репозитории нет, workflow сгенерирует и закоммитит их сам.

## Лицензии

Nox распространяется по **GPL-3.0-or-later** (файл [`LICENSE`](LICENSE)): в сборки входят ядра под GPL, поэтому исходный код открыт и любые распространяемые копии и производные версии должны оставаться под GPL.

- [sing-box](https://github.com/SagerNet/sing-box) — GPL-3.0-or-later, с дополнительным условием автора: производные работы не могут использовать название sing-box или выдавать себя за него без согласия (Nox лишь использует его как ядро).
- [OpenFlux](https://github.com/lucudar/OpenFlux) — GPL-3.0-or-later; сторонние компоненты (wireguard-go, gopacket, gVisor, gorilla/websocket, pion/webrtc, golang.org/x/sys, pierrec/lz4) — под своими лицензиями, см. его `NOTICE`.
- Списки правил: [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite), [SagerNet/sing-geoip](https://github.com/SagerNet/sing-geoip), [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains), [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat).
