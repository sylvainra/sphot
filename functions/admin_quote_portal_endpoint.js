/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {handleAdminQuotePortalRequest} =
    require("./admin_quote_portal_api");

const TRUSTED_WEB_ORIGINS = new Set([
  "https://sphot.app",
  "https://www.sphot.app",
  "https://sphot-ab80b.web.app",
  "https://sphot-ab80b.firebaseapp.com",
]);

function allowedOrigin(origin) {
  return TRUSTED_WEB_ORIGINS.has(origin) ||
      /^http:\/\/(?:localhost|127\.0\.0\.1):\d{2,5}$/.test(origin);
}

// Point de consultation et de téléchargement SEULEMENT.
// Pas d'émission, pas de numéro DV, pas de mail ni d'écriture Firestore.
function registerAdminQuotePortalEndpoint({admin, onRequest}) {
  return onRequest({
    region: "us-central1",
    cpu: 1,
    memory: "512MiB",
    timeoutSeconds: 60,
    maxInstances: 5,
  }, async (req, res) => {
    res.set("Cache-Control", "private, no-store");
    res.set("X-Content-Type-Options", "nosniff");
    res.set("Vary", "Origin, Authorization");
    const origin = typeof req.get === "function" ? req.get("Origin") : "";
    if (origin) {
      if (!allowedOrigin(origin)) {
        res.status(403).json({success: false, error: "ORIGIN_DENIED"});
        return;
      }
      res.set("Access-Control-Allow-Origin", origin);
      res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.set("Access-Control-Allow-Headers",
          "Authorization, Content-Type");
    }
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    await handleAdminQuotePortalRequest(req, res, {
      auth: admin.auth(),
      db: admin.firestore(),
      bucket: admin.storage().bucket(),
    });
  });
}

module.exports = {registerAdminQuotePortalEndpoint, allowedOrigin};
