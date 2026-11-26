# Online Editor：以 Collabora Online 原始碼自行編譯的線上 Office 文件編輯伺服器（runtime 映像）
# 編譯產物 instdir 由 script/build-from-source.sh 產生，以具名 build context「instdir」傳入
# （見 script/build-docker-image.sh）；本檔只負責打包 runtime。
# 依上游 docker/from-source-gh-action/Dockerfile 的 final stage，engine 路徑改為 /opt/lokit。
FROM ubuntu:24.04

# 非 ASCII 檔名需要 UTF-8 locale
ENV LC_CTYPE=C.UTF-8

# libgssapi-krb5-2：自建的 engine 會連結它，上游清單沒有列（上游用的是官方預編 engine）
RUN apt-get update \
    && apt-get -y install libpng16-16 fontconfig adduser cpio tzdata findutils \
    libcap2-bin openssl \
    libxcb-shm0 libxcb-render0 libxrender1 libxext6 \
    fonts-wqy-zenhei fonts-wqy-microhei fonts-droid-fallback fonts-noto-cjk ca-certificates \
    libnss-wrapper libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/* \
    # 映像內每個系統套件與其原始碼套件的版本，script/build-source-package.sh 依此下載對應的原始碼
    && mkdir -p /usr/share/doc/online-editor \
    && dpkg-query -W -f='${Package}\t${Version}\t${source:Package}\t${source:Version}\n' \
        > /usr/share/doc/online-editor/ubuntu-packages.tsv

COPY --from=instdir / /
# Collabora 自家分支把 Collabora Office 的商業 EULA（訂閱合約）放在 engine 原始碼 readlicense_oo/license/，
# 建置時會一起裝進 /opt/lokit。它約束的是向 Collabora 取得的執行檔；本映像由 MPL-2.0 原始碼自行編譯，
# 不適用這份合約，留著會讓收到映像的人誤以為要向 Collabora 訂閱。授權聲明 LICENSE、NOTICE 保留（README「授權與商標」）
RUN rm /opt/lokit/EULA.odt /opt/lokit/EULA_en-US.rtf
# 本 repo 的檔案（啟動腳本、branding.css 等）以 MPL-2.0 授權，授權全文隨映像附上
COPY LICENSE third_party_licenses.txt /usr/share/doc/online-editor/
COPY start-collabora-online.sh /start-collabora-online.sh
# 繁中 Windows 字型對應到 Noto CJK TC；要在 coolwsd-systemplate-setup 之前，jail 才會帶到這份設定
COPY fonts/99-zh-tw-aliases.conf /etc/fonts/conf.d/99-zh-tw-aliases.conf
# 編輯器頁面一定會載入 browser/<版本>/branding.css（上游 wsd/FileServer.cpp）；用它隱藏連到 Collabora 上游的按鈕。
# coolwsd 啟動時才讀取這個目錄，改了要重建映像
COPY branding/branding.css /usr/share/coolwsd/browser/dist/branding.css
# 26.04 新增的新手導覽，標題寫死「Welcome to Collabora Online」，不套用 brandProductName（上游 browser/src/control/onboarding/OnboardingSteps.ts）。
# 英文原字串是翻譯的鍵，bundle.js 與各語言翻譯檔（單行 JSON）要一起改；只改這個字串，翻譯裡的 Collabora Online／Office 也換掉。
# 還有殘留時建置失敗，升版後字串改了會發現
RUN cd /usr/share/coolwsd/browser/dist && \
    sed -i 's|"Welcome to Collabora Online"|"Welcome to Online Editor"|' bundle.js && \
    sed -i -E 's#"Welcome to Collabora Online": "([^"]*)Collabora (Online|Office)([^"]*)"#"Welcome to Online Editor": "\1Online Editor\3"#' l10n/ui-*.json && \
    ! grep -rqF "Welcome to Collabora Online" . && \
    grep -qF '"Welcome to Online Editor"' bundle.js

# engine 的產品名稱與廠商不用 Collabora 商標：顯示在關於對話框的 LOKit 版本、engine 對話框，
# 也會寫進存回文件的產生者欄位（docProps/app.xml）。只改設定檔，不必重編 engine。
# 廠商的原值依版本不同（25.04 是 Collabora，26.04 是 Collabora Productivity Limited），比對時不寫死原值
RUN sed -i -e 's|<prop oor:name="ooName"><value>Collabora Office</value>|<prop oor:name="ooName"><value>Online Editor</value>|' \
        -e 's|<prop oor:name="ooVendor"><value>Collabora[^<]*</value>|<prop oor:name="ooVendor"><value>ITRI</value>|' \
        /opt/lokit/share/registry/main.xcd && \
    sed -i -e 's|^Vendor=Collabora.*$|Vendor=ITRI|' -e 's|^UpdateID=Collabora Office_|UpdateID=Online Editor_|' \
        /opt/lokit/program/versionrc && \
    sed -i -e 's|^ProductKey=Collabora Office |ProductKey=Online Editor |' /opt/lokit/program/bootstraprc && \
    ! grep -q '<value>Collabora' /opt/lokit/share/registry/main.xcd

# 原本由套件的 postinstall 做的設定
RUN chmod +x /start-collabora-online.sh && \
    setcap cap_fowner,cap_chown,cap_sys_chroot=ep /usr/bin/coolforkit-caps && \
    setcap cap_sys_admin=ep /usr/bin/coolmount && \
    adduser --quiet --system --group --home /opt/cool cool && \
    rm -rf /opt/cool && \
    mkdir -p /opt/cool/child-roots /opt/cool/cache && \
    chown cool: /opt/cool /opt/cool/child-roots /opt/cool/cache && \
    fc-cache /opt/lokit/share/fonts/truetype && \
    coolwsd-systemplate-setup /opt/cool/systemplate /opt/lokit >/dev/null 2>&1 && \
    touch /var/log/coolwsd.log && chown cool:cool /var/log/coolwsd.log && \
    chown -R cool:cool /etc/coolwsd && \
    find /opt/cool -user cool -exec chown -h 1001:1001 {} \; && \
    usermod -u 1001 cool && groupmod -g 1001 cool && \
    chown cool:cool /etc/coolwsd/coolwsd.xml && chmod 640 /etc/coolwsd/coolwsd.xml && \
    chown cool:cool /etc/coolwsd && \
    # WOPI proof key 由各容器啟動時自行產生
    rm -rf /etc/coolwsd/proof_key* && \
    chown cool:cool /start-collabora-online.sh

EXPOSE 9980
# 以數字 UID 執行，相容 k8s Pod Security
USER 1001
ENTRYPOINT ["/start-collabora-online.sh"]
