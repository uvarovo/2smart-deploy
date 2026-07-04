#!/bin/sh
grep -q "if (!process.env.SMART_DOMAIN) return;" /app/lib/services/BridgeTypesManager.js || \
sed -i '/async syncRemoteBridgeType(type) {/a\        if (!process.env.SMART_DOMAIN) return;' /app/lib/services/BridgeTypesManager.js
exec node runner.js
