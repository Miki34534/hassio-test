#!/command/with-contenv bashio
# ==============================================================================
# Start Shairport Sync service
# ==============================================================================

set -e  # Выход при ошибке

bashio::log.info "Starting Shairport Sync with MQTT support..."

# === ALSA ===
export ALSA_CONFIG_PATH=/tmp/asound.conf
export ALSA_PLUGIN_DIR=/usr/lib/alsa-lib

# === PulseAudio ===
export PULSE_SERVER=/run/audio/pulse.sock
export PULSE_COOKIE=/run/audio/pulse.cookie

# Получаем конфигурацию
NAME=$(bashio::config 'airplay_name')
MQTT_ENABLED=$(bashio::config 'mqtt_enabled')
MQTT_HOSTNAME=$(bashio::config 'mqtt_hostname')
MQTT_PORT=$(bashio::config 'mqtt_port')
MQTT_TOPIC=$(bashio::config 'mqtt_topic')
MQTT_PUBLISH_PARSED=$(bashio::config 'mqtt_publish_parsed')
MQTT_PUBLISH_COVER=$(bashio::config 'mqtt_publish_cover')
MQTT_ENABLE_REMOTE=$(bashio::config 'mqtt_enable_remote')

bashio::log.info "AirPlay device name: ${NAME}"

# Получаем интерфейс
INTERFACE="auto"
if bashio::config.has_value 'avahi_interfaces'; then # Обратите внимание на имя опции!
    INTERFACE=$(bashio::config 'avahi_interfaces')   # Обратите внимание на имя опции!
fi

bashio::log.info "Network interface setting: ${INTERFACE}"

# Создаем необходимые директории
mkdir -p /var/run/dbus 2>/dev/null || true
mkdir -p /tmp/shairport-sync-metadata 2>/dev/null || true

# Формируем интерфейсную часть конфига
INTERFACE_CONFIG=""
if [ "${INTERFACE}" != "auto" ] && [ -n "${INTERFACE}" ]; then
    bashio::log.info "Using specific network interface: ${INTERFACE}"
    INTERFACE_CONFIG="    interface = \"${INTERFACE}\";"
else
    bashio::log.info "Using automatic interface detection"
    # INTERFACE_CONFIG остается пустым
fi

# Формируем MQTT часть конфига
MQTT_CONFIG=""
if bashio::var.true "${MQTT_ENABLED}"; then
    bashio::log.info "Enabling MQTT integration..."
    bashio::log.info "MQTT Broker: ${MQTT_HOSTNAME}:${MQTT_PORT}"

    PARSED="no"
    COVER="no"
    REMOTE="no"

    bashio::var.true "${MQTT_PUBLISH_PARSED}" && PARSED="yes"
    bashio::var.true "${MQTT_PUBLISH_COVER}" && COVER="yes"
    bashio::var.true "${MQTT_ENABLE_REMOTE}" && REMOTE="yes"

    MQTT_CONFIG="
mqtt = {
    enabled = \"yes\";
    hostname = \"${MQTT_HOSTNAME}\";
    port = ${MQTT_PORT};
    topic = \"${MQTT_TOPIC}\";
    publish_parsed = \"${PARSED}\";
    publish_cover = \"${COVER}\";
    enable_remote = \"${REMOTE}\";"

    # Добавляем аутентификацию MQTT если указана
    if bashio::config.has_value 'mqtt_username'; then
        MQTT_USERNAME=$(bashio::config 'mqtt_username')
        MQTT_PASSWORD=$(bashio::config 'mqtt_password')
        bashio::log.info "Using MQTT authentication"
        MQTT_CONFIG="${MQTT_CONFIG}
    username = \"${MQTT_USERNAME}\";
    password = \"${MQTT_PASSWORD}\";"
    fi

    MQTT_CONFIG="${MQTT_CONFIG}
};"
else
    bashio::log.info "MQTT is disabled"
    # MQTT_CONFIG остается пустым
fi

# Создаем базовый конфигурационный файл, подставляя готовые блоки
cat > /tmp/shairport-sync.conf << EOF
general = {
    name = "${NAME}";
    output_backend = "alsa";
    port = 5000;
    udp_port_base = 6001;
    udp_port_range = 10;
${INTERFACE_CONFIG}
};

alsa = {
    output_device = "default";
};

metadata = {
    enabled = "yes";
    include_cover_art = "yes";
    pipe_name = "/tmp/shairport-sync-metadata";
};
${MQTT_CONFIG}
EOF

bashio::log.info "Configuration file created"

# Показываем конфигурацию для отладки
bashio::log.debug "Shairport Sync configuration:"
cat /tmp/shairport-sync.conf | while read line; do
    bashio::log.debug "$line"
done

# Запускаем D-Bus если еще не запущен
if ! pgrep -x "dbus-daemon" > /dev/null; then
    bashio::log.info "Starting D-Bus..."
    dbus-daemon --system --nofork --nopidfile &
    sleep 2
fi

# Запускаем Shairport Sync с конфигурационным файлом
bashio::log.info "Starting Shairport Sync daemon..."
exec shairport-sync -c /tmp/shairport-sync.conf -v
