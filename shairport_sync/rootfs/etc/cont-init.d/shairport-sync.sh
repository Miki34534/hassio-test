#!/usr/bin/with-contenv bashio

bashio::log.info "Starting Shairport Sync with MQTT support..."

# Создаём конфигурацию ALSA в /tmp (writable)
# Отключаем поиск PulseAudio плагинов
cat > /tmp/asound.conf << 'ALSA_EOF'
# Не использовать PulseAudio плагины
pcm_type.pulse {
    lib "/dev/null"
}

# Основное устройство по умолчанию
pcm.!default {
    type plug
    slave.pcm "dmixer"
}

ctl.!default {
    type hw
    card 0
}

# DMIX для совместного доступа
pcm.dmixer {
    type dmix
    ipc_key 1024
    slave {
        pcm "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 8192
        rate 44100
        format S16_LE
    }
    bindings {
        0 0
        1 1
    }
}

# Software volume control
pcm.softvol {
    type softvol
    slave.pcm "dmixer"
    control {
        name "PCM"
        card 0
    }
    min_dB -51.0
    max_dB 0.0
}
ALSA_EOF

# Устанавливаем переменные окружения для ALSA
export ALSA_CONFIG_PATH=/tmp/asound.conf
export ALSA_PLUGIN_DIR=/usr/lib/alsa-lib

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

# Проверка доступных аудио устройств (если команда доступна)
if command -v aplay >/dev/null 2>&1; then
    bashio::log.info "Available audio devices:"
    aplay -L 2>/dev/null | head -20 || bashio::log.warning "Could not list audio devices"
fi

bashio::log.info "ALSA cards:"
if [ -f /proc/asound/cards ]; then
    cat /proc/asound/cards
else
    bashio::log.warning "No sound cards found - audio may not work!"
fi

# Создание конфигурационного файла в /tmp
# Определяем backend на основе audio_device
if [ "${AUDIO_DEVICE}" = "pulse" ]; then
    OUTPUT_BACKEND="pa"
else
    OUTPUT_BACKEND="alsa"
fi

cat > /tmp/shairport-sync.conf << EOF
general = {
    name = "${AIRPLAY_NAME}";
    interpolation = "soxr";
    output_backend = "${OUTPUT_BACKEND}";
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
EOF

# Добавляем конфигурацию в зависимости от backend
if [ "${OUTPUT_BACKEND}" = "pa" ]; then
    cat >> /tmp/shairport-sync.conf << EOF
pa = {
    application_name = "Shairport Sync";
};
EOF
else
    cat >> /tmp/shairport-sync.conf << EOF
alsa = {
    output_device = "${AUDIO_DEVICE}";
    mixer_control_name = "PCM";
    mixer_type = "software";
    use_mmap_if_available = "no";
};
EOF
fi

cat >> /tmp/shairport-sync.conf << EOF
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
        cat >> /tmp/shairport-sync.conf << EOF
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
        cat >> /tmp/shairport-sync.conf << EOF
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

# Avahi уже настроен через rootfs/etc/avahi/avahi-daemon.conf
# Запускаем с использованием базового конфига

# Экспортируем переменные для дочерних процессов
export ALSA_CONFIG_PATH=/tmp/asound.conf

bashio::log.info "Starting Avahi daemon..."
avahi-daemon --daemonize --no-chroot

# Ждем запуска Avahi
sleep 2

bashio::log.info "Starting Shairport Sync daemon..."
bashio::log.info "Config file: /tmp/shairport-sync.conf"
bashio::log.info "ALSA config: /tmp/asound.conf"
