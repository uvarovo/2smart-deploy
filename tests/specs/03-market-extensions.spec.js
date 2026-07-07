// @ts-check
const { test, expect } = require('@playwright/test');
const { BASE_URL, login } = require('./helpers');

test.describe('Market — Extensions', () => {
    test('вкладка Extensions открывается', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/market`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.waitForTimeout(2000);
        const body = await page.$eval('body', el => el.innerText);
        expect(body).toContain('Extensions');
    });

    test('список Extensions не пустой', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/market`, { waitUntil: 'networkidle', timeout: 20000 });

        // Кликаем на таб Extensions если он не активен
        const extTab = page.locator('text=Extensions');
        await extTab.click();

        // Ждём загрузки — пропадает "Loading"
        await page.waitForFunction(
            () => !document.body.innerText.includes('Loading addons') && !document.body.innerText.includes('Loading extensions'),
            { timeout: 15000 }
        ).catch(() => {/* if no loading text, already loaded */});

        await page.waitForTimeout(3000);
        const body = await page.$eval('body', el => el.innerText);

        // Должны быть extensions (мы точно знаем что они установлены)
        expect(body).not.toContain('No extensions');
        expect(body).not.toContain('Loading extensions');
    });

    test('co2-ventilation виден в маркете Extensions', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/market`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.locator('text=Extensions').click();
        await page.waitForFunction(
            () => !document.body.innerText.toLowerCase().includes('loading'),
            { timeout: 15000 }
        ).catch(() => {});
        await page.waitForTimeout(3000);

        const body = await page.$eval('body', el => el.innerText.toLowerCase());
        expect(body).toContain('co2');
    });

    test('список содержит стандартные extensions', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/market`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.locator('text=Extensions').click();
        await page.waitForTimeout(4000);

        const body = await page.$eval('body', el => el.innerText.toLowerCase());
        for (const name of [ 'thermostat', 'notifier', 'time relay' ]) {
            expect(body).toContain(name);
        }
    });

    test('вкладка Addons загружается (мосты)', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/market`, { waitUntil: 'networkidle', timeout: 20000 });
        // Используем role=tab чтобы избежать strict mode violation с "Loading addons..."
        await page.locator('role=tab[name="Addons"]').click();
        await page.waitForFunction(
            () => !document.body.innerText.includes('Loading addons'),
            { timeout: 15000 }
        ).catch(() => {});
        await page.waitForTimeout(3000);

        const body = await page.$eval('body', el => el.innerText.toLowerCase());
        // Должны быть хоть какие-то bridge types
        const hasBridges = [ 'bridge', 'zigbee', 'tuya', 'weather', 'modbus', 'knx' ]
            .some(kw => body.includes(kw));
        expect(hasBridges).toBe(true);
    });
});
