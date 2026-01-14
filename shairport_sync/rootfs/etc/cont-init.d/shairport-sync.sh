#!/command/with-contenv bashio
# ==============================================================================
# Prepare the Shairport Sync service for running
# ==============================================================================

bashio::log.info "Preparing Shairport Sync environment..."

# Создаем необходимые директории (игнорируем если уже существуют)
mkdir -p /tmp/shairport-sync-metadata 2>/dev/null || true
mkdir -p /var/run/dbus 2>/dev/null || true

# Устанавливаем права доступа
chmod 755 /tmp/shairport-sync-metadata 2>/dev/null || true

bashio::log.info "Environment prepared successfully"
