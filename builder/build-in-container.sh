#!/bin/bash
# 在 builder 容器內編譯 engine 與 online，結果放在 /build/instdir
# 依上游 docker/from-source/build.sh（cp-26.04.6-2）改寫：
#   - 26.04 起 online 是 monorepo，engine 在 online/engine；POCO 隨 engine 一起編譯（engine/external/poco）
#   - 不使用官方預編 engine，不抓 Collabora 的私有 branding repo
#   - 以自訂名稱取代預設的商標名稱，不設 welcome／feedback／infobar URL（不連外）
set -euo pipefail
B=/build
INSTDIR=$B/instdir
STAMP() { echo "=== [$(date '+%F %T')] $*"; }

export HOME=$B/home CCACHE_DIR=$B/ccache
mkdir -p "$HOME" "$CCACHE_DIR"

# online 的網頁前端要求 Node.js >= 20，builder 的 Ubuntu 套件只有 18；改用 build-from-source.sh 下載並核對過的官方二進位檔
NODE_DIR=$B/node-v${NODE_VERSION}-linux-x64
if test ! -x "$NODE_DIR/bin/node" ; then
  tar -xJf "$B/node-v${NODE_VERSION}-linux-x64.tar.xz" -C $B
fi
export PATH="$NODE_DIR/bin:$PATH"

STAMP "engine"
cd $B/online/engine
if test ! -f config_host.mk ; then
  ./autogen.sh --with-distro=CPLinux-LOKit --disable-epm --without-package-format --disable-symbols
fi
make

rm -rf "$INSTDIR" && mkdir -p "$INSTDIR/opt"
cp -a $B/online/engine/instdir "$INSTDIR/opt/lokit"

STAMP "online"
cd $B/online
./autogen.sh
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-silent-rules --disable-tests \
  --with-lokit-path=$B/online/engine/include --with-lo-path=/opt/lokit \
  --with-app-name="${APP_NAME}" --with-vendor="${APP_VENDOR}"
make -j "${BUILD_JOBS:-$(nproc)}"
DESTDIR="$INSTDIR" make install
STAMP "done"
