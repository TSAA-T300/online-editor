#!/bin/bash -e
# 以 bash script/... 執行時 shebang 的 -e 不生效，在這裡明確開啟
set -e
# 以 script/build-from-source.sh 的產物 ${BUILD_DIR}/instdir 打包 runtime 映像
PRJ_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..
cd ${PRJ_DIR}

export DOCKER_BUILDKIT=1
IMAGE_NAME=$(bash script/get-image-name.sh)
BUILD_DIR="${BUILD_DIR:-${PRJ_DIR}/build}"

test -x "${BUILD_DIR}/instdir/usr/bin/coolwsd" || {
  echo "找不到 ${BUILD_DIR}/instdir，請先執行 script/build-from-source.sh"; exit 1; }

echo "building $IMAGE_NAME..."
# 編譯產物以具名 context 傳入，BUILD_DIR 可在 repo 外（約 40 GB）
# 不加 --network=host：開發機 host 網路的 build 連不到套件來源
docker buildx build --load \
    --build-context instdir="${BUILD_DIR}/instdir" \
    --tag $IMAGE_NAME \
    -f Dockerfile \
    .
