// @ts-check
const { test, expect } = require('@playwright/test');
const { BASE_URL, login } = require('./helpers');

test.describe('Login', () => {
    test('страница логина доступна', async ({ page }) => {
        await page.goto(`${BASE_URL}/admin/login`, { waitUntil: 'networkidle', timeout: 20000 });
        await expect(page.locator('input[placeholder=Login]')).toBeVisible();
        await expect(page.locator('input[placeholder=Password]')).toBeVisible();
        await expect(page.locator('button:has-text("Sign in")')).toBeVisible();
    });

    test('неверный пароль — остаёмся на логине', async ({ page }) => {
        await page.goto(`${BASE_URL}/admin/login`, { waitUntil: 'networkidle', timeout: 20000 });
        await page.fill('input[placeholder=Login]', 'admin');
        await page.fill('input[placeholder=Password]', 'wrongpassword');
        await page.click('button:has-text("Sign in")');
        await page.waitForTimeout(3000);
        expect(page.url()).toContain('/login');
    });

    test('успешный вход → редирект на /admin', async ({ page }) => {
        await login(page);
        expect(page.url()).toBe(`${BASE_URL}/admin`);
    });

    test('после входа навигация содержит основные разделы', async ({ page }) => {
        await login(page);
        const nav = await page.$eval('[class*=nav],[class*=menu],[class*=sidebar]', el => el.innerText);
        expect(nav).toContain('Scenarios');
        expect(nav).toContain('Service Manager');
        expect(nav).toContain('Market');
    });
});
