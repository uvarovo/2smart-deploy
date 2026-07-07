/**
 * Shared helpers for 2Smart UI tests.
 */

const BASE_URL = process.env.BASE_URL || 'https://192.168.20.226';
const LOGIN    = process.env.LOGIN    || 'admin';
const PASSWORD = process.env.PASSWORD || '2Smart';

/**
 * Launch options for system Chrome.
 */
const LAUNCH_OPTIONS = {
    executablePath : '/usr/bin/google-chrome',
    args           : [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage'
    ]
};

/**
 * Log in and return the page, already on /admin.
 */
async function login(page) {
    await page.goto(`${BASE_URL}/admin/login`, { waitUntil: 'networkidle', timeout: 20000 });
    await page.fill('input[placeholder=Login]', LOGIN);
    await page.fill('input[placeholder=Password]', PASSWORD);
    await page.click('button:has-text("Sign in")');
    await page.waitForURL(`${BASE_URL}/admin`, { timeout: 10000 });
}

/**
 * Wait until a text pattern is gone from the page body.
 */
async function waitForLoaded(page, loadingText = 'Loading', timeout = 20000) {
    await page.waitForFunction(
        (t) => !document.body.innerText.includes(t),
        loadingText,
        { timeout }
    );
}

module.exports = { BASE_URL, LAUNCH_OPTIONS, login, waitForLoaded };
