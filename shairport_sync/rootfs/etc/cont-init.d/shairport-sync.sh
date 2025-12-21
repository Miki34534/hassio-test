#!/usr/bin/with-contenv bashio

bashio::log.info "Starting Shairport Sync with MQTT support..."

# Создаём конфигурацию ALSA в /tmp (writable)
cat > /tmp/asound.conf << 'ALSA_EOF'
pcm_type.pulse {
    lib "/dev/null"
}

pcm.!default {
    type plug
    slave.pcm "dmixer"
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
        buffer_size 8192
        rate 44100
        format S16_LE
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
    min_dB -51.0
    max_dB 0.0
}
ALSA_EOF

export ALSA_CONFIG_PATH=/tmp/asound.conf
export ALSA_PLUGIN_DIR=/usr/lib/alsa-lib

# Получение конфигурации из options
AIRPLAY_NAME=$(bashio::config 'airplay_name')
AUDIO_DEVICE=$(bashio::config 'audio_device')
PULSE_SINK=$(bashio::config 'pulse_sink')
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

AVAHI_INTERFACES=$(bashio::config 'avahi_interfaces')
AVAHI_HOSTNAME=$(bashio::config 'avahi_hostname')
AVAHI_DOMAINNAME=$(bashio::config 'avahi_domainname')

bashio::log.info "AirPlay device name: ${AIRPLAY_NAME}"

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

# Определяем backend на основе audio_device
if [ "${AUDIO_DEVICE}" = "pulse" ]; then
    OUTPUT_BACKEND="pa"
else
    OUTPUT_BACKEND="alsa"
fi

# Создание ПОЛНОГО конфигурационного файла за один раз
cat > /tmp/shairport-sync.conf << CONF_EOF
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

CONF_EOF

# Добавляем конфигурацию аудио backend
if [ "${OUTPUT_BACKEND}" = "pa" ]; then
    if [ -n "${PULSE_SINK}" ]; then
        cat >> /tmp/shairport-sync.conf << CONF_EOF
pa = {
    application_name = "Shairport Sync";
    server = "/run/audio/pulse.sock";
    sink = "${PULSE_SINK}";
};

CONF_EOF
    else
        cat >> /tmp/shairport-sync.conf << CONF_EOF
pa = {
    application_name = "Shairport Sync";
    server = "/run/audio/pulse.sock";
};

CONF_EOF
    fi
else
    cat >> /tmp/shairport-sync.conf << CONF_EOF
alsa = {
    output_device = "${AUDIO_DEVICE}";
    mixer_control_name = "PCM";
    mixer_type = "software";
    use_mmap_if_available = "no";
};

CONF_EOF
fi

# Добавляем metadata секцию
cat >> /tmp/shairport-sync.conf << CONF_EOF
metadata = {
    enabled = "yes";
    include_cover_art = "yes";
    pipe_name = "/tmp/shairport-sync-metadata";
};

CONF_EOF

# Добавляем MQTT если включен
if bashio::config.true 'mqtt_enabled'; then
    bashio::log.info "MQTT is enabled"
    
    if bashio::config.has_value 'mqtt_username'; then
        cat >> /tmp/shairport-sync.conf << CONF_EOF
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

CONF_EOF
    else
        cat >> /tmp/shairport-sync.conf << CONF_EOF
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

CONF_EOF
    fi
else
    bashio::log.info "MQTT is disabled"
fi

# Добавляем sessioncontrol секцию
cat >> /tmp/shairport-sync.conf << CONF_EOF
sessioncontrol = {
};
CONF_EOF

# Создание metadata pipe
bashio::log.info "Metadata pipe created at /tmp/shairport-sync-metadata"
mkfifo -m 666 /tmp/shairport-sync-metadata 2>/dev/null || true

# Настройка Avahi
mkdir -p /var/run/dbus
rm -f /var/run/dbus/pid

dbus-daemon --system --fork

export ALSA_CONFIG_PATH=/tmp/asound.conf

bashio::log.info "Starting Avahi daemon..."
avahi-daemon --daemonize --no-chroot

sleep 2

bashio::log.info "Starting Shairport Sync daemon..."
bashio::log.info "Config file: /tmp/shairport-sync.conf"
bashio::log.info "ALSA config: /tmp/asound.conf"

# Debug - показываем сгенерированный конфиг
bashio::log.info "Generated config:"
cat /tmp/shairport-sync.conf
