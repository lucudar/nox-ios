#!/usr/bin/env bash
# Downloads the rule-sets used by the routing presets into Nox/Resources/RuleSets/<tag>.srs, so the
# first connection works offline; sing-box refreshes them itself once a day (see RuleSets.swift —
# keep the two lists in sync). A failed download only drops that file from the bundle.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/Nox/Resources/RuleSets"
mkdir -p "$DIR"
SAGER_SITE=https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set
SAGER_IP=https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set
ITDOG=https://github.com/itdoginfo/allow-domains/releases/latest/download
RUNET=https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite

fetch() {  # tag url
  if curl -fsSL --retry 3 --retry-delay 2 --max-time 60 -o "$DIR/$1.srs.part" "$2" && [ -s "$DIR/$1.srs.part" ]; then
    mv "$DIR/$1.srs.part" "$DIR/$1.srs"
    printf '%-36s %8s bytes\n' "$1" "$(wc -c < "$DIR/$1.srs" | tr -d ' ')"
  else
    rm -f "$DIR/$1.srs.part"
    echo "warning: $1 not bundled ($2)"
  fi
}

fetch geosite-category-ads-all "$SAGER_SITE/geosite-category-ads-all.srs"
fetch itdog-russia-inside "$ITDOG/russia_inside.srs"
fetch itdog-telegram "$ITDOG/telegram.srs"
fetch itdog-meta "$ITDOG/meta.srs"
fetch itdog-discord "$ITDOG/discord.srs"
fetch itdog-google-ai "$ITDOG/google_ai.srs"
fetch geosite-category-ru "$SAGER_SITE/geosite-category-ru.srs"
fetch geosite-ru-available-only-inside "$RUNET/geosite-ru-available-only-inside.srs"
fetch geoip-ru "$SAGER_IP/geoip-ru.srs"
exit 0
