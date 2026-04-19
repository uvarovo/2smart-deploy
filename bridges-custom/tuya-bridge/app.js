'use strict';

const fs = require('fs');
const path = require('path');
const mqtt = require('mqtt');
const debug = require('debug')('tuya:bridge');
const TuyaLocalDevice = require('./lib/TuyaLocalDevice');

// --- Load .env ---
const envPath = path.join(__dirname, '.env');
if (fs.existsSync(envPath)) {
    for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const idx = trimmed.indexOf('=');
        if (idx === -1) continue;
        const key = trimmed.slice(0, idx).trim();
        let val = trimmed.slice(idx + 1).trim();
        if ((val.startsWith('"') && val.endsWith('"')) ||
            (val.startsWith("'") && val.endsWith("'"))) {
            val = val.slice(1, -1);
        }
        if (!process.env[key]) process.env[key] = val;
    }
}

// --- Config ---
const TUYA_DEVICE_ID = process.env.TUYA_DEVICE_ID;
const TUYA_LOCAL_KEY = process.env.TUYA_LOCAL_KEY;
const TUYA_LOCAL_IP  = process.env.TUYA_LOCAL_IP;
const TUYA_VERSION   = process.env.TUYA_VERSION || '3.5';
// In host network mode, 2smart-emqx is not resolvable — use localhost
const MQTT_URI       = (process.env.MQTT_URI || 'mqtt://localhost:1883').replace('2smart-emqx', 'localhost');
const MQTT_USER      = process.env.MQTT_USER || '';
const MQTT_PASS      = process.env.MQTT_PASS || '';
const DEVICE_NAME    = process.env.DEVICE_NAME || 'Tuya Device';
// When launched by 2smart-core, MQTT_USER is the bridge instance ID — use it as DEVICE_ID
// so EMQX ACL allows publishing to sweet-home/{MQTT_USER}/...
const DEVICE_ID      = process.env.DEVICE_ID || process.env.MQTT_USER || `tuya-${(TUYA_DEVICE_ID || 'unknown').slice(-8)}`;
const POLL_INTERVAL  = parseInt(process.env.POLL_INTERVAL || '30', 10) * 1000;

// Optional: DP name mapping from file or env
// Format: "2:CO2:ppm,18:Temperature:°C,19:Humidity:%"
const DP_MAP_RAW     = process.env.DP_MAP || '';

// --- Validate ---
if (!TUYA_DEVICE_ID || !TUYA_LOCAL_KEY || !TUYA_LOCAL_IP) {
    console.error('Required: TUYA_DEVICE_ID, TUYA_LOCAL_KEY, TUYA_LOCAL_IP');
    process.exit(1);
}

// --- Known Tuya DP database ---
// Common datapoints across Tuya device categories
const KNOWN_DPS = {
    // Temperature & Humidity sensors
    '1':  { names: ['Power', 'Switch'], unit: '' },
    '2':  { names: ['CO2', 'Current Temperature'], unit: 'ppm', formatMin: '0', formatMax: '5000' },
    '18': { names: ['Temperature'], unit: '°C', formatMin: '-10', formatMax: '60' },
    '19': { names: ['Humidity'], unit: '%', formatMin: '0', formatMax: '100' },
    '20': { names: ['Temperature'], unit: '°C', formatMin: '-10', formatMax: '60' },
    '21': { names: ['Humidity'], unit: '%', formatMin: '0', formatMax: '100' },
    '101': { names: ['Display Unit'], unit: '' },
    // Air quality
    '22': { names: ['PM2.5'], unit: 'µg/m³', formatMin: '0', formatMax: '999' },
    '23': { names: ['TVOC'], unit: 'mg/m³', formatMin: '0', formatMax: '10' },
    '24': { names: ['HCHO'], unit: 'mg/m³', formatMin: '0', formatMax: '5' },
    // Common switch/relay
    '9':  { names: ['Countdown'], unit: 's' },
    '10': { names: ['Switch 2'], unit: '' },
    '11': { names: ['Switch 3'], unit: '' },
    '12': { names: ['Switch 4'], unit: '' },
};

// Device signatures: known DP combinations → specific names
const DEVICE_SIGNATURES = {
    // PTH-9CW: CO2 + Temp + Humidity + Unit
    '2,18,19,101': {
        '2':   { name: 'CO2', unit: 'ppm', formatMin: '0', formatMax: '5000' },
        '18':  { name: 'Temperature', unit: '°C', formatMin: '-10', formatMax: '60' },
        '19':  { name: 'Humidity', unit: '%', formatMin: '0', formatMax: '100' },
        '101': { name: 'Display Unit', unit: '' },
    },
    // TH sensor (common Tuya temp/humidity)
    '1,2,3': {
        '1':  { name: 'Temperature', unit: '°C', formatMin: '-20', formatMax: '60' },
        '2':  { name: 'Humidity', unit: '%', formatMin: '0', formatMax: '100' },
        '3':  { name: 'Battery', unit: '%', formatMin: '0', formatMax: '100' },
    },
    '20,21': {
        '20': { name: 'Temperature', unit: '°C', formatMin: '-20', formatMax: '60' },
        '21': { name: 'Humidity', unit: '%', formatMin: '0', formatMax: '100' },
    },
};

// --- Parse DP map ---
// Format: "dpId:Name:unit:min:max,..."
// Example: "2:CO2:ppm:0:5000,18:Temperature:°C:-10:60"
const dpMap = {};
if (DP_MAP_RAW) {
    for (const entry of DP_MAP_RAW.split(',')) {
        const parts = entry.trim().split(':');
        if (parts.length >= 2) {
            const dpId = parts[0].trim();
            dpMap[dpId] = {
                name: parts[1].trim(),
                unit: parts[2] ? parts[2].trim() : '',
                formatMin: parts[3] ? parts[3].trim() : '',
                formatMax: parts[4] ? parts[4].trim() : ''
            };
        }
    }
    debug('DP map loaded from env: %O', dpMap);
}

// Auto-detect device by DP signature after first data
let signatureMatched = false;
function tryMatchSignature(discoveredDpIds) {
    if (signatureMatched || Object.keys(dpMap).length > 0) return;
    const sig = discoveredDpIds.sort((a, b) => parseInt(a) - parseInt(b)).join(',');
    debug('Trying signature match: %s', sig);

    // Try exact signature match
    if (DEVICE_SIGNATURES[sig]) {
        Object.assign(dpMap, DEVICE_SIGNATURES[sig]);
        console.log('Auto-detected device signature:', sig);
        signatureMatched = true;
        return;
    }

    // Fallback: match individual DPs from known database
    for (const dpId of discoveredDpIds) {
        if (!dpMap[dpId] && KNOWN_DPS[dpId]) {
            dpMap[dpId] = {
                name: KNOWN_DPS[dpId].names[0],
                unit: KNOWN_DPS[dpId].unit || '',
                formatMin: KNOWN_DPS[dpId].formatMin || '',
                formatMax: KNOWN_DPS[dpId].formatMax || ''
            };
        }
    }
    if (Object.keys(dpMap).length > 0) {
        console.log('Auto-matched known DPs:', Object.entries(dpMap).map(([k, v]) => `${k}=${v.name}`).join(', '));
        signatureMatched = true;
    }
}

// --- MQTT ---
const BASE = `sweet-home/${DEVICE_ID}`;
let mqttClient;
let mqttConnected = false;
const publishedDps = new Set();  // track which DPs have Homie schema published

function mqttPublish(topic, value, opts = {}) {
    const defaults = { retain: true, qos: 1 };
    mqttClient.publish(topic, String(value), { ...defaults, ...opts });
}

function publishDeviceSchema() {
    debug('Publishing device schema: %s', DEVICE_ID);
    mqttPublish(`${BASE}/$homie`, '3.0.1');
    mqttPublish(`${BASE}/$name`, DEVICE_NAME);
    mqttPublish(`${BASE}/$state`, 'init');
    mqttPublish(`${BASE}/$localip`, TUYA_LOCAL_IP);
    mqttPublish(`${BASE}/$mac`, `AA:BB:CC:${TUYA_DEVICE_ID.slice(-6, -4)}:${TUYA_DEVICE_ID.slice(-4, -2)}:${TUYA_DEVICE_ID.slice(-2)}`);
    mqttPublish(`${BASE}/$fw/name`, '2smart-tuya-bridge');
    mqttPublish(`${BASE}/$fw/version`, '1.0.0');
    mqttPublish(`${BASE}/$implementation`, 'tuya-local');
    // $nodes will be published after DP discovery
}

function dpPropertyId(dpId) {
    const mapped = dpMap[dpId];
    if (mapped) return mapped.name.toLowerCase().replace(/[^a-z0-9]/g, '-');
    return `dp-${dpId}`;
}

function dpPropertyName(dpId) {
    const mapped = dpMap[dpId];
    if (mapped) return mapped.name;
    return `DP ${dpId}`;
}

function dpUnit(dpId) {
    const mapped = dpMap[dpId];
    return mapped ? mapped.unit : '';
}

function dpFormat(dpId) {
    const mapped = dpMap[dpId];
    if (mapped && mapped.formatMin && mapped.formatMax) {
        return `${mapped.formatMin}:${mapped.formatMax}`;
    }
    return '';
}

function homieDatatype(type, value) {
    if (type === 'boolean') return 'boolean';
    if (type === 'integer') return 'integer';
    if (type === 'float') return 'float';
    return 'string';
}

function publishDpSchema(dpId, type, value) {
    if (publishedDps.has(dpId)) return;
    publishedDps.add(dpId);

    const propId = dpPropertyId(dpId);
    const node = `${BASE}/device`;
    const prop = `${node}/${propId}`;

    mqttPublish(`${prop}/$name`, dpPropertyName(dpId));
    mqttPublish(`${prop}/$datatype`, homieDatatype(type, value));
    mqttPublish(`${prop}/$settable`, type === 'boolean' ? 'true' : 'false');
    mqttPublish(`${prop}/$retained`, 'true');

    const unit = dpUnit(dpId);
    if (unit) mqttPublish(`${prop}/$unit`, unit);

    const format = dpFormat(dpId);
    if (format) mqttPublish(`${prop}/$format`, format);

    // Update $properties list
    updateNodeProperties();

    debug('Published schema for DP %s -> %s (type: %s)', dpId, propId, type);
}

function updateNodeProperties() {
    const props = Array.from(publishedDps)
        .map(dpId => dpPropertyId(dpId))
        .join(',');
    const node = `${BASE}/device`;
    mqttPublish(`${node}/$name`, DEVICE_NAME);
    mqttPublish(`${node}/$type`, 'tuya-device');
    mqttPublish(`${node}/$properties`, props);
    mqttPublish(`${node}/$state`, 'ready');
    mqttPublish(`${BASE}/$nodes`, 'device');
}

function publishDpValue(dpId, value) {
    const propId = dpPropertyId(dpId);
    const topic = `${BASE}/device/${propId}`;
    mqttPublish(topic, String(value));
    debug('DP %s (%s) = %s', dpId, propId, value);
}

function handleDpUpdates(updates) {
    // Try to auto-detect device on first data
    tryMatchSignature(Object.keys(updates));
    for (const [dpId, { type, value }] of Object.entries(updates)) {
        publishDpSchema(dpId, type, value);
        publishDpValue(dpId, value);
    }
}

// --- Subscribe to settable DPs ---
function subscribeToSetTopics() {
    const setTopic = `${BASE}/device/+/set`;
    mqttClient.subscribe(setTopic, { qos: 1 });
    debug('Subscribed to %s', setTopic);
}

// --- Main ---
mqttClient = mqtt.connect(MQTT_URI, {
    username: MQTT_USER,
    password: MQTT_PASS,
    will: {
        topic: `${BASE}/$state`,
        payload: 'lost',
        retain: true,
        qos: 1
    }
});

mqttClient.on('connect', () => {
    console.log('MQTT connected to', MQTT_URI);
    mqttConnected = true;
    publishDeviceSchema();
    subscribeToSetTopics();
    connectDevice();
});

mqttClient.on('offline', () => {
    console.log('MQTT offline, URI:', MQTT_URI, 'user:', MQTT_USER);
    mqttConnected = false;
});

mqttClient.on('error', (err) => {
    console.error('MQTT error:', err.message);
});

// Handle set commands from 2Smart UI
mqttClient.on('message', async (topic, message) => {
    // topic: sweet-home/{deviceId}/device/{propId}/set
    const parts = topic.split('/');
    if (parts.length === 5 && parts[4] === 'set') {
        const propId = parts[3];
        const val = message.toString();

        // Find DP ID by property ID
        for (const [dpId, info] of Object.entries(device.discoveredDps)) {
            if (dpPropertyId(dpId) === propId) {
                let setValue;
                if (info.type === 'boolean') {
                    setValue = val === 'true' || val === '1';
                } else if (info.type === 'integer') {
                    setValue = parseInt(val, 10);
                } else if (info.type === 'float') {
                    setValue = parseFloat(val);
                } else {
                    setValue = val;
                }
                debug('Set command: DP %s = %s (type: %s)', dpId, setValue, info.type);
                try {
                    await device.setDp(dpId, setValue);
                } catch (err) {
                    console.error('Failed to set DP', dpId, ':', err.message);
                }
                break;
            }
        }
    }
});

// --- Tuya device ---
const device = new TuyaLocalDevice({
    id: TUYA_DEVICE_ID,
    key: TUYA_LOCAL_KEY,
    ip: TUYA_LOCAL_IP,
    version: TUYA_VERSION
});

async function connectDevice() {
    try {
        await device.connect();
    } catch (err) {
        console.error('Device connection failed:', err.message);
        // TuyaLocalDevice handles reconnect internally
    }
}

device.on('connected', () => {
    console.log('Tuya device connected:', TUYA_LOCAL_IP);
    if (mqttConnected) {
        mqttPublish(`${BASE}/$state`, 'ready');
        mqttPublish(`${BASE}/device/$state`, 'ready');
    }
});

device.on('disconnected', () => {
    console.log('Tuya device disconnected');
    if (mqttConnected) {
        mqttPublish(`${BASE}/$state`, 'lost');
        mqttPublish(`${BASE}/device/$state`, 'lost');
    }
});

device.on('data', (updates) => {
    if (mqttConnected) {
        handleDpUpdates(updates);
    }
});

device.on('error', (err) => {
    console.error('Tuya device error:', err.message);
    if (mqttConnected) {
        mqttPublish(`${BASE}/$state`, 'alert');
    }
});

// --- Polling ---
setInterval(async () => {
    if (!device.isConnected) return;
    try {
        const updates = await device.getStatus();
        if (mqttConnected && Object.keys(updates).length > 0) {
            handleDpUpdates(updates);
        }
    } catch (err) {
        debug('Poll error: %s', err.message);
    }
}, POLL_INTERVAL);

// --- Heartbeat ---
setInterval(() => {
    if (mqttConnected) {
        mqttClient.publish(`${BASE}/$heartbeat`, 'ping', { retain: false, qos: 1 });
    }
}, 10000);

// --- Graceful shutdown ---
async function shutdown(signal) {
    console.log(`${signal} received, shutting down...`);
    if (mqttConnected) {
        mqttPublish(`${BASE}/$state`, 'disconnected');
    }
    await device.disconnect();
    setTimeout(() => {
        mqttClient.end(false, () => process.exit(0));
    }, 500);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

console.log(`Tuya Bridge starting: ${DEVICE_NAME} (${DEVICE_ID})`);
console.log(`  Device: ${TUYA_DEVICE_ID} @ ${TUYA_LOCAL_IP} (v${TUYA_VERSION})`);
console.log(`  MQTT: ${MQTT_URI}`);
console.log(`  Poll: ${POLL_INTERVAL / 1000}s`);
if (Object.keys(dpMap).length > 0) {
    console.log(`  DP map: ${Object.entries(dpMap).map(([k, v]) => `${k}=${v.name}`).join(', ')}`);
}
