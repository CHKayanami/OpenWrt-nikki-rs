#!/usr/bin/env bash
# Native host tools only; no target SDK, cross compiler, feeds or QEMU.
set -euo pipefail
tools_dir="$(mkdir -p "${1:-.build-tools}" && cd "${1:-.build-tools}" && pwd)"
mkdir -p "$tools_dir/bin"
if [[ -x "$tools_dir/bin/apk" && -x "$tools_dir/bin/po2lmo" && -x "$tools_dir/bin/usign" ]]; then
    exit 0
fi
sources_dir=$(mktemp -d)
trap 'rm -rf "$sources_dir"' EXIT
fetch() { curl --fail --location --retry 3 --silent --show-error "$1" -o "$2"; }

fetch https://codeload.github.com/alpinelinux/apk-tools/tar.gz/refs/tags/v3.0.5 "$sources_dir/apk.tar.gz"
tar -xzf "$sources_dir/apk.tar.gz" -C "$sources_dir"
VERSION=3.0.5 meson setup "$sources_dir/apk-build" "$sources_dir/apk-tools-3.0.5" \
    --buildtype=release -Ddefault_library=static -Ddocs=disabled -Dhelp=disabled \
    -Dlua=disabled -Dpython=disabled -Dtests=disabled -Dzstd=disabled -Durl_backend=wget
meson compile -C "$sources_dir/apk-build"
install -m755 "$sources_dir/apk-build/src/apk" "$tools_dir/bin/apk"

fetch https://codeload.github.com/openwrt/usign/tar.gz/c4c72b1b07945ee192361dc751291a7c98d6adcd "$sources_dir/usign.tar.gz"
tar -xzf "$sources_dir/usign.tar.gz" -C "$sources_dir"
cmake -S "$sources_dir/usign-c4c72b1b07945ee192361dc751291a7c98d6adcd" \
    -B "$sources_dir/usign-build" -DUSE_LIBUBOX=OFF
cmake --build "$sources_dir/usign-build" --parallel
install -m755 "$sources_dir/usign-build/usign" "$tools_dir/bin/usign"

mkdir -p "$sources_dir/lmo/lib" "$sources_dir/lmo/contrib"
for source in po2lmo.c lib/lmo.c lib/lmo.h lib/plural_formula.y contrib/lemon.c contrib/lempar.c; do
    fetch "https://raw.githubusercontent.com/openwrt/luci/0e6537981036ea221a73e497920192179e9f74c3/modules/luci-base/src/$source" "$sources_dir/lmo/$source"
done
cc -std=gnu17 -O2 -o "$sources_dir/lmo/contrib/lemon" "$sources_dir/lmo/contrib/lemon.c"
(cd "$sources_dir/lmo" && ./contrib/lemon -q lib/plural_formula.y)
cc -std=gnu17 -O2 -o "$tools_dir/bin/po2lmo" "$sources_dir/lmo/po2lmo.c" \
    "$sources_dir/lmo/lib/lmo.c" "$sources_dir/lmo/lib/plural_formula.c"
