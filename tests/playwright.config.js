// @ts-check
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
    testDir     : './specs',
    timeout     : 60000,
    retries     : 1,
    reporter    : [ [ 'list' ], [ 'html', { open: 'never', outputFolder: 'report' } ] ],

    use : {
        baseURL            : 'https://192.168.20.226',
        ignoreHTTPSErrors  : true,
        headless           : true,
        screenshot         : 'only-on-failure',
        video              : 'off',
        launchOptions      : {
            executablePath : '/usr/bin/google-chrome',
            args           : [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage'
            ]
        }
    }
});
