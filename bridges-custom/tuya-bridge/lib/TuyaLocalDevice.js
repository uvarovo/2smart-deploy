'use strict';

const TuyAPI = require('tuyapi');
const EventEmitter = require('events');
const debug = require('debug')('tuya:device');

class TuyaLocalDevice extends EventEmitter {
    constructor({ id, key, ip, version = '3.5' }) {
        super();
        this._id = id;
        this._ip = ip;
        this._key = key;
        this._version = version;
        this._connected = false;
        this._reconnectTimer = null;
        this._dps = {};  // discovered datapoints: { dpId: { type, value } }

        this._device = new TuyAPI({
            id,
            key,
            ip,
            version,
            issueRefreshOnConnect: true
        });

        this._device.on('connected', () => {
            debug('Connected to %s', this._ip);
            this._connected = true;
            this._clearReconnect();
            this.emit('connected');
        });

        this._device.on('disconnected', () => {
            debug('Disconnected from %s', this._ip);
            this._connected = false;
            this.emit('disconnected');
            this._scheduleReconnect();
        });

        this._device.on('data', (data) => {
            debug('Raw data: %O', data);
            if (data && data.dps) {
                const updates = this._parseDps(data.dps);
                if (Object.keys(updates).length > 0) {
                    this.emit('data', updates);
                }
            }
        });

        this._device.on('error', (err) => {
            const msg = err.message || '';
            if (msg.includes('offset') ||
                msg.includes('buffer bounds') ||
                msg.includes('Prefix does not match')) {
                debug('Ignoring non-critical parse error (TuyAPI v3.5 multi-frame bug): %s', msg.slice(0, 60));
                return;
            }
            debug('Error: %s', msg);
            this.emit('error', err);
        });

        this._device.on('heartbeat', () => {
            this.emit('heartbeat');
        });
    }

    _parseDps(dps) {
        const updates = {};
        for (const [dpId, value] of Object.entries(dps)) {
            const type = this._detectType(value);
            const prev = this._dps[dpId];
            this._dps[dpId] = { type, value };

            // Report as update if value changed or first time seeing this DP
            if (!prev || prev.value !== value) {
                updates[dpId] = { type, value };
            }
        }
        return updates;
    }

    _detectType(value) {
        if (typeof value === 'boolean') return 'boolean';
        if (typeof value === 'number') {
            if (Number.isInteger(value)) return 'integer';
            return 'float';
        }
        if (typeof value === 'string') return 'string';
        return 'string';
    }

    get discoveredDps() {
        return { ...this._dps };
    }

    get isConnected() {
        return this._connected;
    }

    async connect() {
        try {
            debug('Connecting to %s (id: %s, version: %s)', this._ip, this._id, this._version);
            await this._device.connect();
        } catch (err) {
            debug('Connection failed: %s', err.message);
            this._scheduleReconnect();
            throw err;
        }
    }

    async getStatus() {
        try {
            const status = await this._device.get({ schema: true });
            debug('Status response: %O', status);
            if (status && status.dps) {
                const updates = this._parseDps(status.dps);
                return updates;
            }
            return {};
        } catch (err) {
            debug('getStatus error: %s', err.message);
            throw err;
        }
    }

    async setDp(dpId, value) {
        try {
            debug('Setting DP %s = %s', dpId, value);
            await this._device.set({ dps: dpId, set: value });
        } catch (err) {
            debug('setDp error: %s', err.message);
            throw err;
        }
    }

    async disconnect() {
        this._clearReconnect();
        if (this._connected) {
            try {
                await this._device.disconnect();
            } catch (err) {
                debug('Disconnect error: %s', err.message);
            }
        }
        this._connected = false;
    }

    _scheduleReconnect() {
        this._clearReconnect();
        this._reconnectTimer = setTimeout(async () => {
            debug('Reconnecting to %s...', this._ip);
            try {
                await this._device.connect();
            } catch (err) {
                debug('Reconnect failed: %s', err.message);
                this._scheduleReconnect();
            }
        }, 15000);
    }

    _clearReconnect() {
        if (this._reconnectTimer) {
            clearTimeout(this._reconnectTimer);
            this._reconnectTimer = null;
        }
    }
}

module.exports = TuyaLocalDevice;
