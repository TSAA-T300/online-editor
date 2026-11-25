#!/bin/bash -e
# 從原始碼編譯 Collabora Online，結果放在 build/instdir
# 需求：約 40 GB 硬碟；64 核約 1 小時（engine 佔大部分）。重跑時沿用 build/ 的編譯結果與 ccache。
# 編完後執行 script/build-docker-image.sh 打包 runtime 映像。
#
# 用法：
#   bash script/build-from-source.sh           預檢後編譯
#   bash script/build-from-source.sh --check   只做環境預檢（換一台電腦時先跑這個）
# 以 bash script/... 執行時 shebang 的 -e 不生效，在這裡明確開啟；pipefail：編譯輸出經 tee 寫 log，失敗時仍要中止
set -eo pipefail
PRJ_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..
cd ${PRJ_DIR}
source script/versions.sh

BUILD_DIR="${BUILD_DIR:-${PRJ_DIR}/build}"
# 使用者看得到的產品名稱與供應商：不可使用 Collabora 的商標名稱（見 README「授權與商標」）
APP_NAME="${APP_NAME:-Online Editor}"
APP_VENDOR="${APP_VENDOR:-ITRI}"
# 網路有 TLS 檢查（以自己的 CA 重新簽發憑證）時：engine 編譯時會下載第三方原始碼，容器要信任 host 的 CA。
# 不需要時設 none
HOST_CA_BUNDLE="${HOST_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
BUILDER_IMAGE="collabora-online-builder:ubuntu24.04"
# 預檢門檻：第一次編譯需要的可用空間（GB）；每個平行編譯工作預留的記憶體（GB）
MIN_FREE_GB="${MIN_FREE_GB:-40}"
GB_PER_JOB="${GB_PER_JOB:-2}"
MIN_MEM_GB=8

# ---------- 環境預檢 ----------
# 編譯在 builder 容器內進行，host 只需要少數工具；換電腦時常見的失敗原因（CA 路徑、Docker 版本、
# 硬碟、記憶體、網路）在這裡先擋下，不要等編譯到一半才失敗。全部檢查完才一起列出問題。
preflight() {
  local errors=() cmd free_gb avail_gb url
  echo "== 環境預檢"
  for cmd in git curl sha256sum docker; do
    command -v "$cmd" >/dev/null || errors+=("找不到指令 ${cmd}")
  done
  [ "$(uname -m)" = "x86_64" ] || errors+=("CPU 架構是 $(uname -m)，只支援 x86_64")
  if ! docker info >/dev/null 2>&1; then
    errors+=("無法使用 docker：未安裝、未啟動，或目前使用者沒有權限")
  elif ! docker buildx version >/dev/null 2>&1; then
    errors+=("沒有 docker buildx：打包映像（build-docker-image.sh）需要 Docker 23 以上，或另外安裝 buildx")
  fi

  if [ "${HOST_CA_BUNDLE}" != "none" ] && [ ! -f "${HOST_CA_BUNDLE}" ]; then
    errors+=("找不到 CA 檔 ${HOST_CA_BUNDLE}：有 TLS 檢查的網路要設 HOST_CA_BUNDLE=<含該 CA 的檔案>（RHEL 系通常是 /etc/pki/tls/certs/ca-bundle.crt）；不需要時設 HOST_CA_BUNDLE=none")
  fi

  mkdir -p "${BUILD_DIR}"
  free_gb=$(df -Pk "${BUILD_DIR}" | awk 'NR==2 {print int($4 / 1048576)}')
  if [ ! -d "${BUILD_DIR}/core/instdir" ] && [ "${free_gb}" -lt "${MIN_FREE_GB}" ]; then
    errors+=("${BUILD_DIR} 所在磁碟只剩 ${free_gb} GB，第一次編譯需要約 ${MIN_FREE_GB} GB；可用 BUILD_DIR 指到較大的磁碟")
  fi

  avail_gb=$(awk '/^MemAvailable:/ {print int($2 / 1048576)}' /proc/meminfo)
  BUILD_JOBS=$(( avail_gb / GB_PER_JOB ))
  [ "${BUILD_JOBS}" -gt "$(nproc)" ] && BUILD_JOBS=$(nproc)
  [ "${BUILD_JOBS}" -lt 1 ] && BUILD_JOBS=1
  if [ "${avail_gb}" -lt "${MIN_MEM_GB}" ]; then
    errors+=("可用記憶體只有 ${avail_gb} GB，至少需要 ${MIN_MEM_GB} GB（連結 engine 時用量最大）")
  fi

  # 編譯過程會連到的來源：原始碼（GitHub）、POCO、engine 的第三方原始碼（LibreOffice）、
  # 前端套件（npm）、builder 映像的 apt 套件（Ubuntu）
  for url in https://github.com https://pocoproject.org https://dev-www.libreoffice.org \
    https://registry.npmjs.org http://archive.ubuntu.com/ubuntu/; do
    local ca_opt=()
    [ "${HOST_CA_BUNDLE}" != "none" ] && [ -f "${HOST_CA_BUNDLE}" ] && ca_opt=(--cacert "${HOST_CA_BUNDLE}")
    curl -sS -o /dev/null --max-time 20 "${ca_opt[@]}" "${url}" 2>/dev/null \
      || errors+=("連不上 ${url}（網路、代理或 CA 設定）")
  done

  echo "   架構 $(uname -m)、Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')、可用空間 ${free_gb} GB、可用記憶體 ${avail_gb} GB、平行編譯 ${BUILD_JOBS} 個（CPU $(nproc) 核）"
  if [ "${#errors[@]}" -gt 0 ]; then
    echo "== 預檢失敗，請先處理：" >&2
    printf '   - %s\n' "${errors[@]}" >&2
    exit 1
  fi
  echo "== 預檢通過"
}

preflight
if [ "${1:-}" = "--check" ]; then
  exit 0
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "== 取得原始碼（engine ${CORE_COMMIT:0:10}、online ${ONLINE_TAG}）"
if test ! -d core/.git ; then
  git init -q core
  git -C core remote add origin "${CORE_REPO}"
fi
if [ "$(git -C core rev-parse -q --verify HEAD || true)" != "${CORE_COMMIT}" ]; then
  git -C core fetch -q --depth=1 origin "${CORE_COMMIT}"
  git -C core checkout -q --force FETCH_HEAD
fi
if test ! -d online/.git ; then
  git clone -q --depth=1 --branch "${ONLINE_TAG}" "${ONLINE_REPO}" online
fi
test "$(git -C online describe --tags --exact-match)" = "${ONLINE_TAG}" || {
  echo "online 不是 ${ONLINE_TAG}，請刪除 ${BUILD_DIR}/online 後重跑"; exit 1; }

POCO_TARBALL="poco-${POCO_VERSION}-all.tar.gz"
if test ! -f "${POCO_TARBALL}" ; then
  curl -sSfLO "https://pocoproject.org/releases/poco-${POCO_VERSION}/${POCO_TARBALL}"
fi
echo "${POCO_SHA256}  ${POCO_TARBALL}" | sha256sum -c -

echo "== 建立編譯環境 ${BUILDER_IMAGE}"
# 不加 --network=host：開發機 host 網路的 build 連不到套件來源
docker build -q -t "${BUILDER_IMAGE}" "${PRJ_DIR}/builder"

CA_MOUNT=()
if [ "${HOST_CA_BUNDLE}" != "none" ]; then
  CA_MOUNT=(-v "${HOST_CA_BUNDLE}:/etc/ssl/certs/ca-certificates.crt:ro")
fi

echo "== 編譯（平行 ${BUILD_JOBS} 個；log：${BUILD_DIR}/build.log）"
# PARALLELISM 覆寫 engine 在 autogen 時記下的平行數（config_host.mk 的 PARALLELISM?=）
docker run --rm --user "$(id -u):$(id -g)" "${CA_MOUNT[@]}" \
  -v "${BUILD_DIR}:/build" -v "${PRJ_DIR}/builder/build-in-container.sh:/build-in-container.sh:ro" \
  -e POCO_VERSION="${POCO_VERSION}" -e APP_NAME="${APP_NAME}" -e APP_VENDOR="${APP_VENDOR}" \
  -e BUILD_JOBS="${BUILD_JOBS}" -e PARALLELISM="${BUILD_JOBS}" \
  "${BUILDER_IMAGE}" bash /build-in-container.sh 2>&1 | tee "${BUILD_DIR}/build.log"

echo "== 完成：${BUILD_DIR}/instdir"
