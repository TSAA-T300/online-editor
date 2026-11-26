# 建置用的原始碼版本。升版時一起換，重新驗證編輯、存檔，並更新 README「原始碼來源」與 third_party_licenses.txt。
# online（coolwsd、網頁前端與 engine）：26.04 起是 monorepo，engine（LibreOffice core 的 Collabora 版）在 engine/，
# POCO 在 engine/external/poco。GitHub CollaboraOnline/online 沒有 26.04 的 tag，用同一組織的 online.mirror
# （tag 物件與 gerrit.collaboraoffice.com/online 相同）。
ONLINE_REPO="${ONLINE_REPO:-https://github.com/CollaboraOnline/online.mirror}"
ONLINE_TAG="${ONLINE_TAG:-cp-26.04.6-2}"
# engine 的介面翻譯：不在 monorepo 內，只在 gerrit。分支 distro/collabora/coc-26.04 會持續前進，
# 鎖定 online tag 日期（2026-11-18）之前的最後一個 commit
TRANSLATIONS_REPO="${TRANSLATIONS_REPO:-https://gerrit.collaboraoffice.com/translations}"
TRANSLATIONS_COMMIT="${TRANSLATIONS_COMMIT:-3ce4e01250efb782293196f6341a2c8aa405fd71}" # distro/collabora/coc-26.04，2026-10-29
# 編譯 online 網頁前端用的 Node.js（26.04 要求 >= 20；builder 的 Ubuntu 24.04 套件只有 18）。只在編譯時使用，不進 runtime 映像。
# 官方二進位檔，sha256 取自 https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt
NODE_VERSION="22.11.0"
NODE_SHA256="83bf07dd343002a26211cf1fcd46a9d9534219aad42ee02847816940bf610a72"
