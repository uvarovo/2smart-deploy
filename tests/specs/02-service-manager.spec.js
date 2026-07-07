// @ts-check
const { test, expect } = require('@playwright/test');
const { BASE_URL, login, waitForLoaded } = require('./helpers');

// ID бриджа OpenWeatherMap, установленного на тестовом сервере
const BRIDGE_ID   = 'ny0sjiye1yubi6ongmcw';
const BRIDGE_NAME = 'OpenWeatherMap Bridge';

test.describe('Service Manager', () => {
    test('список сервисов загружается и показывает бридж', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/services`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.waitForTimeout(2000);
        const body = await page.$eval('body', el => el.innerText);
        expect(body).toContain(BRIDGE_NAME);
    });

    test('страница бриджа открывается', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/service/${BRIDGE_ID}`, { waitUntil: 'networkidle', timeout: 20000 });
        await waitForLoaded(page, 'Loading service');
        const body = await page.$eval('body', el => el.innerText);
        // должны видеть поля конфигурации
        expect(body).toContain('Service ID');
        expect(body).toContain(BRIDGE_ID);
    });

    test('переключатель бриджа выключен (контейнер не запущен)', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/service/${BRIDGE_ID}`, { waitUntil: 'networkidle', timeout: 20000 });
        await waitForLoaded(page, 'Loading service');
        const swInput = page.locator('[class*=Switch] input').first();
        await expect(swInput).not.toBeChecked();
    });

    test('включение бриджа через UI — переключатель становится ON, контейнер запускается', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/service/${BRIDGE_ID}`, { waitUntil: 'networkidle', timeout: 20000 });
        await waitForLoaded(page, 'Loading service');

        const swInput  = page.locator('[class*=Switch] input').first();
        const swLabel  = page.locator('[class*=Switch]').first();
        const isOn     = await swInput.evaluate(el => el.checked);

        if (!isOn) {
            // Включаем — кликаем по label/span, не по input (он скрыт)
            await swLabel.click();
            // Ждём пока UI обновится (может занять до 30 секунд — bridge запускается)
            await page.waitForFunction(
                () => {
                    const input = document.querySelector('[class*=Switch] input');
                    return input && input.checked;
                },
                { timeout: 40000 }
            );
        }

        await expect(swInput).toBeChecked();
    });

    test('выключение бриджа через UI — без таймаута, переключатель становится OFF', async ({ page }) => {
        await login(page);
        await page.goto(`${BASE_URL}/admin/service/${BRIDGE_ID}`, { waitUntil: 'networkidle', timeout: 20000 });
        await waitForLoaded(page, 'Loading service');

        const swInput = page.locator('[class*=Switch] input').first();
        const swLabel = page.locator('[class*=Switch]').first();
        const isOn    = await swInput.evaluate(el => el.checked);

        if (!isOn) {
            // Сначала включаем
            await swLabel.click();
            await page.waitForFunction(
                () => document.querySelector('[class*=Switch] input')?.checked,
                { timeout: 40000 }
            );
        }

        // Выключаем — засекаем время
        const t0 = Date.now();
        await swLabel.click();

        // Ждём выключения — не более 20 секунд (раньше было 60+ из-за бага)
        await page.waitForFunction(
            () => {
                const input = document.querySelector('[class*=Switch] input');
                return input && !input.checked;
            },
            { timeout: 20000 }
        );
        const elapsed = Date.now() - t0;

        await expect(swInput).not.toBeChecked();
        // Убеждаемся что выключение прошло быстро (менее 15 секунд)
        expect(elapsed).toBeLessThan(15000);
    });
});
