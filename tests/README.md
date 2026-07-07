# 2Smart E2E tests

Playwright smoke tests for a deployed 2Smart standalone system.

## What is covered

- Login page and authentication
- Service Manager — bridge list and on/off toggle (validates the stop-timeout fix)
- Market — Extensions tab loads and shows local extensions such as `co2-ventilation`
- Scenarios — list and create-scenario dropdown
- API health — `/api/v1/extensions`, `/api/v1/bridgeTypes`, `/api/v1/scenarios`, etc.

## Configuration

Set environment variables before running tests:

```bash
export BASE_URL=https://192.168.20.226
export LOGIN=admin
export PASSWORD=2Smart
```

If not set, the defaults above are used.

## Install

```bash
cd tests
npm install
npx playwright install chromium
```

## Run

```bash
# All tests
npm test

# API only (fast, no browser)
npm run test:api

# UI only
npm run test:ui

# Open HTML report
npm run test:report
```

## Notes

- The tests expect Chrome to be installed at `/usr/bin/google-chrome`. Change
  `specs/helpers.js` (`LAUNCH_OPTIONS.executablePath`) if your path differs.
- The OpenWeatherMap bridge id used in the tests is `ny0sjiye1yubi6ongmcw`.
  Update `specs/02-service-manager.spec.js` if your test server has a different id.
