# Ядра для VPN-клиента: sing-box, Xray-core, mihomo — разбор и план своего ядра «Nox Core»

Документ для Nox 0.6. Цель — понять, как устроены популярные прокси-ядра, что из этого реально нужно на iOS и как прийти к своему ядру, не переписывая с нуля TCP/IP-стек, TLS и QUIC.

## 1. Ограничения iOS, под которые выбирается ядро

| Ограничение | Что это значит для ядра |
|---|---|
| Туннель живёт только в **Network Extension** (Packet Tunnel Provider) | Ядро — библиотека внутри `.appex`, без отдельного процесса, `fork/exec` запрещены |
| Лимит памяти расширения — **≈50 МБ** (jetsam убивает процесс без предупреждения) | Нужны маленькие буферы, ограничение числа соединений, `GOMEMLIMIT`/OOM-контроль; тяжёлые фичи (Tailscale, Naive/cronet) — мимо |
| Пакеты приходят из `NEPacketTunnelFlow` / fd utun | Нужен **userspace TCP/IP-стек** (gVisor, lwIP) или NAT в системный стек; плюс маршруты/DNS через `NEPacketTunnelNetworkSettings` |
| `includeAllNetworks` (kill switch) | Нельзя слушать локальные сокеты для NAT-трюков → только чистый userspace-стек (gVisor) |
| Go работает через **gomobile** (статическая `.xcframework`) | Простой экспорт API: строки, числа, интерфейсы-колбэки; без дженериков и каналов на границе |
| Связь приложение ↔ расширение | App Group (файлы), `sendProviderMessage`, локальный HTTP/unix-сокет |
| Лицензии | sing-box и mihomo — **GPL-3.0**, Xray-core — **MPL-2.0** |

## 2. Общая модель любого прокси-ядра

```
 вход (inbound)          ядро                                   выход (outbound)
 ──────────────     ───────────────────────────────────────    ─────────────────────
 TUN (IP-пакеты) ─▶ TCP/IP-стек ─▶ сниффинг (TLS SNI, HTTP  ─▶  direct / block
 SOCKS/HTTP/mixed   (gVisor/lwIP/  Host, QUIC, DNS)             VLESS, VMess, Trojan,
                    system)        ─▶ роутер: правила            Shadowsocks(2022), Hysteria2,
                                      (домен, IP, geosite,       TUIC, WireGuard, SSH, AnyTLS…
                                      порт, протокол…)          ── транспорт: TCP, WS, gRPC,
                                   ─▶ DNS-роутер, кэш, FakeIP       HTTP/2, HTTPUpgrade, QUIC, XHTTP
                                   ─▶ учёт соединений,          ── безопасность: TLS, uTLS
                                      статистика, API              (отпечаток браузера), REALITY,
                                                                   ShadowTLS, ECH
                                                                ── мультиплексирование: smux,
                                                                   yamux, h2mux, XUDP
```

Любое ядро — это четыре вещи: **стек** (превращает пакеты в соединения), **роутер** (решает, куда отправить соединение), **DNS** (решает, какой IP у домена и не утекает ли запрос), **протоколы и транспорты** (как замаскировать трафик к серверу). Остальное — конфигурация, API и жизненный цикл.

## 3. sing-box (SagerNet) — то, что работает в Nox сейчас

**Язык / лицензия:** Go, GPL-3.0-or-later. **Конфиг:** JSON со строгой схемой (неизвестные поля — ошибка). Версия в Nox — 1.14.2.

### Архитектура (по исходникам v1.14.2)

- `box.go` — сборка экземпляра `Box`: создаёт менеджеры и запускает их по стадиям жизненного цикла (`adapter/lifecycle.go`: Initialize → Start → PostStart → Started). Порядок важен: сначала сеть и DNS, потом inbound'ы.
- `adapter/` — интерфейсы всего ядра: `Inbound`, `Outbound`, `Endpoint` (для WireGuard/Tailscale — одновременно вход и выход), `Router`, `DNSRouter`, `ConnectionManager`, `NetworkManager`, `RuleSet`, `PlatformInterface`. Реализации регистрируются в реестрах (`include/`) и включаются build-тегами — так из бинарника выкидывается ненужное.
- `protocol/` — реализации протоколов: `vless`, `vmess`, `trojan`, `shadowsocks`, `hysteria2`, `tuic`, `anytls`, `shadowtls`, `wireguard`, `ssh`, `socks`, `http`, `mixed`, `naive`, `openvpn`, `tun`, `direct`, `block`, `dns`, `group` (selector, urltest) и др.
- `route/` — роутер соединений. Правила (`route/rule/`) — это набор условий (домен, суффикс, ключевое слово, regex, IP/CIDR, порт, протокол, `rule_set`, сеть Wi-Fi/сотовая, `network_is_expensive`, логические AND/OR) и **действие**: `route`, `route-options`, `reject`, `hijack-dns`, `sniff`, `resolve`, `bypass`, `evaluate`, `respond`, `predefined`. С 1.11 сниффинг и резолв — это действия правил, а не флаги inbound'а.
- **Rule-set** — списки правил в бинарном формате `.srs` (`common/srs`), локальные или удалённые с автообновлением (`rule_set_remote.go`, `rule_set_updater.go`); есть поддержка синтаксиса фильтров AdGuard. Внутри — сжатые succinct-структуры для доменов, поэтому тысячи доменов занимают килобайты.
- `dns/` — свой DNS-роутер с правилами (те же условия, что у маршрутов), кэшем и транспортами (`dns/transport/`): UDP, TCP, TLS (DoT), HTTPS (DoH), QUIC/H3, FakeIP, hosts, local (системный резолвер), DHCP, mDNS. Каждый DNS-сервер может ходить через свой outbound (`detour`).
- **TUN** — библиотека `sing-tun`: стеки `system` (NAT в системный стек ОС), `gvisor` (полностью userspace, netstack из gVisor), `mixed` (TCP через system, UDP через gVisor); `auto_route`, `strict_route`. На iOS fd туннеля даёт платформа (`PlatformInterface.openTun`).
- `transport/` — транспорты V2Ray (WebSocket, gRPC — полный и «lite», HTTP/2, HTTPUpgrade, QUIC), `simple-obfs`, `sip003`; `common/tls` — стандартный TLS, **uTLS** (отпечатки браузеров), **REALITY** (клиент и сервер), **ECH**, kTLS, а на Apple — ещё и системный TLS через Network.framework; `common/mux` — **sing-mux** (smux/yamux/h2mux + padding); `common/tlsfragment` — фрагментация ClientHello против DPI.
- `experimental/` — **Clash API** (REST: трафик, соединения, задержки, переключение групп — им пользуется Nox), V2Ray API (статистика), `cache-file` (bbolt: FakeIP, выбранные группы, кэш rule-set).
- `experimental/libbox` — мобильная обвязка для gomobile: `CommandServer` (управление сервисом, логи, статусы), `PlatformInterface` (TUN, мониторинг сети, DNS-кэш, поиск владельца соединения), `Setup` (пути, лимиты, OOM-отчёты), `service/oomkiller` — следит за памятью и сбрасывает соединения до того, как iOS убьёт расширение.

### Плюсы и минусы для Nox

- ➕ Самое «мобильное» ядро: официальная обвязка для iOS/Android, учитывает лимит памяти, есть platform interface под Network Extension.
- ➕ Почти все актуальные протоколы и маскировки (VLESS+REALITY+Vision, Hysteria2, TUIC, AnyTLS, WireGuard, SS-2022), гибкий роутинг и DNS, rule-set с автообновлением.
- ➕ Clash API — готовый канал статистики для приложения.
- ➖ GPL-3.0: распространяемый клиент должен быть открытым.
- ➖ Конфиг строгий и часто меняется между версиями (поля удаляются, миграции) — поэтому в Nox конфиг генерируется кодом (`Nox/Tunnel/SingBoxConfig.swift`) и проверяется `sing-box check` в тестах.
- ➖ XHTTP (SplitHTTP) и VLESS Encryption из Xray не поддерживаются.

## 4. Xray-core (XTLS)

**Язык / лицензия:** Go, MPL-2.0. **Конфиг:** JSON (V2Ray-совместимый), внутри переводится в protobuf.

### Архитектура

- `core/` — экземпляр `Instance` с **реестром фич** (`features/`): `inbound.Manager`, `outbound.Manager`, `routing.Router`, `dns.Client`, `policy.Manager`, `stats.Manager`. Фичи находят друг друга через `RequireFeatures` (dependency injection).
- `app/` — реализации фич: `dispatcher` (точка, где соединение встречает роутер и сниффинг), `router` (правила: domain/ip/geosite/geoip/port/protocol/user/attrs, балансировщики), `dns` (DNS-клиент, FakeDNS), `proxyman` (менеджеры inbound/outbound), `stats`, `log`, `commander` (gRPC API), `observatory` (проверка доступности серверов), `reverse` (обратный прокси).
- `proxy/` — протоколы: `vless` (с потоком **XTLS Vision**), `vmess`, `trojan`, `shadowsocks`, `shadowsocks_2022`, `socks`, `http`, `dokodemo-door`, `freedom`, `blackhole`, `wireguard`, `dns`, `loopback`.
- `transport/internet/` — транспорты: TCP, mKCP, WebSocket, gRPC, HTTPUpgrade, **XHTTP (SplitHTTP)**, QUIC; безопасность: TLS, **REALITY** (Xray — её автор).
- `common/` — пулы буферов (`buf`), мультиплексор `mux` и **XUDP** (UDP с сохранением адреса через mux), геоданные `geosite.dat`/`geoip.dat` (protobuf), быстрый матчер доменов `strmatcher` (MPH/ac-автомат).

### Плюсы и минусы для Nox

- ➕ Эталонная реализация VLESS/REALITY/Vision и XHTTP — новые маскировки появляются здесь первыми; самая мягкая лицензия (MPL-2.0).
- ➕ Огромная совместимость с панелями (3x-ui, Marzban, Remnawave) и подписками.
- ➖ Исторически **нет своего TUN**: мобильные клиенты (v2rayNG, Streisand, V2Box, FoXray) добавляют tun2socks (hev-socks5-tunnel на C или gVisor-tun2socks) и обвязку libXray; это лишний слой и копирования.
- ➖ DNS и роутинг беднее, чем у sing-box (нет rule-set с автообновлением, правил DNS по rule-set, `strict_route`), геоданные `.dat` тяжелее для памяти.
- ➖ Нет готового platform interface под Network Extension — всю iOS-специфику писать самим.

## 5. mihomo (Clash.Meta)

**Язык / лицензия:** Go, GPL-3.0. **Конфиг:** Clash YAML.

### Архитектура

- `tunnel/` — сердце ядра: очередь TCP/UDP-соединений, сопоставление с правилами (`match`), NAT-таблица для UDP, статистика (`tunnel/statistic`).
- `adapter/` — `inbound`, `outbound` (протоколы), `outboundgroup` (**select, url-test, fallback, load-balance, relay**), `provider` (**proxy-providers** — подписки прямо в ядре, с health-check).
- `rules/` — правила: DOMAIN, DOMAIN-SUFFIX, DOMAIN-KEYWORD, GEOSITE, GEOIP, IP-CIDR, SRC-*, DST-PORT, PROCESS-NAME, логические AND/OR/NOT, **rule-providers** (форматы yaml/text/`mrs`).
- `dns/` — enhanced-mode **fake-ip** / redir-host, `nameserver-policy`, fallback с фильтром (защита от подмены), DoH/DoT/DoQ.
- `listener/` — входы: mixed, socks, http, redir/tproxy, **TUN через тот же sing-tun**, а также серверные shadowsocks/vmess/tuic.
- `transport/` и `component/` — vmess/vless/trojan/ss/snell/hysteria(2)/tuic/wireguard/ssh/anytls, gun (gRPC), сниффер, диалер, резолвер, trie доменов, пул FakeIP, геоданные.
- REST API `external-controller` — оригинальный **Clash API**, который повторяет sing-box и использует Nox.

### Плюсы и минусы для Nox

- ➕ Лучшие «группы» и провайдеры: url-test/fallback/load-balance и подписки внутри ядра, огромная база готовых конфигов Clash.
- ➕ Тот же sing-tun для TUN, тот же Clash API.
- ➖ GPL-3.0; нет официальной iOS-обвязки (Stash и Shadowrocket — закрытые собственные ядра); YAML-конфиги с провайдерами тяжелее по памяти.
- ➖ Логика «сначала правила, потом группы» удобна для десктопа, но избыточна для мобильного клиента с одним выбранным сервером.

## 6. Сравнение

| | sing-box | Xray-core | mihomo |
|---|---|---|---|
| Лицензия | GPL-3.0 | **MPL-2.0** | GPL-3.0 |
| Конфиг | JSON, строгий | JSON → protobuf | YAML (Clash) |
| TUN | **sing-tun** (system/gvisor/mixed) | нет / tun2socks снаружи | sing-tun |
| iOS-обвязка | **libbox** (официальная) | libXray (сторонняя) | нет |
| Учёт лимита памяти NE | **oomkiller**, low-memory тег | вручную | вручную |
| VLESS + REALITY + Vision | да | **эталон** | да |
| XHTTP / VLESS Encryption | нет | **да** | частично |
| Hysteria2 / TUIC / AnyTLS | **да** | частично | да |
| WireGuard | да (endpoint) | да | да |
| Роутинг | правила + действия + rule-set `.srs` | правила + балансировщики, `.dat` | правила + rule-providers `.mrs` |
| DNS | **свой роутер с правилами**, FakeIP, все транспорты | DNS-клиент, FakeDNS | fake-ip, nameserver-policy |
| API для приложения | Clash API, V2Ray API, libbox command | gRPC (commander) | Clash API |

**Вывод:** для iOS-клиента лучшая основа — sing-box: у него единственного есть зрелая обвязка под Network Extension и контроль памяти. Xray стоит держать в уме ради XHTTP и новых маскировок — их можно добавить как отдельный outbound.

## 7. Своё ядро: что реально писать, а что — нет

Писать с нуля TCP/IP-стек, TLS с отпечатками браузеров, REALITY и QUIC — это годы работы и постоянная гонка с DPI; ошибки там — это утечки и уязвимости. Все три ядра сами собраны из общих библиотек (gVisor netstack, quic-go, uTLS, wireguard-go). Поэтому «своё ядро» Nox — это **свой слой над проверенными компонентами**: своя модель конфигурации, свой роутер и DNS, свой API для приложения и свои функции, которых нет у других.

### Архитектура «Nox Core»

```
 Nox.app ──(JSON профиля Nox, не sing-box)──▶ NoxCore (Go, gomobile, в NoxTunnel.appex)
                                              ├─ API: Start / Reload / Stop / Stats / Probe / Logs
                                              ├─ TUN: sing-tun (gvisor / mixed)
                                              ├─ Smart Router (своё):
                                              │   • компилированные пресеты (trie доменов + таблицы CIDR)
                                              │   • авто-обход: прямое соединение не прошло (RST, тайм-аут,
                                              │     обрыв TLS) → повтор через VPN, решение кэшируется
                                              │   • анти-DPI для прямого трафика: фрагментация ClientHello
                                              ├─ DNS: свой роутер поверх DoH/DoT-транспортов sing-box
                                              ├─ Outbounds: протоколы sing-box как библиотека
                                              │   (+ XHTTP из Xray как отдельный outbound)
                                              └─ Memory guard: GOMEMLIMIT, лимит соединений, сброс буферов
```

### План

1. **Этап 0 — сделано в 0.6.** Packet Tunnel + libbox (sing-box 1.14.2). Конфиг собирает Nox (`SingBoxConfig`), передаёт через App Group, горячая перезагрузка без разрыва туннеля, статистика через Clash API, вшитые rule-set'ы. Это «ядро на уровне конфигурации»: приложение уже не зависит от формата подписок — всё сводится к своей модели `ProxySpec`.
2. **Этап 1 — свой Go-модуль `noxcore`** вместо libbox: тот же sing-box, но как библиотека (`box.New` + реестры протоколов). Свой минимальный API для gomobile (старт по профилю Nox, перезагрузка, поток статистики и логов, пинг серверов изнутри туннеля), только нужные протоколы через build-теги → меньше бинарник и память.
3. **Этап 2 — Smart Router.** Свой роутер для пресетов: «Россия напрямую» и «Только заблокированное» компилируются в одну структуру поиска; авто-обход блокировок — если прямое соединение к сайту рвётся DPI, ядро само повторяет его через VPN и запоминает домен. Такого по умолчанию нет ни в одном из трёх ядер.
4. **Этап 3 — анти-DPI без сервера.** Для прямого трафика: фрагментация TLS ClientHello и TCP-сегментов (как zapret/GoodbyeDPI, насколько позволяет userspace-стек в NE) — часть замедленных сервисов работает вообще без VPN-сервера.
5. **Этап 4 — новые маскировки.** XHTTP и VLESS Encryption (порт из Xray как outbound), автоматический подбор транспорта, если текущий заблокирован.

### Риски

- **Лицензия:** использование кода sing-box (как и mihomo) делает Nox GPL-3.0 — исходники клиента должны быть открыты. Если нужна закрытая версия, основа — Xray-core (MPL-2.0) + свой TUN-слой на gVisor.
- **Память:** каждое новое свойство (кэш решений Smart Router, анти-DPI) надо мерить на устройстве: лимит расширения ≈50 МБ.
- **Совместимость:** протоколы меняются, поэтому их реализации берём из апстрима и обновляем, а своё пишем только там, где у нас есть преимущество — роутинг, DNS, UX.

## 8. Что изменилось в Nox 0.6

- Таргет **NoxTunnel** (Packet Tunnel Provider) с sing-box 1.14.2 (libbox, gomobile), CI собирает и кэширует `Libbox.xcframework`.
- Конфиг передаётся через App Group (`config.json`), ошибки и лог ядра — обратно (`error.txt`, `box.log`).
- Убраны демонстрационные серверы и демо-движок на устройстве (демо остаётся только в симуляторе).
- Маршрутизация с рабочими пресетами на rule-set'ах (вшиты в приложение, обновляются раз в сутки), блокировка рекламы, свои правила, kill switch, автоподключение.
- Реальная статистика трафика, задержки и внешнего IP через Clash API.
- Новый минималистичный главный экран: кнопка питания, статус, нижняя панель «Серверы» / «Настройки».

## 9. Что изменилось в Nox 0.7: OpenFlux

[OpenFlux](https://github.com/lucudar/OpenFlux) (Go, GPL-3.0) туннелирует IP-пакеты через российские сервисы — документы Яндекс Диска (Yandex Docs / Volga), Mail.ru, звонки MAX (WebRTC), комнаты Cups.online — до выходного узла пользователя. Как он встроен в Nox:

```
 TUN ─▶ sing-box: маршрутизация, DNS, правила ─▶ outbound "proxy" = socks 127.0.0.1:19091 (логин/пароль)
                                                   │
                                                   ▼
        core/noxflux: SOCKS5 → gVisor TCP/IP (10.10.10.2, как у клиентов OpenFlux) → кодек batched|legacy
                      → [AES-256-GCM] → транспорт OpenFlux (несколько документов = MultiTransport) ─▶ выходной узел
```

- **Почему SOCKS-мост, а не свой outbound в sing-box:** sing-box не трогаем (собирается из апстрима), вся маршрутизация, DNS без утечек, пресеты и статистика Clash API работают для OpenFlux так же, как для VLESS. Порт слушает только 127.0.0.1 и требует пароль (RFC 1929): иначе любое приложение на телефоне могло бы пользоваться им как открытым прокси. Исходящее подключение sing-box к порту привязано к 127.0.0.1 (`inet4_bind_address`), чтобы `auto_detect_interface` не привязал его к Wi-Fi/LTE.
- **Один Go-рантайм:** `core/noxflux` собирается gomobile вместе с libbox в один `Libbox.xcframework` (`import Libbox` даёт и `Noxflux*`). OpenFlux подключается к checkout'у sing-box через `replace` на закреплённый коммит; бинарник +3,5 МБ, куча в покое +~170 КБ.
- **Ключ шифрования:** OpenFlux выводит его scrypt'ом (N=32768, r=8 — 32 МБ). В расширении (лимит ≈50 МБ) это опасно, поэтому scrypt считает приложение (чистый Swift, `Nox/Tunnel/Scrypt.swift`, проверен на векторах RFC 7914 и OpenFlux), а в `openflux.json` уходит готовый `master_key`; ключи направлений и формат кадров (`OFX`, версия, направление, nonce, GCM с заголовком в AAD) — как в `transport/encrypted.go`.
- **Проверка при подключении:** новый сеанс должен за отведённое время поднять канал и получить TCP-рукопожатие от выхода через туннель (выход L4 принимает соединение до того, как идёт наружу). Иначе — понятная ошибка («сервис недоступен» / «выходной узел не отвечает») вместо «подключено», но ничего не открывается. Повторный `Start` с теми же настройками (перезагрузка конфига sing-box) сеанс не рвёт.
- **Ограничения:** клиент несёт только TCP и IPv4. Для таких серверов (и для SSH) Nox переводит DNS на TCP (UDP→TCP, DoQ→DoT, DoH3→DoH) и отклоняет UDP/443, чтобы браузеры сразу уходили с QUIC на TCP. Пинг OpenFlux-сервера показывает задержку до сервиса, а не до выхода, поэтому автовыбор такие серверы не берёт.
- **Исправление ядра:** в конфиге 0.6 было поле `log.disable_color`, которого нет в схеме sing-box 1.14 (строгий декодер отвергает конфиг). Цвета в файле лога sing-box отключает сам. Все варианты генерируемых конфигов (протоколы, пресеты, DNS, OpenFlux) теперь проверяются `sing-box check`, а цепочка «конфиг Nox → sing-box → noxflux → выход» — локальным e2e-тестом.
