#!/bin/sh
# 啟動 coolwsd。改寫自上游 docker/from-source-gh-action/start-collabora-online.sh（MPL-2.0）。
#
# 環境變數：
#   SERVICE_ROOT    網址前綴，需與反向代理轉送的路徑相同（預設 /collabora）
#   WOPI_HOST       唯一允許呼叫的 WOPI host，例如 http://backend:80
#   SSL_TERMINATION 前面的反向代理是否以 https 對外（預設 true）；只用 http 存取時（例如開發環境）設 false，
#                   否則編輯器會以 wss:// 連線而失敗
#   LOG_LEVEL       coolwsd log 等級（預設 warning）
#   BRAND_PRODUCT_NAME 編輯器顯示的產品名稱（關於對話框、載入畫面、錯誤訊息；預設 Online Editor）。
#                   沒設時 coolwsd 會顯示 Collabora 的名稱
#   BRAND_PRODUCT_URL  關於對話框產品名稱的連結（預設 /，即同一網站的首頁）；沒設時會連到 Collabora 官網
#   STATUSBAR_SAVE_INDICATOR 狀態列是否顯示「最後儲存於」（預設 false）。時間取自 WOPI CheckFileInfo 的
#                   LastModifiedTime；WOPI host 為了避免共編衝突回舊時間時（例如 IKM），這個顯示會一直不準
#   extra_params    其他 coolwsd --o: 參數，原樣附加
#
# TLS 由前面的反向代理終止，coolwsd 本身走 http。

SERVICE_ROOT="${SERVICE_ROOT-/collabora}"
SSL_TERMINATION="${SSL_TERMINATION:-true}"
LOG_LEVEL="${LOG_LEVEL:-warning}"
BRAND_PRODUCT_NAME="${BRAND_PRODUCT_NAME:-Online Editor}"
BRAND_PRODUCT_URL="${BRAND_PRODUCT_URL:-/}"
STATUSBAR_SAVE_INDICATOR="${STATUSBAR_SAVE_INDICATOR:-false}"

wopi_params=""
if [ -n "${WOPI_HOST}" ]; then
  wopi_params="--o:storage.wopi.alias_groups[@mode]=groups \
 --o:storage.wopi.alias_groups.group[0].host=${WOPI_HOST} \
 --o:storage.wopi.alias_groups.group[0].host[@allow]=true"
fi

# 不讓文件伺服器替外部做事（post_allow 只留 loopback、lok_allow 不允許其他主機）已在建置映像時寫進
# /etc/coolwsd/coolwsd.xml（見 Dockerfile），不在這裡依條目編號覆寫：條目的格式與順序隨版本改變，編號會清錯

# OpenShift／k8s 可能指定任意 UID，coolwsd 需要名為 cool 的使用者，以 nss_wrapper 對應
user_id=$(id -u)
group_id=$(id -g)
if [ "$user_id" -ne 1001 ]; then
  echo "cool:x:${user_id}:${group_id}::/opt/cool:/usr/sbin/nologin" >/tmp/passwd
  export NSS_WRAPPER_PASSWD=/tmp/passwd
  export NSS_WRAPPER_GROUP=/etc/group
  export LD_PRELOAD=libnss_wrapper.so
fi

# shellcheck disable=SC2086
exec /usr/bin/coolwsd --version --use-env-vars \
  --o:ssl.enable=false --o:ssl.termination="${SSL_TERMINATION}" \
  --o:net.service_root="${SERVICE_ROOT}" \
  --o:logging.level="${LOG_LEVEL}" --o:logging.color=false \
  --o:user_interface.brandProductName="${BRAND_PRODUCT_NAME}" \
  --o:user_interface.brandProductURL="${BRAND_PRODUCT_URL}" \
  --o:sys_template_path=/opt/cool/systemplate --o:child_root_path=/opt/cool/child-roots \
  --o:file_server_root_path=/usr/share/coolwsd --o:cache_files.path=/opt/cool/cache \
  --o:stop_on_config_change=true \
  --o:per_document.always_save_on_exit=true \
  --o:admin_console.enable=false \
  --o:user_interface.statusbar_save_indicator="${STATUSBAR_SAVE_INDICATOR}" \
  ${wopi_params} ${extra_params} "$@"
