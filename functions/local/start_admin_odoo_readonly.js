/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Serveur LOCAL 127.0.0.1:8768 exclusivement en lecture.
// Auth Firebase SPHOT -> preuves Firestore SPHOT -> tarifs -> Odoo TEST.
// Aucun endpoint draft/invoice/activate, aucune écriture Firebase.
const http = require("node:http");
const {FIREBASE_PROJECT_ID, TEST_DATABASE, preflightAdminOffer} =
  require("./odoo_admin_live_readonly_preflight");
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");

const HOST = "127.0.0.1";
const PORT = 8768;
const MAX_BYTES = 16384;
const LOCAL_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1):[0-9]{2,5}$/;

function send(res, status, body) {
  res.writeHead(status, {"Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"});
  res.end(JSON.stringify(body));
}

function createServer({verifyToken, db, odooClient,
  fixturePreflight, cardTestStatus} = {}) {
  if (typeof verifyToken !== "function" ||
      !db || db.projectId !== FIREBASE_PROJECT_ID ||
      !odooClient || typeof odooClient.call !== "function") {
    throw new Error("PREFLIGHT_ADMIN_CONFIG_INCOMPLETE");
  }
  return http.createServer(async (req, res) => {
    const origin = req.headers.origin || "";
    const host = req.headers.host || "";
    if (origin && !LOCAL_ORIGIN.test(origin)) {
      return send(res, 403, {ok: false, error: "ORIGIN_LOCAL_REQUIRED"});
    }
    if (![HOST + ":" + PORT, "localhost:" + PORT].includes(host)) {
      return send(res, 403, {ok: false, error: "HOST_LOCAL_REQUIRED"});
    }
    if (origin) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
    }
    if (req.method === "OPTIONS") {
      res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers",
          "Authorization, Content-Type");
      return send(res, 204, {});
    }
    if (req.method !== "POST" || ![
      "/admin/preflight", "/admin/fixture-preflight",
      "/admin/card-test-status",
    ].includes(req.url)) {
      return send(res, 404, {ok: false, error: "ADMIN_PREFLIGHT_ONLY"});
    }
    const isFixture = req.url === "/admin/fixture-preflight";
    const isCardStatus = req.url === "/admin/card-test-status";
    if (isFixture && typeof fixturePreflight !== "function") {
      return send(res, 404, {ok: false, error: "TEST_FIXTURE_MODE_DISABLED"});
    }
    if (isCardStatus && typeof cardTestStatus !== "function") {
      return send(res, 404, {ok: false, error: "TEST_CARD_STATUS_DISABLED"});
    }
    const header = req.headers.authorization || "";
    if (!header.startsWith("Bearer ") || header.length > 10000) {
      return send(res, 401, {ok: false, error: "FIREBASE_TOKEN_REQUIRED"});
    }
    try {
      let raw = "";
      for await (const chunk of req) {
        raw += chunk;
        if (Buffer.byteLength(raw, "utf8") > MAX_BYTES) {
          return send(res, 413, {ok: false, error: "REQUEST_TOO_LARGE"});
        }
      }
      let body;
      try {
        body = JSON.parse(raw);
      } catch (_) {
        return send(res, 400, {ok: false, error: "INVALID_JSON"});
      }
      // Le mode fictif n'accepte AUCUNE donnée réelle depuis le navigateur.
      // Le parcours réel conserve ses vérifications et son endpoint séparé.
      if (!body || Array.isArray(body) || typeof body !== "object" ||
          (isFixture || isCardStatus ? Object.keys(body).length !== 0 :
            Object.keys(body).sort().join("|") !== "stationIds")) {
        return send(res, 400, {ok: false,
          error: isFixture || isCardStatus ?
            "FIXTURE_EMPTY_BODY_ONLY" : "STATION_SELECTION_ONLY"});
      }
      let user;
      try {
        user = await verifyToken(header.slice(7));
      } catch (_) {
        return send(res, 401, {ok: false, error: "FIREBASE_TOKEN_INVALID"});
      }
      if (!user || typeof user.uid !== "string" || !user.uid.trim()) {
        return send(res, 401, {ok: false, error: "FIREBASE_TOKEN_INVALID"});
      }
      if (isFixture) {
        const result = await fixturePreflight();
        if (!result || result.testOnly !== true || result.action !== "none" ||
            typeof result.reference !== "string" ||
            !/^SPHOT-ADM-TEST-[A-F0-9]{16}$/.test(result.reference)) {
          return send(res, 503, {ok: false,
            error: "ADMIN_TEST_FIXTURE_CONTRACT_INVALID"});
        }
        return send(res, 200, {ok: true, ...result,
          fixtureOnly: true, fixtureStationCount: 3,
          odooDatabase: TEST_DATABASE, firestoreProject: TEST_PROJECT_ID,
          prodFirestoreWritten: false, odooWritten: false,
          activationAttempted: false});
      }
      if (isCardStatus) {
        const result = await cardTestStatus();
        if (!result || result.testOnly !== true ||
            result.fixtureOnly !== true || result.action !== "none" ||
            !/^SPHOT-ADM-TEST-[A-F0-9]{16}$/.test(result.reference) ||
            result.firestoreProject !== TEST_PROJECT_ID ||
            result.odooDatabase !== TEST_DATABASE ||
            result.prodFirestoreWritten !== false ||
            result.odooWritten !== false ||
            result.activationAttempted !== false) {
          return send(res, 503, {ok: false,
            error: "ADMIN_CARD_STATUS_CONTRACT_INVALID"});
        }
        return send(res, 200, {ok: true, ...result});
      }
      const result = await preflightAdminOffer({db,
        uid: user.uid, stationIds: body.stationIds,
        odooClient, database: TEST_DATABASE});
      return send(res, 200, {ok: true, ...result});
    } catch (error) {
      if (!error.httpStatus) {
        // Ne jamais imprimer l'identité, l'API key ou le bearer.
        console.error("SPHOT ADMIN : lecture locale indisponible",
            error.code || error.name);
      }
      return send(res, error.httpStatus || 503, {ok: false,
        error: error.httpStatus ? error.message :
          "ADMIN_READ_ONLY_BRIDGE_UNAVAILABLE"});
    }
  });
}

function main() {
  if (process.env.SPHOT_ADMIN_ODOO_READONLY_PREFLIGHT !== "true" ||
      !process.env.SPHOT_ODOO_LOCAL_API_KEY ||
      process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.SPHOT_ADMIN_TEST_FIRESTORE_WRITES === "true") {
    throw new Error("PREFLIGHT_ADMIN_LOCAL_OPT_IN_REQUIRED");
  }
  const admin = require("firebase-admin");
  const {createOdooClient} = require("./odoo_community_bridge_server");
  const app = admin.initializeApp({projectId: FIREBASE_PROJECT_ID},
      "sphot-admin-odoo-local-readonly");
  const odoo = createOdooClient({
    apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
    database: TEST_DATABASE,
  });
  let fixturePreflight;
  let cardTestStatus;
  const fixtureEnabled =
    process.env.SPHOT_ADMIN_ODOO_TEST_FIXTURE_READONLY === "true";
  const cardEnabled =
    process.env.SPHOT_ADMIN_ODOO_TEST_CARD_STATUS_READONLY === "true";
  if (fixtureEnabled || cardEnabled) {
    // Identifiants ADC explicitement liés au projet C4 TEST.
    const {readC4Credentials} = require("./start_c4_bridge");
    readC4Credentials();
    const fixtureApp = admin.initializeApp({projectId: TEST_PROJECT_ID,
      credential: admin.credential.applicationDefault()},
    "sphot-admin-fixture-local-readonly");
    const fixtureDb = admin.firestore(fixtureApp);
    if (fixtureEnabled) {
      const {runFixtureActivation} = require("./odoo_admin_test_fixture_activate");
      const {createAdminCheckoutClient} = require("./odoo_admin_checkout_client");
      const checkout = createAdminCheckoutClient({
        database: TEST_DATABASE, odooClient: odoo,
      });
      fixturePreflight = () => runFixtureActivation({
        db: fixtureDb, database: TEST_DATABASE, checkoutClient: checkout,
        mode: "preflight",
      });
    }
    if (cardEnabled) {
      const {readCardTestStatus} =
        require("./odoo_admin_card_test_status_readonly");
      cardTestStatus = () => readCardTestStatus({
        db: fixtureDb, odooClient: odoo, database: TEST_DATABASE,
      });
    }
  }
  const server = createServer({
    verifyToken: (token) => admin.auth(app).verifyIdToken(token, true),
    db: admin.firestore(app),
    odooClient: odoo,
    fixturePreflight,
    cardTestStatus,
  });
  server.listen(PORT, HOST, () => {
    console.log("SPHOT ADMIN : lecture seule sur http://" + HOST +
        ":" + PORT + "/admin/preflight");
    console.log("Firebase SPHOT en lecture seule ; Odoo TEST en lecture seule.");
    console.log("AUCUNE COMMANDE, FACTURE OU ACTIVATION POSSIBLE.");
    if (fixturePreflight) {
      console.log("Dossier ADMIN FICTIF C4 TEST : lecture seule activée, " +
          "sans lien avec les postes du compte réel.");
    }
    if (cardTestStatus) {
      console.log("Cycle ADMIN CARTE FICTIF C4 TEST : statut Odoo/Stripe/" +
          "Firestore en lecture seule disponible.");
    }
  });
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error("SPHOT ADMIN PREFLIGHT REFUSE :", error.message);
    process.exitCode = 1;
  }
}

module.exports = {HOST, PORT, createServer};
