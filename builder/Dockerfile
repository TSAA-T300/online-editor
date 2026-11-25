# Collabora Online 編譯環境。只用來編譯，不交付。
# 網路有 TLS 檢查時，該網路的 CA 由 script/build-from-source.sh 在執行時掛入，不寫進映像。
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update && apt-get -y build-dep libreoffice && \
    apt-get -y install git build-essential zip ccache autoconf automake libtool gperf nasm xsltproc flex bison \
      uuid-dev ninja-build wget curl rsync pkg-config lsb-release ca-certificates \
      libcap-dev libpam0g-dev libzstd-dev libpng-dev libcppunit-dev libssl-dev \
      python3-polib python3-lxml nodejs npm && \
    rm -rf /var/lib/apt/lists/*
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
