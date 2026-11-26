#!/bin/bash -e
# 產生映像對應的原始碼包：映像所含 MPL、GPL、LGPL 元件的對應原始碼與編譯腳本。
# 把映像交給他人時，這個原始碼包要一併提供（README「提供原始碼」）。
#
# 前提：同一個 BUILD_DIR 已執行過 script/build-from-source.sh 與 script/build-docker-image.sh。
# 內容取自 BUILD_DIR 中實際編譯用的原始碼，不重新向上游下載；Ubuntu 套件的原始碼依映像內的版本清單下載。
# Ubuntu 套件的原始碼先用 apt-get source，archive 已沒有該版本時改向 Launchpad 取。
#
# 用法：bash script/build-source-package.sh
#   產物：${OUT_DIR}/online-editor-source-<映像版本>.tar（OUT_DIR 預設 ${BUILD_DIR}/source-package）
# 以 bash script/... 執行時 shebang 的 -e 不生效，在這裡明確開啟
set -eo pipefail
PRJ_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..
cd ${PRJ_DIR}
source script/versions.sh

BUILD_DIR="${BUILD_DIR:-${PRJ_DIR}/build}"
IMAGE_NAME="${IMAGE_NAME:-$(bash script/get-image-name.sh)}"
NAME="online-editor-source-${IMAGE_NAME##*:}"
OUT_DIR="${OUT_DIR:-${BUILD_DIR}/source-package}"
STAGE="${OUT_DIR}/${NAME}"
ENGINE_DIR="${BUILD_DIR}/online/engine"

# ---------- 確認 BUILD_DIR 與映像是這次要交付的版本 ----------
errors=()
[ "$(git -C "${BUILD_DIR}/online" describe --tags --exact-match 2>/dev/null)" = "${ONLINE_TAG}" ] \
  || errors+=("${BUILD_DIR}/online 不是 ${ONLINE_TAG}，請先執行 script/build-from-source.sh")
[ "$(git -C "${ENGINE_DIR}/translations" rev-parse -q --verify HEAD 2>/dev/null)" = "${TRANSLATIONS_COMMIT}" ] \
  || errors+=("${ENGINE_DIR}/translations 不是 ${TRANSLATIONS_COMMIT}，請先執行 script/build-from-source.sh")
# config_host.mk 記的是 builder 容器內的路徑（BUILD_DIR 掛在 /build），換回 host 的路徑
TARFILE_LOCATION=$(sed -n 's/^export TARFILE_LOCATION=//p' "${ENGINE_DIR}/config_host.mk" 2>/dev/null)
TARFILE_LOCATION="${TARFILE_LOCATION/#\/build/${BUILD_DIR}}"
[ -n "${TARFILE_LOCATION}" ] && [ -n "$(ls -A "${TARFILE_LOCATION}" 2>/dev/null)" ] \
  || errors+=("找不到 engine 下載的第三方原始碼（config_host.mk 的 TARFILE_LOCATION），請先完成編譯")
docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1 \
  || errors+=("找不到映像 ${IMAGE_NAME}，請先執行 script/build-docker-image.sh")
[ -z "$(git -C "${PRJ_DIR}" status --porcelain -- .)" ] \
  || errors+=("${PRJ_DIR} 有未 commit 的修改；原始碼包收錄的建置腳本取自 HEAD，要和建置映像時一致")
if [ "${#errors[@]}" -gt 0 ]; then
  printf '錯誤：%s\n' "${errors[@]}" >&2
  exit 1
fi

rm -rf "${STAGE}" "${OUT_DIR}/${NAME}.tar"
mkdir -p "${STAGE}/licenses" "${STAGE}/ubuntu-sources"

echo "== 本 repo 的建置腳本"
# 本目錄在 repo 中的路徑（獨立 repo 時為空字串）；git archive 要在 repo 最上層執行，否則會以目前目錄為前綴而找不到子樹
COMPONENT_PATH=$(git -C "${PRJ_DIR}" rev-parse --show-prefix)
git -C "$(git -C "${PRJ_DIR}" rev-parse --show-toplevel)" archive --format=tar.gz --prefix=build-scripts/ \
  -o "${STAGE}/build-scripts.tar.gz" "HEAD:${COMPONENT_PATH%/}"

echo "== online ${ONLINE_TAG}（內含 engine 與 POCO）"
git -C "${BUILD_DIR}/online" archive --format=tar.gz --prefix=online/ \
  -o "${STAGE}/online-${ONLINE_TAG}.tar.gz" HEAD

echo "== engine 的介面翻譯 ${TRANSLATIONS_COMMIT:0:10}"
git -C "${ENGINE_DIR}/translations" archive --format=tar.gz --prefix=online/engine/translations/ \
  -o "${STAGE}/translations-${TRANSLATIONS_COMMIT:0:10}.tar.gz" HEAD

echo "== engine 編譯時下載的第三方原始碼（${TARFILE_LOCATION}）"
mkdir -p "${STAGE}/engine-external-tarballs"
find "${TARFILE_LOCATION}" -maxdepth 1 -type f ! -name '*.part' -exec cp -p {} "${STAGE}/engine-external-tarballs/" \;
echo "   $(ls "${STAGE}/engine-external-tarballs" | wc -l) 個檔案"

echo "== 授權檔（取自映像 ${IMAGE_NAME}）"
for f in /usr/share/doc/online-editor/third_party_licenses.txt /usr/share/doc/online-editor/ubuntu-packages.tsv \
  /opt/lokit/LICENSE /opt/lokit/NOTICE /usr/share/doc/coolwsd/THIRDPARTYLICENSES \
  /usr/share/doc/coolwsd/collabora-online-sbom.spdx.json; do
  docker run --rm --entrypoint cat "${IMAGE_NAME}" "${f}" > "${STAGE}/licenses/$(basename "${f}")"
done

echo "== Ubuntu 套件的原始碼（依 ubuntu-packages.tsv 的版本）"
# 原始碼套件名稱與版本去重；第 3、4 欄是原始碼套件
cut -f3,4 "${STAGE}/licenses/ubuntu-packages.tsv" | sort -u | awk -F'\t' '{print $1"="$2}' \
  > "${STAGE}/ubuntu-sources/requested.txt"
# archive 只保留每個套件的最新版；映像的基底較舊、或之後套件更新時，apt-get source 取不到映像內的版本，
# 改向 Launchpad 取（保留所有發佈過的版本）。連 Launchpad 走 https，網路有 TLS 檢查時掛入 host 的 CA（同 build-from-source.sh）
HOST_CA_BUNDLE="${HOST_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
CA_MOUNT=()
if [ "${HOST_CA_BUNDLE}" != "none" ]; then
  CA_MOUNT=(-v "${HOST_CA_BUNDLE}:/host-ca.crt:ro" -e CURL_CA_BUNDLE=/host-ca.crt)
fi
# 不加 --network=host：開發機 host 網路的容器連不到套件來源（同 build-from-source.sh）
docker run --rm "${CA_MOUNT[@]}" -v "${STAGE}/ubuntu-sources:/out" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  ubuntu:24.04 bash -c '
    set -o pipefail
    sed -i "s/^Types: deb$/Types: deb deb-src/" /etc/apt/sources.list.d/ubuntu.sources
    apt-get update -qq >/dev/null && apt-get install -y -qq dpkg-dev curl jq >/dev/null
    LP=https://api.launchpad.net/1.0/ubuntu/+archive/primary
    cd /out && : > missing.txt
    while read -r spec; do
      apt-get source -qq --download-only "${spec}" >/dev/null 2>&1 && continue
      src="${spec%%=*}"; ver="${spec#*=}"
      pub=$(curl -sSf "${LP}?ws.op=getPublishedSources&source_name=${src}&version=${ver}&exact_match=true" \
        | jq -r ".entries[0].self_link // empty") || pub=""
      urls=""
      [ -n "${pub}" ] && urls=$(curl -sSf "${pub}?ws.op=sourceFileUrls" | jq -r ".[]") || urls=""
      if [ -z "${urls}" ]; then echo "${spec}" >> missing.txt; continue; fi
      for u in ${urls}; do curl -sSfLO "${u}" || { echo "${spec}" >> missing.txt; break; }; done
      echo "${spec}" >> from-launchpad.txt
    done < requested.txt
    chown -R "${HOST_UID}:${HOST_GID}" /out'
if [ -s "${STAGE}/ubuntu-sources/missing.txt" ]; then
  echo "錯誤：下列 Ubuntu 原始碼套件在 archive 與 Launchpad 都取不到這個版本：" >&2
  sed 's/^/   /' "${STAGE}/ubuntu-sources/missing.txt" >&2
  exit 1
fi
[ -f "${STAGE}/ubuntu-sources/from-launchpad.txt" ] \
  && echo "   archive 已沒有、改從 Launchpad 取得：$(tr '\n' ' ' < "${STAGE}/ubuntu-sources/from-launchpad.txt")"
rm "${STAGE}/ubuntu-sources/missing.txt"
echo "   $(wc -l < "${STAGE}/ubuntu-sources/requested.txt") 個原始碼套件"

cat > "${STAGE}/README.txt" <<EOF
線上共編文件伺服器（Online Editor）原始碼包
映像：${IMAGE_NAME}

本原始碼包是映像所含 MPL、GPL、LGPL 等開放原始碼元件的對應原始碼，以及編譯用的腳本。
各元件的授權總表見 licenses/third_party_licenses.txt。

| 檔案 | 內容 |
|---|---|
| build-scripts.tar.gz | 編譯與打包映像的腳本（script/build-from-source.sh、builder/、Dockerfile 等），說明見其中的 README.md |
| online-${ONLINE_TAG}.tar.gz | Collabora Online（${ONLINE_REPO} 的 tag ${ONLINE_TAG}）；engine（LibreOffice core 的 Collabora 版）在 online/engine，POCO 在 online/engine/external/poco |
| translations-${TRANSLATIONS_COMMIT:0:10}.tar.gz | engine 的介面翻譯（${TRANSLATIONS_REPO} 的 commit ${TRANSLATIONS_COMMIT}），解開後位於 online/engine/translations |
| engine-external-tarballs/ | engine 編譯時下載的第三方原始碼，編譯時放在 engine 的 TARFILE_LOCATION 即不必連網下載 |
| ubuntu-sources/ | 映像內 Ubuntu 24.04 系統套件的原始碼（apt-get source 格式；清單見 requested.txt） |
| licenses/ | 映像內的授權檔與 Ubuntu 套件清單 |
| SHA256SUMS | 以上檔案的 sha256 |

編譯方式：依 build-scripts 的 README.md「建置」，script/build-from-source.sh 會在 builder 容器內
以上述原始碼編譯 engine 與 online，script/build-docker-image.sh 再打包成映像；
產品名稱的替換與 EULA 的移除在 Dockerfile。
EOF

(cd "${STAGE}" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | xargs -d '\n' sha256sum > SHA256SUMS)
tar -cf "${OUT_DIR}/${NAME}.tar" -C "${OUT_DIR}" "${NAME}"
rm -rf "${STAGE}"
echo "== 完成：${OUT_DIR}/${NAME}.tar（$(du -h "${OUT_DIR}/${NAME}.tar" | cut -f1)）"
