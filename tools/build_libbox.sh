#!/usr/bin/env bash
# Builds Frameworks/Libbox.xcframework — sing-box compiled as an iOS library (gomobile), linked
# statically into the NoxTunnel extension. Needs macOS with Xcode and Go (the version sing-box's
# own CI uses, see .github/workflows/build.yml there).
#
#   tools/build_libbox.sh [sing-box version]          e.g. tools/build_libbox.sh 1.14.2
#
# Env: LIBBOX_TARGETS (default ios/arm64,iossimulator/arm64), PATCH_GO=1 to patch GOROOT for
# hardware AES/SHA on iOS like upstream does (SagerNet/sing-box#4486; edits your Go install!).
set -euo pipefail

VERSION="${1:-${SING_BOX_VERSION:-1.14.2}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${LIBBOX_WORK:-$ROOT/build/libbox}"
OUT="$ROOT/Frameworks/Libbox.xcframework"
TARGETS="${LIBBOX_TARGETS:-ios/arm64,iossimulator/arm64}"
# Upstream's Apple tags minus Tailscale, Naive (cronet), OpenConnect, USB/IP and DHCP — Nox does not
# use them and the Network Extension has a 50 MB memory limit. with_low_memory = upstream's iOS mode.
TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_openvpn,with_low_memory,badlinkname,tfogo_checklinkname0,grpcnotrace"
LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$VERSION -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

export GOTOOLCHAIN=local
export PATH="$PATH:$(go env GOPATH)/bin"
go version

mkdir -p "$WORK"
SRC="$WORK/sing-box-$VERSION"
if [ ! -d "$SRC" ]; then
  git clone -q --depth 1 --branch "v$VERSION" https://github.com/SagerNet/sing-box.git "$SRC"
fi
cd "$SRC"

if [ "${PATCH_GO:-0}" = 1 ] && [ -x .github/patch_go_for_ios.sh ]; then
  .github/patch_go_for_ios.sh || echo "warning: Go is not patched for iOS CPU features"
fi

go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.13
go install github.com/sagernet/gomobile/cmd/gobind@v0.1.13

rm -rf "$WORK/Libbox.xcframework"
gomobile bind -v -target "$TARGETS" -libname=box -iosversion=15.0 \
  -trimpath -buildvcs=false -ldflags "$LDFLAGS" -tags "$TAGS" \
  -o "$WORK/Libbox.xcframework" ./experimental/libbox

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$WORK/Libbox.xcframework" "$OUT"
echo "Libbox $VERSION → $OUT"
find "$OUT" -maxdepth 2 | sort
du -sh "$OUT"/*/ 2>/dev/null || true
