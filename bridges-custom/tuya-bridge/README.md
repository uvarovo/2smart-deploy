# 2Smart Tuya Local Bridge

MQTT bridge between a local-network Tuya device (no cloud) and a 2Smart
Standalone platform (or any Homie 3.0.1 consumer).

Connects directly to a Tuya device over LAN using its `id`, `local_key`
and `ip`, subscribes to datapoint (DP) updates and republishes them as
Homie-compatible topics under `sweet-home/<deviceId>/...`.

## Features

- Direct LAN communication with Tuya devices via [`tuyapi`](https://github.com/codetheweb/tuyapi) (no Tuya cloud required).
- Full Homie 3.0.1 schema publication (`$homie`, `$name`, `$state`, `$nodes`, per-property `$datatype`, `$unit`, `$format`).
- Auto-detection of device type by DP signature (e.g. PTH-9CW = CO2 + Temperature + Humidity + Display Unit) with fallback to a DB of common DPs.
- Optional manual DP mapping via `DP_MAP` environment variable.
- Write support — `sweet-home/<deviceId>/device/<prop>/set` translates to `tuyapi.set({ dps: dpId, set: value })`.
- Auto-reconnect on device disconnect with 15 s backoff.
- Tolerant of TuyAPI v3.5 multi-frame parse errors (they are filtered).
- Graceful SIGTERM / SIGINT shutdown — publishes `$state=disconnected`, disconnects device, flushes MQTT.

## Requirements

- Node.js 18 LTS (the Docker image uses `node:18-alpine`).
- A Tuya device with known `device id`, `local_key` and static LAN IP.
  See [tuya-cli](https://github.com/TuyaAPI/cli) for obtaining local keys.
- Reachable MQTT broker (2Smart Standalone ships EMQX).

## Configuration

All configuration is via environment variables (a local `.env` file is
also loaded if present next to `app.js`).

| Variable         | Required | Default                  | Description                                                                      |
|------------------|----------|--------------------------|----------------------------------------------------------------------------------|
| `TUYA_DEVICE_ID` | yes      | —                        | Tuya device id (hex string).                                                     |
| `TUYA_LOCAL_KEY` | yes      | —                        | Device local key.                                                                |
| `TUYA_LOCAL_IP`  | yes      | —                        | Device IPv4 on the LAN.                                                          |
| `TUYA_VERSION`   | no       | `3.5`                    | TuyAPI protocol version (`3.1`, `3.3`, `3.4`, `3.5`).                            |
| `MQTT_URI`       | no       | `mqtt://localhost:1883`  | MQTT broker URL. Any `2smart-emqx` hostname is rewritten to `localhost` (host network mode). |
| `MQTT_USER`      | no       | `""`                     | MQTT username. When launched by 2smart-core this becomes the bridge instance id and is used as `DEVICE_ID` to satisfy EMQX ACL. |
| `MQTT_PASS`      | no       | `""`                     | MQTT password.                                                                   |
| `DEVICE_NAME`    | no       | `Tuya Device`            | Human-readable name exposed in Homie `$name`.                                    |
| `DEVICE_ID`      | no       | `MQTT_USER` or auto      | Override for the Homie topic prefix `sweet-home/<DEVICE_ID>`.                    |
| `POLL_INTERVAL`  | no       | `30` (seconds)           | How often to poll `device.get()` in addition to push events.                     |
| `DP_MAP`         | no       | —                        | Manual DP naming: `dpId:Name:unit:min:max,...`, e.g. `2:CO2:ppm:0:5000,18:Temperature:°C:-10:60`. |

See <a href=".env.example">`.env.example`</a> for a working template.

## Local development

```bash
npm install
cp .env.example .env        # fill in TUYA_* and MQTT_*
npm start                   # or: DEBUG=tuya* node app.js
```

## Docker

```bash
docker build -t 2smart-tuya-bridge .
docker run --rm --network host --env-file ./.env 2smart-tuya-bridge
```

Or with the included compose file:

```bash
docker compose up --build
```

`network_mode: host` is used so the bridge can see the Tuya device on the
LAN without extra NAT gymnastics; adjust if you need port isolation.

## MQTT topic layout

```
sweet-home/<DEVICE_ID>/$homie           -> "3.0.1"
sweet-home/<DEVICE_ID>/$name            -> DEVICE_NAME
sweet-home/<DEVICE_ID>/$state           -> init | ready | lost | alert | disconnected
sweet-home/<DEVICE_ID>/$nodes           -> "device"
sweet-home/<DEVICE_ID>/device/$properties
sweet-home/<DEVICE_ID>/device/<propId>              <- current value
sweet-home/<DEVICE_ID>/device/<propId>/$datatype
sweet-home/<DEVICE_ID>/device/<propId>/$unit
sweet-home/<DEVICE_ID>/device/<propId>/$format
sweet-home/<DEVICE_ID>/device/<propId>/set          <- write commands from UI
```

## License

MIT — see [LICENSE](LICENSE).
