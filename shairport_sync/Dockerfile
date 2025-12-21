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
    xmltoman

# Клонирование и сборка Shairport Sync с поддержкой MQTT
WORKDIR /tmp
RUN git clone https://github.com/mikebrady/shairport-sync.git && \
    cd shairport-sync && \
    autoreconf -fi && \
    ./configure \
        --with-alsa \
        --with-avahi \
        --with-ssl=openssl \
        --with-soxr \
        --with-metadata \
        --with-mqtt-client \
        --with-dbus-interface \
        --with-stdout \
        --sysconfdir=/etc && \
    make && \
    make install && \
    cd .. && \
    rm -rf shairport-sync

# Удаление зависимостей для сборки
RUN apk del --no-cache \
    autoconf \
    automake \
    build-base \
    git \
    libtool \
    xmltoman

# Создание необходимых директорий
RUN mkdir -p /var/run/dbus

# Копирование файлов конфигурации и скриптов
COPY rootfs /

# Установка прав на выполнение для скриптов
RUN chmod a+x /etc/services.d/shairport-sync/run && \
    chmod a+x /etc/services.d/shairport-sync/finish && \
    chmod a+x /etc/cont-init.d/shairport-sync.sh

# Запуск D-Bus
CMD [ "/init" ]
