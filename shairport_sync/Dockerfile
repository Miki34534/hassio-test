ARG BUILD_FROM
FROM $BUILD_FROM

# Установка зависимостей для сборки и работы
RUN apk add --no-cache \
    alsa-lib \
    alsa-lib-dev \
    autoconf \
    automake \
    avahi \
    avahi-dev \
    build-base \
    dbus \
    ffmpeg-dev \
    git \
    libressl-dev \
    libconfig-dev \
    libdaemon-dev \
    libgcrypt-dev \
    libplist-dev \
    libsndfile-dev \
    libsodium-dev \
    libtool \
    mosquitto-dev \
    mosquitto-clients \
    popt-dev \
    pulseaudio-dev \
    soxr-dev \
    xmltoman \
    jq

# Клонирование и сборка Shairport Sync
WORKDIR /tmp
RUN git clone https://github.com/mikebrady/shairport-sync.git && \
    cd shairport-sync && \
    autoreconf -fi && \
    # Сборка без D-Bus интерфейса (MQTT достаточно для интеграции)
    ./configure \
        --with-alsa \
        --with-avahi \
        --with-ssl=openssl \
        --with-soxr \
        --with-metadata \
        --with-mqtt-client \
        --with-stdout \
        --without-dbus-interface \
        --sysconfdir=/etc && \
    make && \
    make install && \
    cd .. && \
    rm -rf shairport-sync

# Удаление build-зависимостей
RUN apk del --no-cache \
    autoconf \
    automake \
    build-base \
    git \
    libtool \
    xmltoman

# Копирование файлов конфигурации и скриптов
COPY rootfs /

# Установка прав на выполнение
RUN chmod a+x /etc/services.d/shairport-sync/run && \
    chmod a+x /etc/services.d/shairport-sync/finish && \
    chmod a+x /etc/cont-init.d/shairport-sync.sh
