#!/usr/bin/with-contenv bashio

bashio::log.info "Starting Shairport Sync with MQTT support..."

# Отключаем PulseAudio плагины для ALSA
export ALSA_PLUGIN_DIR=/usr/lib/alsa-lib
export ALSA_CONFIG_PATH=/etc/asound.conf

# Настройка ALSA - отключаем PulseAudio
cat > /etc/asound.conf << 'ALSA_EOF'
pcm.!default {
    type hw
    card 0
    device 0
}

ctl.!default {
    type hw
    card 0
}

pcm.dmixer {
    type dmix
    ipc_key 1024
    slave {
        pcm "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 4096
        rate 44100
    }
    bindings {
        0 0
        1 1
    }
}

pcm.softvol {
    type softvol
    slave.pcm "dmixer"
    control {
        name "PCM"
        card 0
    }
}
ALSA_EOF

# Получение конфигурации из options
AIRPLAY_NAME=$(bashio::config 'airplay_name')
AUDIO_DEVICE=$(bashio::config 'audio_device')
LOG_LEVEL=$(bashio::config 'log_level')
MQTT_ENABLED=$(bashio::config 'mqtt_enabled')
MQTT_HOSTNAME=$(bashio::config 'mqtt_hostname')
MQTT_PORT=$(bashio::config 'mqtt_port')
MQTT_TOPIC=$(bashio::config 'mqtt_topic')
MQTT_USERNAME=$(bashio::config 'mqtt_username')
MQTT_PASSWORD=$(bashio::config 'mqtt_password')
ENABLE_IPV6=$(bashio::config 'enable_ipv6')

# Конвертация boolean в yes/no для Shairport Sync
MQTT_PUBLISH_PARSED="no"
if bashio::config.true 'mqtt_publish_parsed'; then
    MQTT_PUBLISH_PARSED="yes"
fi

MQTT_PUBLISH_COVER="no"
if bashio::config.true 'mqtt_publish_cover'; then
    MQTT_PUBLISH_COVER="yes"
fi

MQTT_ENABLE_REMOTE="no"
if bashio::config.true 'mqtt_enable_remote'; then
    MQTT_ENABLE_REMOTE="yes"
fi

# Avahi настройки
AVAHI_INTERFACES=$(bashio::config 'avahi_interfaces')
AVAHI_HOSTNAME=$(bashio::config 'avahi_hostname')
AVAHI_DOMAINNAME=$(bashio::config 'avahi_domainname')

bashio::log.info "AirPlay device name: ${AIRPLAY_NAME}"

# Проверка доступных аудио устройств
bashio::log.info "Available audio devices:"
aplay -L | head -20 || true

bashio::log.info "ALSA cards:"
cat /proc/asound/cards || bashio::log.warning "No sound cards found"

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
    ignore_volume_control = "no";
    volume_range_db = 60;
    playback_mode = "stereo";
};

diagnostics = {
    log_verbosity = 1;
};

alsa = {
    output_device = "${AUDIO_DEVICE}";
    mixer_control_name = "PCM";
    mixer_type = "software";
    use_mmap_if_available = "no";
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
if bashio::config.true 'mqtt_enabled'; then
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
use-ipv6=no
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
