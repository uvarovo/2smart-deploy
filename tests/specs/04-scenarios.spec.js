// @ts-check
const { test, expect } = require('@playwright/test');
const { BASE_URL, login } = require('./helpers');

test.describe('Scenarios', () => {
    test('страница сценариев открывается', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/scenarios`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.waitForTimeout(2000);
        expect(page.url()).toContain('/scenarios');
        const body = await page.$eval('body', el => el.innerText);
        // либо есть кнопка создания, либо список сценариев
        const hasContent = body.includes('Create scenario') || body.includes('scenario');
        expect(hasContent).toBe(true);
    });

    test('кнопка "Create scenario" видна', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/scenarios`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.waitForTimeout(2000);
        const body = await page.$eval('body', el => el.innerText);
        expect(body).toContain('Create scenario');
    });

    test('создание сценария — список типов открывается (dropdown)', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/scenarios`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.waitForTimeout(2000);

        // Нажимаем кнопку создания — открывается dropdown со списком типов
        await page.click('text=Create scenario');
        await page.waitForTimeout(3000);

        const body = await page.$eval('body', el => el.innerText);
        // Dropdown со списком типов должен содержать известные типы
        expect(body).toContain('Thermostat');
        expect(body.toLowerCase()).toContain('co2 ventilation');
    });

    test('MQTT API — эндпоинт сценариев отвечает', async ({ request }) => {
        const loginResp = await request.post(`${BASE_URL}/api/v1/sessions`, {
            data    : { data: { username: 'admin', password: '2Smart' } },
            headers : { 'Content-Type': 'application/json' }
        });
        expect(loginResp.ok()).toBe(true);
        const { data: { accessToken } } = await loginResp.json();

        const scenResp = await request.get(`${BASE_URL}/api/v1/scenarios`, {
            headers : { 'x-access-token': accessToken }
        });
        expect(scenResp.ok()).toBe(true);
        const body = await scenResp.json();
        expect(body).toHaveProperty('status', 1);
        expect(Array.isArray(body.data)).toBe(true);
    });
});
