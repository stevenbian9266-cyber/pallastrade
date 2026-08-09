'use strict';

var crypto = require('crypto');

// src/webhooks.ts
function verifyWebhookSignature(payload, signature, timestamp, secret, toleranceSeconds = 300) {
  const ts = Number.parseInt(timestamp, 10);
  if (Number.isNaN(ts)) return false;
  const age = Math.abs(Math.floor(Date.now() / 1e3) - ts);
  if (age > toleranceSeconds) return false;
  const expected = crypto.createHmac("sha256", secret).update(`${timestamp}.${payload}`).digest("hex");
  try {
    return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
  } catch {
    return false;
  }
}

exports.verifyWebhookSignature = verifyWebhookSignature;
//# sourceMappingURL=webhooks.cjs.map
//# sourceMappingURL=webhooks.cjs.map