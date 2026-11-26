PRJ_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..
cd ${PRJ_DIR}

# 映像名稱不用 Collabora 商標（README「授權與商標」）
DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-itri/online-editor}"
# 上游版本 26.04.6.2，最後一碼是本 repo 的打包版次
VERSION="26.04.6.2-2"

echo "${DOCKER_IMAGE_NAME}:${VERSION}"
