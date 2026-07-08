#!/bin/sh
set -e

# Recover a 2Smart standalone stack after a host reboot.
# - Brings the compose project back up.
# - Waits for EMQX to accept MQTT connections.
# - Sends event=start to bridges that are stuck in stopped state after boot
#   (workaround for EMQX retained-message race >7000 topics).
# - Ensures scenario-runner is running.

PROJECT_DIR="${PROJECT_DIR:-/home/admin007}"
COMPOSE_FILE="${COMPOSE_FILE:-$PROJECT_DIR/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-$PROJECT_DIR/.env}"

if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
fi

MQTT_HOST="${MQTT_HOST:-2smart-emqx}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-${MQTT_ROOT_USERNAME}}"
MQTT_PASS="${MQTT_PASS:-${MQTT_ROOT_PASSWORD}}"
BRIDGE_IDS="${BRIDGE_IDS:-}"

log() {
    echo "[$(date -Iseconds)] $*"
}

wait_for_docker() {
    log "Waiting for Docker daemon..."
    while ! docker info >/dev/null 2>&1; do
        sleep 2
    done
    log "Docker daemon is ready."
}

bring_stack_up() {
    log "Bringing 2Smart stack up..."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
}

wait_for_mqtt() {
    log "Waiting for MQTT broker at $MQTT_HOST:$MQTT_PORT..."
    for i in $(seq 1 60); do
        if timeout 2 sh -c "</dev/tcp/$MQTT_HOST/$MQTT_PORT" 2>/dev/null; then
            log "MQTT broker is reachable."
            return 0
        fi
        sleep 2
    done
    log "ERROR: MQTT broker did not become reachable."
    return 1
}

start_stopped_bridges() {
    if [ -z "$BRIDGE_IDS" ]; then
        log "No BRIDGE_IDS configured; skipping bridge start recovery."
        return 0
    fi

    log "Starting stopped bridges via MQTT..."
    docker exec 2smart-core node -e "
const mqtt = require('mqtt');
const ids = process.env.BRIDGE_IDS.split(/\s+/).filter(Boolean);
const client = mqtt.connect('mqtt://${MQTT_HOST}:${MQTT_PORT}', {
    username: '${MQTT_USER}',
    password: '${MQTT_PASS}'
});
client.on('connect', async () => {
    for (const id of ids) {
        await new Promise(r => client.publish('bridges/' + id + '/event/set', 'start', { qos: 1 }, r));
        await new Promise(r => setTimeout(r, 2000));
    }
    client.end();
    process.exit(0);
});
client.on('error', (e) => { console.error(e); process.exit(1); });
" 2>/dev/null
}

ensure_scenario_runner() {
    if docker ps --format '{{.Names}}' | grep -qx "scenario-runner"; then
        log "scenario-runner is already running."
        return 0
    fi
    log "scenario-runner is missing; starting it..."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d scenario-runner
}

main() {
    wait_for_docker
    bring_stack_up
    wait_for_mqtt
    # Give core a few seconds to subscribe before sending bridge events.
    sleep 10
    start_stopped_bridges
    ensure_scenario_runner
    log "Post-reboot recovery complete."
}

main "$@"
