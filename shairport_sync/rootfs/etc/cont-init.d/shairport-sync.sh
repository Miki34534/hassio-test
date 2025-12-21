#!/usr/bin/with-contenv bashio

bashio::log.info "Starting Shairport Sync with MQTT support..."

# Получение конфигурации из options
AIRPLAY_NAME=$(bashio::config 'airplay_name')
LOG_LEVEL=$(bashio::config 'log_level')
MQTT_ENABLED=$(bashio::config 'mqtt_enabled')
MQTT_HOSTNAME=$(bashio::config 'mqtt_hostname')
MQTT_PORT=$(bashio::config 'mqtt_port')
MQTT_TOPIC=$(bashio::config 'mqtt_topic')
MQTT_USERNAME=$(bashio::config 'mqtt_username')
MQTT_PASSWORD=$(bashio::config 'mqtt_password')
MQTT_PUBLISH_PARSED=$(bashio::config 'mqtt_publish_parsed')
MQTT_PUBLISH_COVER=$(bashio::config 'mqtt_publish_cover')
MQTT_ENABLE_REMOTE=$(bashio::config 'mqtt_enable_remote')
ENABLE_IPV6=$(bashio::config 'enable_ipv6')

# Avahi настройки
AVAHI_INTERFACES=$(bashio::config 'avahi_interfaces')
AVAHI_HOSTNAME=$(bashio::config 'avahi_hostname')
AVAHI_DOMAINNAME=$(bashio::config 'avahi_domainname')

bashio::log.info "AirPlay device name: ${AIRPLAY_NAME}"

# Создание конфигурационного файла
cat > /etc/shairport-sync.conf << EOF
general = {
    name = "${AIRPLAY_NAME}";
    interpolation = "soxr";
    output_backend = "alsa";
    port = 5000;
    udp_port_base = 6001;
    udp_port_range = 10;
    drift_tolerance_in_seconds = 0.002;
    resync_threshold_in_seconds = 0.05;
    log_verbosity = 1;
    ignore_volume_control = "no";
    volume_range_db = 60;
    playback_mode = "stereo";
};

alsa = {
    output_device = "default";
    mixer_control_name = "PCM";
    mixer_type = "software";
};

metadata = {
    enabled = "yes";
    include_cover_art = "yes";
    pipe_name = "/tmp/shairport-sync-metadata";
};

sessioncontrol = {
};
EOF

# Настройка MQTT если включен
if [ "${MQTT_ENABLED}" = "true" ]; then
    bashio::log.info "MQTT is enabled"
    
    # Если username/password не заданы, используем без аутентификации
    if bashio::config.has_value 'mqtt_username'; then
        cat >> /etc/shairport-sync.conf << EOF
mqtt = {
    enabled = "yes";
    hostname = "${MQTT_HOSTNAME}";
    port = ${MQTT_PORT};
    username = "${MQTT_USERNAME}";
    password = "${MQTT_PASSWORD}";
    topic = "${MQTT_TOPIC}";
    publish_raw = "no";
    publish_parsed = "${MQTT_PUBLISH_PARSED}";
    publish_cover = "${MQTT_PUBLISH_COVER}";
    enable_remote = "${MQTT_ENABLE_REMOTE}";
};
EOF
    else
        cat >> /etc/shairport-sync.conf << EOF
mqtt = {
    enabled = "yes";
    hostname = "${MQTT_HOSTNAME}";
    port = ${MQTT_PORT};
    topic = "${MQTT_TOPIC}";
    publish_raw = "no";
    publish_parsed = "${MQTT_PUBLISH_PARSED}";
    publish_cover = "${MQTT_PUBLISH_COVER}";
    enable_remote = "${MQTT_ENABLE_REMOTE}";
};
EOF
    fi
else
    bashio::log.info "MQTT is disabled"
fi

# Создание metadata pipe
bashio::log.info "Metadata pipe created at /tmp/shairport-sync-metadata"
mkfifo -m 666 /tmp/shairport-sync-metadata 2>/dev/null || true

# Настройка Avahi
mkdir -p /var/run/dbus
rm -f /var/run/dbus/pid

# Запуск D-Bus
dbus-daemon --system --fork

# Настройка avahi-daemon.conf
cat > /etc/avahi/avahi-daemon.conf << EOF
[server]
use-ipv4=yes
use-ipv6=${ENABLE_IPV6}
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=yes

[publish]
publish-hinfo=no
publish-workstation=no

[reflector]
enable-reflector=no

[rlimits]
EOF

# Добавление интерфейсов если указаны
if [ -n "${AVAHI_INTERFACES}" ]; then
    sed -i "/\[server\]/a allow-interfaces=${AVAHI_INTERFACES}" /etc/avahi/avahi-daemon.conf
fi

# Hostname
if [ -n "${AVAHI_HOSTNAME}" ]; then
    sed -i "/\[server\]/a host-name=${AVAHI_HOSTNAME}" /etc/avahi/avahi-daemon.conf
fi

# Domain
if [ -n "${AVAHI_DOMAINNAME}" ]; then
    sed -i "/\[server\]/a domain-name=${AVAHI_DOMAINNAME}" /etc/avahi/avahi-daemon.conf
fi

bashio::log.info "Starting Avahi daemon..."
avahi-daemon --daemonize --no-chroot

# Ждем запуска Avahi
sleep 2

bashio::log.info "Starting Shairport Sync daemon..."
