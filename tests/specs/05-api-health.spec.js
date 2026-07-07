// @ts-check
const { test, expect } = require('@playwright/test');
const { BASE_URL } = require('./helpers');

/**
 * API health checks — быстрые тесты без браузера.
 * Проверяют что backend отвечает корректно.
 */
test.describe('API Health', () => {
    let token;

    test.beforeAll(async ({ request }) => {
        const resp = await request.post(`${BASE_URL}/api/v1/sessions`, {
            data    : { data: { username: 'admin', password: '2Smart' } },
            headers : { 'Content-Type': 'application/json' }
        });
        expect(resp.ok()).toBe(true);
        const body = await resp.json();
        token = body.data.accessToken;
    });

    test('GET /api/v1/extensions — возвращает список', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/extensions`, {
            headers : { 'x-access-token': token }
        });
        expect(resp.ok()).toBe(true);
        const body = await resp.json();
        expect(body.status).toBe(1);
        expect(body.data.length).toBeGreaterThan(0);
    });

    test('GET /api/v1/extensions — co2-ventilation присутствует', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/extensions`, {
            headers : { 'x-access-token': token }
        });
        const { data } = await resp.json();
        const names = data.map(e => e.name);
        expect(names).toContain('@2smart/co2-ventilation');
    });

    test('GET /api/v1/extensions — нет пакетов с npmjs.org (проверка отвязки)', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/extensions`, {
            headers : { 'x-access-token': token }
        });
        const { data } = await resp.json();
        // Все пакеты должны быть локальными — у них нет ссылки на npmjs.org
        for (const ext of data) {
            if (ext.link) {
                expect(ext.link).not.toContain('registry.npmjs.org');
            }
        }
    });

    test('GET /api/v1/bridgeTypes — возвращает типы мостов', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/bridgeTypes`, {
            headers : { 'x-access-token': token }
        });
        expect(resp.ok()).toBe(true);
        const body = await resp.json();
        expect(body.status).toBe(1);
        expect(body.data.length).toBeGreaterThan(0);
    });

    test('GET /api/v1/bridgeTypes — список не пустой, есть knx-bridge', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/bridgeTypes`, {
            headers : { 'x-access-token': token }
        });
        const { data } = await resp.json();
        const types = data.map(b => b.type);
        expect(types.some(t => t && t.includes('knx'))).toBe(true);
    });

    test('GET /api/v1/scenarios — отвечает успехом', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/scenarios`, {
            headers : { 'x-access-token': token }
        });
        expect(resp.ok()).toBe(true);
        const body = await resp.json();
        expect(body.status).toBe(1);
    });

    test('GET /api/v1/simpleScenarioTypes — возвращает типы сценариев', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/simpleScenarioTypes`, {
            headers : { 'x-access-token': token }
        });
        expect(resp.ok()).toBe(true);
        const body = await resp.json();
        expect(body.status).toBe(1);
        expect(Array.isArray(body.data)).toBe(true);
    });

    test('GET /api/v1/simpleScenarioTypes — содержит базовые типы (thermostat, time relay)', async ({ request }) => {
        const resp = await request.get(`${BASE_URL}/api/v1/simpleScenarioTypes`, {
            headers : { 'x-access-token': token }
        });
        const { data } = await resp.json();
        const titles = data.map(t => (t.title || '').toLowerCase());
        expect(titles.some(t => t.includes('thermostat'))).toBe(true);
        expect(titles.some(t => t.includes('time relay') || t.includes('relay'))).toBe(true);
    });
});
