#!/bin/bash
# 在 builder 容器內編譯 engine 與 online，結果放在 /build/instdir
# 依上游 docker/from-source/build.sh（cp-25.04.9-4）改寫：
#   - 不使用官方預編 engine，不抓 Collabora 的私有 branding repo
#   - 以自訂名稱取代預設的商標名稱，不設 welcome／feedback／infobar URL（不連外）
set -euo pipefail
B=/build
INSTDIR=$B/instdir
STAMP() { echo "=== [$(date '+%F %T')] $*"; }

export HOME=$B/home CCACHE_DIR=$B/ccache
mkdir -p "$HOME" "$CCACHE_DIR"

STAMP "POCO"
if test ! -f $B/poco/lib/libPocoFoundation.a ; then
  cd $B && rm -rf "poco-${POCO_VERSION}-all" && tar -xzf "poco-${POCO_VERSION}-all.tar.gz" && cd "poco-${POCO_VERSION}-all"
  ./configure --static --no-tests --no-samples --no-sharedlibs --cflags="-fPIC" \
    --omit=Zip,Data,Data/SQLite,Data/ODBC,Data/MySQL,MongoDB,PDF,CppParser,PageCompiler,Redis,Encodings,ActiveRecord \
    --prefix=$B/poco
  make -j "${BUILD_JOBS:-$(nproc)}" && make install
fi

STAMP "engine"
cd $B/core
if test ! -f config_host.mk ; then
  ./autogen.sh --with-distro=CPLinux-LOKit --disable-epm --without-package-format --disable-symbols
fi
make

rm -rf "$INSTDIR" && mkdir -p "$INSTDIR/opt"
cp -a $B/core/instdir "$INSTDIR/opt/lokit"

STAMP "online"
cd $B/online
./autogen.sh
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-silent-rules --disable-tests \
  --with-lokit-path=$B/core/include --with-lo-path=/opt/lokit \
  --with-poco-includes=$B/poco/include --with-poco-libs=$B/poco/lib \
  --with-app-name="${APP_NAME}" --with-vendor="${APP_VENDOR}"
make -j "${BUILD_JOBS:-$(nproc)}"
DESTDIR="$INSTDIR" make install
STAMP "done"
