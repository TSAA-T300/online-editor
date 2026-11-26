# online-editor

以 [Collabora Online](https://www.collaboraonline.com/) 與 LibreOffice core 的 MPL-2.0 原始碼自行編譯的線上 Office 文件編輯伺服器（coolwsd），以及打包成容器映像的建置腳本。
網頁上可多人同時編輯 docx／xlsx／pptx 等文件，透過 [WOPI](https://learn.microsoft.com/en-us/microsoft-365/cloud-storage-partner-program/online/) 向你的系統取檔、存檔。

- 不含 Collabora 的品牌與佈景主題，產品名稱為「Online Editor」（見「授權與商標」）。
- 不修改上游原始碼，只用官方的 configure 參數編譯；編譯後在 `Dockerfile` 替換產品名稱、刪除不適用的商業 EULA。
- 映像含 MPL、GPL、LGPL 等開放原始碼元件。把映像交給他人時，要一併提供對應原始碼（見「提供原始碼」）。

> 本專案與 Collabora Productivity Ltd.、The Document Foundation 無關，也不是它們的產品。

## 原始碼來源

版本鎖定在 `script/versions.sh`，升版時一起換。26.04 起 online 是 monorepo：engine（LibreOffice core 的 Collabora 版）在 `engine/`，POCO 在 `engine/external/poco`，都隨 online 的 tag 取得。

| 元件 | 版本 | 原始碼位置 | 授權 |
|---|---|---|---|
| Collabora Online（coolwsd、網頁編輯器與 engine） | tag `cp-26.04.6-2` | <https://github.com/CollaboraOnline/online.mirror/tree/cp-26.04.6-2> | MPL-2.0（engine 內含的第三方元件各有授權） |
| engine 的介面翻譯（含繁中） | `distro/collabora/coc-26.04` 的 commit `3ce4e01250efb782293196f6341a2c8aa405fd71` | <https://gerrit.collaboraoffice.com/translations> | MPL-2.0 |
| engine 編譯時下載的第三方原始碼 | 依 engine 的 `download.lst` | <https://dev-www.libreoffice.org/src/> | 各自不同 |
| POCO C++ Libraries（隨 engine 編譯，靜態連結進 coolwsd） | engine 的 `external/poco` 指定的版本 | 同上（第三方原始碼） | BSL-1.0 |
| 系統套件與字型 | Ubuntu 24.04（建置當下的版本，清單在映像內 `ubuntu-packages.tsv`） | <http://archive.ubuntu.com/ubuntu/>（`apt-get source`） | 各自不同 |

以上是上游位置；上游分支會停更、搬家或改成需要登入，交付時請用「提供原始碼」的原始碼包，不要只給這些網址。

## 為什麼自建

Collabora 官方發布的 CODE 執行檔與映像附有商業 EULA（需訂閱、30 天評估、稽核、英國法），是否適用 CODE 並不明確，不適合隨產品交付給客戶。原始碼採 MPL-2.0，自行編譯的版本不受該 EULA 約束（見「授權與商標」）。

## 建置

| 步驟 | 指令 | 說明 |
|---|---|---|
| 0. 預檢 | `bash script/build-from-source.sh --check` | 換一台電腦時先跑：檢查下方「host 需求」，有問題一次列出，不開始編譯 |
| 1. 編譯 | `bash script/build-from-source.sh` | 先做同樣的預檢，再取原始碼、在 builder 容器內編譯 engine 與 online，產物在 `build/instdir` |
| 2. 打包 | `bash script/build-docker-image.sh` | 以 `build/instdir` 打包 runtime 映像，名稱見 `script/get-image-name.sh` |
| 3. 原始碼包 | `bash script/build-source-package.sh` | 映像對應的原始碼包，見「提供原始碼」 |

- **為什麼分兩段**（不寫成一個多階段 Dockerfile）：編譯產物與 ccache 約 40 GB，放在 `BUILD_DIR` 可以指到大硬碟、重跑時沿用；放進 BuildKit cache 的話，一次 `docker builder prune` 就要重編 1 小時，編譯失敗時也沒有 `build/` 與 `build.log` 可查。換電腦最常失敗的原因（CA、記憶體、網路）兩種寫法都一樣，由預檢處理。
- **host 需求**：編譯器與 LibreOffice 的相依套件都在 builder 容器（`ubuntu:24.04`）內，host 只需要下列項目，預檢會逐一檢查：
    - bash、git、curl、sha256sum；Docker 與 buildx（Docker 23 以上）；x86_64；
    - 網路有 TLS 檢查（以自己的 CA 重新簽發憑證）時：含該 CA 的檔案（`HOST_CA_BUNDLE`，預設 `/etc/ssl/certs/ca-certificates.crt`；RHEL 系通常是 `/etc/pki/tls/certs/ca-bundle.crt`；不需要時設 `none`）；
    - 第一次編譯約 40 GB 可用空間（`MIN_FREE_GB`）、至少 8 GB 可用記憶體；平行編譯數依可用記憶體決定（每個工作預留 `GB_PER_JOB`=2 GB，不超過 CPU 核數），避免連結 engine 時記憶體不足；
    - 連得到 GitHub、gerrit.collaboraoffice.com（engine 的介面翻譯）、dev-www.libreoffice.org（engine 的第三方原始碼）、nodejs.org（編譯前端用的 Node.js，`versions.sh` 鎖定版本與 sha256，不進 runtime 映像）、registry.npmjs.org（前端套件）、archive.ubuntu.com（builder 的 apt 套件）。
- **資源**：約 40 GB 硬碟。64 核約 1 小時，engine 佔大部分。
    - 第一次編譯時另外下載 online（含 engine，約 1.5 GB，GitHub）與介面翻譯（`--depth=1`，gerrit），時間依網路速度另計。
    - `build/` 可用 `BUILD_DIR` 指到別處（例如空間較大的磁碟），各支腳本都會讀它。重跑時沿用編譯結果與 ccache。
- **產品名稱**：預設 `APP_NAME=Online Editor`、`APP_VENDOR=ITRI`。

### 升版時的原始碼來源

2026-11-26 查證：

- online：`CollaboraOnline/online` 沒有 26.04 的 tag，從 GitHub 的 [`CollaboraOnline/online.mirror`](https://github.com/CollaboraOnline/online.mirror) 取（`cp-26.04.6-2` 的 tag 與 commit hash 與 `gerrit.collaboraoffice.com/online` 一致）。mirror 可能比 gerrit 晚同步，升版前用 `git ls-remote` 比對兩邊的 tag。
- engine：26.04 起在 online 的 `engine/`，不必另外取得。25.04 以前的 engine 在另一個 repo（`gerrit.collaboraoffice.com/core`，GitHub 與 git.libreoffice.org 的 Collabora 分支停在 2026 年 4 月）。
- 介面翻譯：只在 `gerrit.collaboraoffice.com/translations`，分支 `distro/collabora/coc-26.04` 會持續前進，鎖定 online tag 日期之前的最後一個 commit。
- 從 gerrit 取原始碼不要加 `git -q`：gerrit 打包期間沒有任何輸出，有 TLS 檢查的網路可能把閒置的連線切斷（2026-11-26 院內實測約 245 秒後中斷）；有進度輸出時連線持續有資料，不會被切。
- 升版後更新本 README「原始碼來源」與 `third_party_licenses.txt` 的版本，並確認「授權與商標」的檢查項目。

## 執行

```
瀏覽器 ─(iframe，含 WebSocket)─► 反向代理（https）─► online-editor（coolwsd，http :9980）
online-editor ─(WOPI：CheckFileInfo、GetFile、PutFile)─► 你的系統（WOPI host）
```

你的系統要實作 WOPI host 端點、簽發 access token，並在網頁以表單 POST 開啟編輯器（網址取自 coolwsd 的 `/hosting/discovery`）。反向代理與編輯器網頁要同源，或另外設定 CORS 與 frame 政策。

| 環境變數 | 預設 | 說明 |
|---|---|---|
| `SERVICE_ROOT` | `/collabora` | 網址前綴，與反向代理轉送的路徑相同 |
| `WOPI_HOST` | （空） | 唯一允許呼叫的 WOPI host，例如 `http://backend:80` |
| `SSL_TERMINATION` | `true` | 反向代理以 https 對外；只用 http 時設 `false`，否則編輯器以 wss:// 連線失敗 |
| `LOG_LEVEL` | `warning` | coolwsd log 等級 |
| `BRAND_PRODUCT_NAME` | `Online Editor` | 編輯器畫面上的產品名稱（關於對話框、載入畫面、錯誤訊息） |
| `BRAND_PRODUCT_URL` | `/` | 產品名稱的連結 |
| `STATUSBAR_SAVE_INDICATOR` | `false` | 狀態列是否顯示「最後儲存於」。時間取自 WOPI CheckFileInfo 的 `LastModifiedTime`；WOPI host 為了避免共編衝突回舊時間時，這個顯示會一直不準 |
| `extra_params` | （空） | 其他 `--o:` 參數 |

- `start-collabora-online.sh` 一律關閉管理介面；`Dockerfile` 把映像內 `coolwsd.xml` 的 `net.post_allow` 收窄到 loopback，不開放 convert-to 等 REST 端點（刪除後檢查只剩 loopback，升版時格式改變會建置失敗；不以啟動參數依條目編號覆寫，因為 26.04 改了條目的格式與順序，照 25.04 的編號清除會漏掉 10/8、172.16/12）。`net.lok_allow` 在 26.04 預設為空清單，文件內的外部資料（`=WEBSERVICE()`、外部參照）只能連 WOPI host 與文件來源。建議反向代理另外封鎖 `<SERVICE_ROOT>/(cool|lool)/` 底下的 `convert-to`、`render-search-result`、`extract-link-targets`、`extract-document-structure`、`transform-document-structure`、`get-thumbnail`、`getMetrics`、`adminws`，因為 coolwsd 會放行 Host 是 WOPI host 的請求，而 Host 可以偽造。
- 容器沒有 `CAP_SYS_ADMIN` 時，coolwsd 會記錄 `Bind-Mounting fails` 並改用複製檔案，功能正常，只是開檔稍慢。
- 26.04 啟動時會記錄 `alias_groups: ignoring <host> [true] of group #1`：coolwsd 列舉群組內的 host 時，把 `start-collabora-online.sh` 設的 `host[@allow]=true` 屬性誤當成另一個 host；`WOPI_HOST` 仍以 allow=true 生效（上游 `wsd/HostUtil.cpp`），可以忽略。
- 以數字 UID 1001 執行，相容 k8s Pod Security。WOPI proof key 由各容器啟動時自行產生。
- 中文字型用 Ubuntu 的 `fonts-noto-cjk`，繁中 Windows 字型（微軟正黑體、新細明體、標楷體等）與韓文 Windows 字型（Gungsuh、Batang、Gulim 等，台灣的文件也會拿來寫中文）對應到它的繁中版本（`fonts/99-zh-tw-aliases.conf`）；沒有對應的字型會落到只有拉丁字的 DejaVu Sans，部分中文字顯示成方框。版面與原文件的差異主要來自字型；商用字型不可隨映像散布。

## 授權與商標

- **本 repo 的檔案**：以 MPL-2.0 授權（`LICENSE`）。`start-collabora-online.sh`、`builder/build-in-container.sh` 改寫自上游 Collabora Online 的 MPL-2.0 檔案。
- **映像內的元件**：Collabora Online、LibreOffice core 是 MPL-2.0，另含多種第三方授權（GPL、LGPL、Apache-2.0、SIL OFL、CC-BY-SA 等）。總表是 `third_party_licenses.txt`，映像內在 `/usr/share/doc/online-editor/`；完整條款在映像內的 `/opt/lokit/LICENSE`、`/opt/lokit/NOTICE`、`/usr/share/doc/coolwsd/THIRDPARTYLICENSES`。
- **copyleft 的範圍**：MPL-2.0 以檔案為單位，本 repo 新增的檔案與呼叫本服務的系統都不受它約束；呼叫端與本服務只透過 HTTP（WOPI）溝通，是各自獨立的程式，也不受映像內 GPL、LGPL 元件約束。
- **商業 EULA 不收錄**：Collabora 自家分支（2023 年起的 `co-23.05`～`co-26.04`）把 Collabora Office 的訂閱合約放在 engine 的 `readlicense_oo/license/EULA*`，建置時會裝進 `/opt/lokit`。合約寫明它依 MPL 3.2(b) 附加在 Collabora 自己散布的執行檔上，且不限制開放原始碼授權賦予的權利；本映像自行編譯，不適用這份合約。`Dockerfile` 刪除這兩個檔，避免收到映像的人誤以為要向 Collabora 訂閱。`LICENSE`、`NOTICE` 是授權聲明，保留。
- **升版時**：
    - 確認 online 的 `COPYING` 與 engine 的 `COPYING.MPL` 仍是 MPL-2.0（25.04.9-4 與 26.04.6-2 的 online `COPYING` 相同）；
    - 更新 `third_party_licenses.txt` 的版本；
    - `Dockerfile` 刪除 EULA 用的是 `rm`，檔名改變時建置會失敗，不會漏掉。
- **商標**：「Collabora」「Collabora Online」「Collabora Office」「CODE」是 Collabora Productivity Ltd. 的商標；「LibreOffice」是 The Document Foundation 的商標。本 repo 只以這些名稱說明原始碼的出處。
    - 產品名稱、介面與文宣都不可使用這些商標；
    - 預設的 `--with-app-name` 就是商標名稱，`build-from-source.sh` 一律覆寫；
    - 編輯器畫面上的產品名稱沒設定時，會顯示「Collabora Online Development Edition (unbranded)」，連結指向 Collabora 官網。`start-collabora-online.sh` 一律帶入 `user_interface.brandProductName`、`brandProductURL`；
    - engine 的產品名稱與廠商（關於對話框的 LOKit 版本，以及存回文件 `docProps/app.xml` 的產生者）原本是 `Collabora Office`／`Collabora`，`Dockerfile` 改寫 `main.xcd`、`versionrc`、`bootstraprc`，換成 `Online Editor`／`ITRI`；
    - 品牌與佈景主題在 Collabora 的私有 repo，自建版本不含；
    - 26.04 新增的新手導覽（每個使用者在每種文件類型第一次開啟時跳出，也可從「說明」再打開）標題寫死「Welcome to Collabora Online」，不套用 `brandProductName`。`Dockerfile` 把 `bundle.js` 與各語言翻譯檔中這個字串的「Collabora Online／Office」換成「Online Editor」，還有殘留時建置失敗。導覽大部分沒有繁中翻譯，而且整合方無法用 `ui_defaults` 關掉它（coolwsd 只接受 `Ruler`、`Sidebar` 等白名單的鍵），所以 `branding/patch-bundle.pl` 讓它一律視為已看過、不自動跳出；仍可從「說明」手動打開；
    - 關於對話框：版本旁的 git hash 原本連到 Collabora 的 gerrit，`branding/patch-bundle.pl` 改連本 repo 的 Release（映像的建置腳本與對應原始碼），顯示的 hash 仍是上游 online 的 commit。著作權原本是「Copyright © 年, ITRI.」，讀起來像整個程式屬於 ITRI，改成「Copyright © 年, ITRI (modifications). Based on Collabora Online and LibreOffice, © their respective contributors.」；
    - 編輯器「說明」分頁原本有連到 Collabora 上游的「回報問題」與「論壇」，以 `branding/branding.css` 隱藏。coolwsd 的每個編輯器頁面都會載入 `browser/<版本>/branding.css`，Dockerfile 把它放進 `browser/dist`；coolwsd 啟動時才讀取這個目錄，改了要重建映像。
    - 腳本內部的檔名與路徑（例如 `start-collabora-online.sh`、`/opt/cool`、coolwsd 的設定鍵）沿用上游的技術名稱，不是對外的產品名稱。

## 提供原始碼

把映像交給他人（`docker save` 給客戶、推上公開或私有 registry）就是散布，MPL 與 GPL、LGPL 要求讓收到的人取得對應原始碼。只給上游網址不夠可靠（見「升版時的原始碼來源」），所以每個映像版本都產生一份原始碼包：

1. 依「建置」的步驟 1、2 建好映像後，在同一個 `BUILD_DIR` 執行 `bash script/build-source-package.sh`，產出 `online-editor-source-<映像版本>.tar`。
    - 內容：本 repo 的建置腳本、online 原始碼（含 engine 與 POCO）、engine 的介面翻譯與編譯時下載的第三方原始碼、映像內 Ubuntu 套件的原始碼、授權檔與 `SHA256SUMS`，說明在包內的 `README.txt`。
    - 全部取自這次編譯實際使用的檔案，不重新向上游下載；Ubuntu 套件依映像內的 `ubuntu-packages.tsv` 下載同版本的原始碼：archive 只保留最新版，取不到的改向 Launchpad 取（保留所有發佈過的版本，連線走 https，網路有 TLS 檢查時同樣用 `HOST_CA_BUNDLE`）；兩處都取不到時腳本會停止並列出套件。
    - repo 有未 commit 的修改時腳本會停止：包內的建置腳本取自 HEAD，要和建置映像時一致。
2. 交付映像 tar 時，把原始碼包放在一起交付；發佈到 registry 時，把原始碼包放在收到的人取得得到的位置（例如本 repo 對應版本的 GitHub Release）。
    - 25.04.9.4-2 實測約 4.2 GB（engine 第三方原始碼 2.0 GB、Ubuntu 套件原始碼 1.4 GB、translations 370 MB、engine 340 MB），產生約 10 分鐘。
    - GitHub Release 單一附件上限 2 GB：整包 tar 傳不上去，改上傳包內的各個檔案（`engine-external-tarballs/`、`ubuntu-sources/` 各自打成 tar，超過 2 GB 時依大小拆成多份），並附上 `SHA256SUMS`、`README.txt`。
3. 至少保存到該映像版本不再提供給任何人之後三年。
4. 映像內的 `/usr/share/doc/online-editor/third_party_licenses.txt` 寫明原始碼包的取得方式。
