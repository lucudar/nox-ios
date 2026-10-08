#!/usr/bin/env bash
# Builds Frameworks/Libbox.xcframework — sing-box compiled as an iOS library (gomobile), linked
# statically into the NoxTunnel extension, together with the OpenFlux client (core/noxflux, built
# against https://github.com/lucudar/OpenFlux). Needs macOS with Xcode and Go 1.26.4+ (OpenFlux's
# minimum; sing-box itself needs the version its own CI uses).
#
#   tools/build_libbox.sh [sing-box version]          e.g. tools/build_libbox.sh 1.14.2
#
# Env: LIBBOX_TARGETS (default ios/arm64,iossimulator/arm64), PATCH_GO=1 to patch GOROOT for
# hardware AES/SHA on iOS like upstream does (SagerNet/sing-box#4486; edits your Go install!),
# OPENFLUX_REPO / OPENFLUX_REF (git URL and commit of OpenFlux), NOXFLUX_TEST=1 to run the
# OpenFlux bridge tests on the build machine first.
set -euo pipefail

VERSION="${1:-${SING_BOX_VERSION:-1.14.2}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${LIBBOX_WORK:-$ROOT/build/libbox}"
OUT="$ROOT/Frameworks/Libbox.xcframework"
TARGETS="${LIBBOX_TARGETS:-ios/arm64,iossimulator/arm64}"
OPENFLUX_REPO="${OPENFLUX_REPO:-https://github.com/lucudar/OpenFlux.git}"
OPENFLUX_REF="${OPENFLUX_REF:-a661c9a49ea167b210be3ea751c75c031818a960}"
# Upstream's Apple tags minus Tailscale, Naive (cronet), OpenConnect, USB/IP and DHCP — Nox does not
# use them and the Network Extension has a 50 MB memory limit. with_low_memory = upstream's iOS mode.
TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_openvpn,with_low_memory,badlinkname,tfogo_checklinkname0,grpcnotrace"
LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$VERSION -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

export GOTOOLCHAIN=local
# go.mod/go.sum of the sing-box checkout are edited below to pull in OpenFlux.
export GOFLAGS="${GOFLAGS:+$GOFLAGS }-mod=mod"
export PATH="$PATH:$(go env GOPATH)/bin"
go version

mkdir -p "$WORK"
SRC="$WORK/sing-box-$VERSION"
if [ ! -d "$SRC" ]; then
  git clone -q --depth 1 --branch "v$VERSION" https://github.com/SagerNet/sing-box.git "$SRC"
fi

# OpenFlux: module "openflux", pinned to a commit and wired in with a replace directive.
OF="$WORK/openflux-${OPENFLUX_REF:0:12}"
if [ ! -d "$OF/.git" ]; then
  rm -rf "$OF"
  git init -q "$OF"
  git -C "$OF" fetch -q --depth 1 "$OPENFLUX_REPO" "$OPENFLUX_REF"
  git -C "$OF" checkout -q FETCH_HEAD
fi
OF_COMMIT="$(git -C "$OF" rev-parse HEAD)"
echo "OpenFlux $OF_COMMIT"

cd "$SRC"
rm -rf experimental/noxflux
mkdir -p experimental/noxflux
cp "$ROOT"/core/noxflux/*.go experimental/noxflux/
go mod edit -require=openflux@v0.0.0 -replace=openflux="$OF"
go get openflux@v0.0.0
LDFLAGS="$LDFLAGS -X github.com/sagernet/sing-box/experimental/noxflux.openFluxVersion=$OF_COMMIT"
if [ "${NOXFLUX_TEST:-0}" = 1 ]; then
  go test -count=1 -tags "$TAGS" ./experimental/noxflux
fi

if [ "${PATCH_GO:-0}" = 1 ] && [ -x .github/patch_go_for_ios.sh ]; then
  .github/patch_go_for_ios.sh || echo "warning: Go is not patched for iOS CPU features"
fi

go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.13
go install github.com/sagernet/gomobile/cmd/gobind@v0.1.13

rm -rf "$WORK/Libbox.xcframework"
gomobile bind -v -target "$TARGETS" -libname=box -iosversion=15.0 \
  -trimpath -buildvcs=false -ldflags "$LDFLAGS" -tags "$TAGS" \
  -o "$WORK/Libbox.xcframework" ./experimental/libbox ./experimental/noxflux

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$WORK/Libbox.xcframework" "$OUT"
echo "Libbox $VERSION + OpenFlux ${OF_COMMIT:0:12} → $OUT"
find "$OUT" -maxdepth 2 | sort
du -sh "$OUT"/*/ 2>/dev/null || true
