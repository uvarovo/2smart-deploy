# 2Smart Standalone — deployment

Self-contained kit for deploying the **2Smart Standalone** home-automation
platform (MQTT broker, core, UI, MySQL, InfluxDB, backups, updater, and
18 built-in bridge types) on a fresh Linux server via Docker Compose.

This repo bundles:

- `docker-compose.yml` — the main service graph (core, UI, EMQX broker,
  MySQL, InfluxDB, time-series-service, scenario-runner, backup-service,
  updater, heartbeat, filebeat, nginx, ssl-certs).
- `docker-compose.custom.yml.example` — per-host overrides (SSL cert paths,
  optional extra port exposures). Copy to `docker-compose.custom.yml` and edit.
- `install_2smart.sh` — installs Docker Engine + Docker Compose on a fresh
  host, seeds `.env`, pulls images, starts the stack.
- `update_2smart.sh` — refreshes `docker-compose.yml` from the upstream
  release channel and does `pull → down → up -d`.
- `system/bridge-types/` — metadata catalogue for all built-in bridges
  (KNX, Modbus, Zigbee, Tuya, Xiaomi, esphome, OpenWeatherMap, Tesla,
  MQTT adapter, REST adapter, Grafana, certbot, auto-discovery, …).
- `bridges-custom/tuya-bridge/` — custom **Tuya Local** bridge (direct LAN,
  no Tuya cloud) with Homie 3.0.1 MQTT mapping. See its
  [README](bridges-custom/tuya-bridge/README.md).
- `.env.example` — all tunable environment variables with comments.

## What gets installed

| Service                   | Purpose                                             |
|---------------------------|-----------------------------------------------------|
| `2smart-core`             | Bridge/extension orchestrator. Uses Docker socket.  |
| `2smart-ui`               | Admin panel + end-user dashboard UI.                |
| `2smart-emqx`             | MQTT broker (EMQX) with MySQL-backed auth.          |
| `2smart-mysql`            | MySQL 5.7 for users, scenarios, bridge metadata.    |
| `client-dashboard-be`     | REST backend for the dashboard.                     |
| `influxdb`                | Time-series storage for device values.              |
| `time-series-service`     | Ingests MQTT values → InfluxDB.                     |
| `scenario-runner`         | Executes automation scenarios.                      |
| `2smart-nginx`            | Reverse proxy, terminates TLS.                      |
| `ssl-certs`               | Self-signed SSL on first boot.                      |
| `2smart-heartbeat`        | Per-service liveness to MQTT.                       |
| `2smart-filebeat`         | Container log → MQTT for in-UI log viewer.          |
| `backup-service`          | Scheduled MySQL + config snapshots.                 |
| `2smart-updater`          | Rolls bridge images on Market install/update.       |
| `2smart-updater-manager`  | Queues and throttles updater jobs.                  |

## Prerequisites

- Linux server (Ubuntu 22.04+ recommended), x86_64 or arm64.
- Root / `sudo` access.
- Ports free: `80`, `443` (or whatever you set as `NGINX_HTTPS_PORT`),
  `1883`, `8883`. Port `18083` (EMQX dashboard) only if you enable it in
  `docker-compose.custom.yml`.
- ~5 GB free disk for images, more for your data.

## Fresh install

```bash
# 1. Clone this repo into the target directory (path must match ROOT_DIR_2SMART)
sudo mkdir -p /opt/2smart
sudo chown $USER:$USER /opt/2smart
git clone https://github.com/uvarovo/2smart-deploy.git /opt/2smart
cd /opt/2smart

# 2. Configure env
cp .env.example .env
$EDITOR .env              # set HOSTNAME, ROOT_DIR_2SMART, strong passwords

# 3. (Optional) override ports / mount custom SSL cert
cp docker-compose.custom.yml.example docker-compose.custom.yml
$EDITOR docker-compose.custom.yml

# 4. Bootstrap Docker + 2smart
sudo ./install_2smart.sh

# ↑ the installer will:
#   - install Docker Engine and Docker Compose plugin
#   - pull all 2smart images
#   - start the stack
```

When the stack is up:

- Admin UI: `https://<HOSTNAME>:<NGINX_HTTPS_PORT>/admin`
- Default login: `admin` / `2Smart` (**change immediately** in *Settings → Security*).
- Market (bridges & extensions): `/admin/market`.

## Update

```bash
sudo ./update_2smart.sh
```

Grabs the latest `docker-compose.yml` from upstream release channel, pulls
new images, restarts. **Note**: this overwrites `docker-compose.yml` — if
you tweak it locally, keep edits in `docker-compose.custom.yml`.

## Custom Tuya Local bridge

The included `bridges-custom/tuya-bridge/` talks to Tuya devices directly
over LAN (no Tuya cloud needed). Build + run alongside the main stack:

```bash
cd bridges-custom/tuya-bridge
cp .env.example .env
$EDITOR .env              # fill TUYA_DEVICE_ID / _LOCAL_KEY / _LOCAL_IP
docker compose up -d --build
```

Once the bridge publishes to MQTT, its device shows up in the 2smart UI
automatically. See [bridges-custom/tuya-bridge/README.md](bridges-custom/tuya-bridge/README.md)
for DP mapping, auto-detection rules, and the full MQTT topic layout.

## Files **not** in this repo (on purpose)

| Ignored path              | Reason                                            |
|---------------------------|---------------------------------------------------|
| `.env`                    | Contains real secrets.                            |
| `docker-compose.custom.yml` | Contains per-host paths (SSL cert files).       |
| `system/bridges/`         | Runtime instance configs (per-device KNX/Tuya addresses, auth tokens). |
| `system/data/`, `system/dumps/`, `system/emqx/` | Live database + broker state. |
| `system/shared/`, `system/extensions/` | Filled at runtime when you install extensions via Market. |
| `docker-compose.yml.copy` | Automatic backup from `update_2smart.sh`.         |

Check `.gitignore` for the full list.

## License

The deployment manifests and bundled custom bridges are released under the
MIT / 2Smart Standalone license — see [LICENSE.txt](LICENSE.txt).
