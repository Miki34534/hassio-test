#!/usr/bin/env bashio
# ==============================================================================
# Prepare the Shairport Sync service for running
# ==============================================================================

bashio::log.info "Preparing Shairport Sync environment..."

# Создаем необходимые директории
mkdir -p /tmp/shairport-sync-metadata
mkdir -p /var/run/dbus

# Устанавливаем права доступа
chmod 755 /tmp/shairport-sync-metadata

# Проверяем наличие MQTT брокера если MQTT включен
if bashio::config.true 'mqtt_enabled'; then
    mqtt_hostname=$(bashio::config 'mqtt_hostname' 'core-mosquitto')
    mqtt_port=$(bashio::config 'mqtt_port' '1883')
    
    bashio::log.info "Checking MQTT broker availability at ${mqtt_hostname}:${mqtt_port}..."
    
    # Простая проверка доступности
    if timeout 5 nc -z "${mqtt_hostname}" "${mqtt_port}" 2>/dev/null; then
        bashio::log.info "MQTT broker is available"
    else
        bashio::log.warning "Cannot connect to MQTT broker at ${mqtt_hostname}:${mqtt_port}"
        bashio::log.warning "Make sure Mosquitto broker addon is installed and running"
    fi
fi

bashio::log.info "Environment prepared successfully"
