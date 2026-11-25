# 建置用的原始碼版本。升版時三個一起換，重新驗證編輯、存檔，並更新 README「原始碼來源」與 third_party_licenses.txt。
# engine（LibreOffice core 的 Collabora 分支）：GitHub 鏡像 LibreOffice/core，鎖定 commit（分支會持續前進）
CORE_REPO="${CORE_REPO:-https://github.com/LibreOffice/core}"
CORE_COMMIT="${CORE_COMMIT:-e588bf8da9ddb55823b88f5d2461d3935e9ed3fb}" # distro/collabora/co-25.04，版本 25.04.9.4
# online（coolwsd 與網頁前端）：GitHub CollaboraOnline/online，與 engine 版本相同的 tag。
# 升到 26.04 時改用 https://github.com/CollaboraOnline/online.mirror：CollaboraOnline/online 沒有 26.04 的 tag。
# engine 在 GitHub 只到 2026 年 4 月，更新的版本只在 gerrit.collaboraoffice.com（見 README「升版時的原始碼來源」）
ONLINE_REPO="${ONLINE_REPO:-https://github.com/CollaboraOnline/online}"
ONLINE_TAG="${ONLINE_TAG:-cp-25.04.9-4}"
# online 25.04 靜態連結的 POCO（版本取自上游 docker/from-source/build.sh）
POCO_VERSION="1.12.5p2"
POCO_SHA256="4bdf352deef1dcc39260c1b43604236f5759dbdd9c695fffac23488f502f95a2"
