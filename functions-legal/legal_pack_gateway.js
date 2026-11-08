"use strict";

// Gateway for the FIVE initial documents (54 articles): no implicit publication.
// Status may be read by authenticated Super Admin; validation and publication
// each require their own explicit release flag and an explicit HTTP request.
const {assertReviewer} = require("./legal_admin_publication");
const pack = require("./legal_pack_publication");
const ORIGINS = ["https://sphot.app", "https://www.sphot.app",
  "http://127.0.0.1:5081", "http://localhost:5081",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com"];

function httpError(status, message) {
  const e = new Error(message);
  e.httpStatus = status;
  return e;
}
function register({admin, onRequest, reviewEnabled = false, publishEnabled = false}) {
  return onRequest({region: "us-central1", cors: ORIGINS,
    cpu: 1, memory: "512MiB", maxInstances: 2}, async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    if (req.method !== "POST") return res.status(405).json({success: false});
    try {
      const bearer = req.get("Authorization") || "";
      if (typeof bearer !== "string" || !bearer.startsWith("Bearer ")) {
        throw httpError(401, "SESSION_REQUISE");
      }
      const token = await admin.auth().verifyIdToken(bearer.slice(7), true);
      assertReviewer(token);
      const input = pack.validateInput(req.body);
      if (input.action === "validate" && !reviewEnabled) {
        throw httpError(403, "VALIDATION_INITIALE_NON_ACTIVEE");
      }
      if (input.action === "publish" && !publishEnabled) {
        throw httpError(403, "PUBLICATION_INITIALE_NON_ACTIVEE");
      }
      const result = await pack.action({admin, token, input});
      const response = {success: true, ...result};
      if (input.action === "status") {
        response.validationEnabled = reviewEnabled === true;
        response.publicationEnabled = publishEnabled === true;
      }
      return res.status(200).json(response);
    } catch (e) {
      const status = e.httpStatus || 403;
      if (!e.httpStatus) console.error("SPHOT initial legal pack refused", e);
      return res.status(status).json({success: false,
        error: e.httpStatus ? e.message : "OPERATION_REFUSEE"});
    }
  });
}
module.exports = {register};
