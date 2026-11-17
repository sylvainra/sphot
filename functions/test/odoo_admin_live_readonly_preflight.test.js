"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {Readable} = require("node:stream");
const test = require("node:test");
const {preflightAdminOffer, safeStations} =
  require("../local/odoo_admin_live_readonly_preflight");
const {createServer} = require("../local/start_admin_odoo_readonly");

const UID = "admin_valid_request_001";
const TERRITORY = "territoire_fr_test_001";
const SIRET = "21630123400012";
const IDS = ["station_alpha_001", "station_beta_002", "station_gamma_003"];
const locality = {pays: "France", region: "Auvergne-Rhône-Alpes",
  departement: "Puy-de-Dôme", ville: "VILLE FICTIVE"};

function records() {
  const request = {uid: UID, status: "approved",
    structure: {siren: SIRET.slice(0, 9), siret: SIRET},
    territoire: {territoireId: TERRITORY, ...locality}};
  const fingerprint = crypto.createHash("sha256").update(JSON.stringify({
    requestId: UID, territoryId: TERRITORY, siren: SIRET.slice(0, 9),
    siret: SIRET, locality,
  })).digest("hex");
  const docs = new Map([
    ["adminRequests/" + UID, request],
    ["admins/" + UID, {uid: UID, role: "admin",
      accessStatus: "approved", territoireId: TERRITORY}],
    ["subscriptions/" + UID, {adminUid: UID,
      status: "awaiting_subscription", billingOrganisation: "Commune Test",
      billingSiret: SIRET, billingAddress: "1 rue de Test",
      billingPostalCode: "63000", billingCity: "TEST",
      billingContactEmail: "finance@example.invalid"}],
    ["adminOdooReviewEvidence/" + UID, {
      source: "server_review_archive", status: "approved",
      verifiedSuperAdminReview: true, adminUid: UID,
      territoireId: TERRITORY, siren: SIRET.slice(0, 9), siret: SIRET,
      requestFingerprint: fingerprint,
      reviewedByUid: "sphot-super-admin-" + "a".repeat(32),
      reviewedAt: new Date("2026-10-31T12:00:00Z"),
      superAdminChecks: {locality: true, siren: true, siret: true},
    }],
    ["commercialPricingMarkets/FR_ADMIN", {type: "ADMIN", country: "FR",
      currency: "EUR", publishedVersion: 3,
      publishedPrices: [499, 399, 299, 199]}],
    ["commercialCustomerDiscounts/ADMIN__" + UID, {percent: 10}],
    ...IDS.map((id) => ["territoires/" + TERRITORY + "/spots/" + id,
      {isPosteSecours: true, territoireId: TERRITORY}]),
  ]);
  return docs;
}

function harness() {
  const docs = records();
  const calls = [];
  const db = {projectId: "sphot-ab80b", collection(collection) {
    return {doc(id) {return {async get() {
      const key = collection + "/" + id;
      calls.push(["firestore_get", key]);
      return {exists: docs.has(key), data: () => docs.get(key)};
    }};}};
  }};
  const odooClient = {async call(model, method, body) {
    calls.push(["odoo", model, method]);
    assert.equal(model, "product.product");
    assert.equal(method, "read");
    assert.deepEqual(body.ids, [2, 3, 4, 5]);
    return body.ids.map((id, index) => ({id,
      default_code: "SPHOT-ADM-TEST-T" + (index + 1),
      type: "service", invoice_policy: "order",
      sale_ok: true, active: true, list_price: 0}));
  }};
  return {docs, db, calls, odooClient,
    run: (stationIds = IDS) => preflightAdminOffer({db, uid: UID,
      stationIds, odooClient})};
}

test("ADMIN local : lecture vérifiée du dossier et du tarif, zéro écriture", async () => {
  const h = harness();
  const result = await h.run();
  assert.equal(result.testOnly, true);
  assert.equal(result.action, "read_only_preflight");
  assert.equal(result.numberOfRescueStations, 3);
  assert.equal(result.pricingReference, "FR_ADMIN-V3");
  assert.equal(result.baseExclTaxCents, 129700);
  assert.equal(result.payableExclTaxCents, 116730);
  assert.equal(result.discountPercent, 10);
  assert.equal(result.billingFieldsPresent, true);
  assert.equal(result.odooOrderCreated, false);
  assert.equal(result.odooInvoiceCreated, false);
  assert.equal(result.firestoreWriteAttempted, false);
  assert.equal(result.activationAllowed, false);
  assert.deepEqual(h.calls.filter((row) => row[0] === "odoo"),
      [["odoo", "product.product", "read"]]);
});

test("ADMIN local : filtre initial Super Admin obligatoire", async () => {
  for (const mutate of [
    (h) => h.docs.delete("adminOdooReviewEvidence/" + UID),
    (h) => h.docs.get("adminOdooReviewEvidence/" + UID).source = "fake",
    (h) => h.docs.get("adminOdooReviewEvidence/" + UID)
        .superAdminChecks.siret = false,
    (h) => h.docs.get("adminRequests/" + UID)
        .territoire.ville = "AUTRE VILLE",
    (h) => h.docs.get("adminRequests/" + UID)
        .structure.siret = "99999999900000",
  ]) {
    const h = harness();
    mutate(h);
    await assert.rejects(h.run(), /ADMIN_REQUIRED_SERVER_RECORD_MISSING|ADMIN_SUPERADMIN_REVIEW_UNVERIFIED/);
    assert.equal(h.calls.some((c) => c[0] === "odoo"), false);
  }
});

test("ADMIN local : poste hors territoire, faux ou doublonné bloqué", async () => {
  assert.throws(() => safeStations([IDS[0], IDS[0]]), /SELECTION_INVALID/);
  assert.throws(() => safeStations(["../other"]), /SELECTION_INVALID/);
  for (const mutation of [
    (h) => h.docs.get("territoires/" + TERRITORY + "/spots/" + IDS[0])
        .isPosteSecours = false,
    (h) => h.docs.get("territoires/" + TERRITORY + "/spots/" + IDS[0])
        .territoireId = "another_territory",
  ]) {
    const h = harness();
    mutation(h);
    await assert.rejects(h.run(), /OUTSIDE_APPROVED_TERRITORY/);
    assert.equal(h.calls.some((c) => c[0] === "odoo"), false);
  }
});

test("ADMIN local : facture/activation existante interdit le nouveau cycle", async () => {
  const h = harness();
  h.docs.get("subscriptions/" + UID).odooAdminManaged = true;
  await assert.rejects(h.run(), /ADMIN_EXISTING_COMMERCIAL_CYCLE/);
  assert.equal(h.calls.some((c) => c[0] === "odoo"), false);
});

test("ADMIN local : grille publiée et remise non vérifiées refusées", async () => {
  const h = harness();
  h.docs.get("commercialPricingMarkets/FR_ADMIN").type = "ADVERTISER_RADIUS";
  await assert.rejects(h.run(), /ADMIN_PUBLISHED_PRICING_MARKET_INVALID/);
  assert.equal(h.calls.some((c) => c[0] === "odoo"), false);
  const badDiscount = harness();
  badDiscount.docs.get("commercialCustomerDiscounts/ADMIN__" + UID)
      .percent = 150;
  await assert.rejects(badDiscount.run(), /Remise invalide/);
  assert.equal(badDiscount.calls.some((c) => c[0] === "odoo"), false);
});

test("ADMIN local : Firestore non autorisé et Odoo non TEST refusés", async () => {
  const h = harness();
  h.db.projectId = "sphot-c4-test-20261029";
  await assert.rejects(h.run(), /ADMIN_TEST_BRIDGE_DESTINATION_INVALID/);
  h.db.projectId = "sphot-ab80b";
  await assert.rejects(preflightAdminOffer({db: h.db, uid: UID,
    stationIds: IDS, odooClient: h.odooClient,
    database: "some_other_database"}), /ADMIN_TEST_BRIDGE_DESTINATION_INVALID/);
});

test("ADMIN Flutter : aucun tarif, SIRET ou identifiant ADMIN envoyé depuis UI", () => {
  const service = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/admin/services/admin_odoo_local_preflight_service.dart"),
  "utf8");
  assert.match(service, /jsonEncode\(\{'stationIds': stationIds\}\)/);
  assert.doesNotMatch(service, /jsonEncode\(\{[^}]*prix|apiKey|SPHOT_ODOO_LOCAL_API_KEY/);
  const panel = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/admin/pages/admin_subscription_panel.dart"), "utf8");
  assert.match(panel, /AdminOdooLocalPreflightService\.configured/);
  assert.match(panel, /verifySelection\(stationIds: ids\)/);
  const bridge = fs.readFileSync(path.resolve(__dirname,
      "../local/start_admin_odoo_readonly.js"), "utf8");
  assert.match(bridge, /FIREBASE_TOKEN_REQUIRED/);
  assert.match(bridge, /verifyToken\(header\.slice\(7\)\)/);
  assert.match(bridge, /"\/admin\/fixture-preflight"/);
  assert.match(bridge, /SPHOT_ADMIN_ODOO_TEST_FIXTURE_READONLY/);
  assert.doesNotMatch(bridge, /\.set\(|\.update\(|\.runTransaction\(|\.delete\(/);
});

test("ADMIN Flutter : résultat du précontrôle affiché dans le panneau sans Scaffold", () => {
  const panel = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/admin/pages/admin_subscription_panel.dart"), "utf8");
  const offerHandler = panel.slice(panel.indexOf("if (section == 'offer')"),
      panel.indexOf("setState(() {\n      _savingSection = section;", panel.indexOf("if (section == 'offer')")));
  assert.match(offerHandler, /_offerPreflightNotice =/);
  assert.match(panel, /if \(_offerPreflightNotice != null\)/);
  assert.match(panel, /_offerPreflightNotice = null;\s*_offerPreflightOk = false;\s*if \(value == true\)/);
  assert.doesNotMatch(offerHandler, /ScaffoldMessenger\.[\s\S]*?showSnackBar/);
  assert.match(panel, /child: Material\(\s*color: Colors\.transparent,\s*child: CheckboxListTile/);
});

async function simulatedRequest(server, {url = "/admin/fixture-preflight",
  body = "{}", token = "Bearer valid"} = {}) {
  return new Promise((resolve, reject) => {
    const req = Readable.from([body]);
    req.method = "POST";
    req.url = url;
    req.headers = {host: "127.0.0.1:8768",
      origin: "http://127.0.0.1:52118", authorization: token};
    const res = {headers: {}, status: null,
      setHeader(key, value) {this.headers[key] = value;},
      writeHead(code, headers) {this.status = code;
        Object.assign(this.headers, headers);},
      end(data) {resolve({status: this.status, data: JSON.parse(data || "{}")});}};
    try {server.emit("request", req, res);} catch (error) {reject(error);}
  });
}

test("ADMIN fixture : route exclusivement TEST, lecture seule et authentifiée", async () => {
  let calls = 0;
  const fixturePreflight = async () => {
    calls++;
    return {testOnly: true, action: "none",
      reference: "SPHOT-ADM-TEST-AE2CF757C9C18535",
      rightsActive: true, paymentStatus: "not_paid"};
  };
  const options = {verifyToken: async () => ({uid: UID}),
    db: {projectId: "sphot-ab80b",
      collection() {throw Error("PROD_FIRESTORE_ACCESS_FORBIDDEN");}},
    odooClient: {async call() {throw Error("ODOO_RPC_NOT_EXPECTED");}},
    fixturePreflight};
  const server = createServer(options);
  const success = await simulatedRequest(server);
  assert.equal(success.status, 200);
  assert.equal(success.data.testOnly, true);
  assert.equal(success.data.fixtureOnly, true);
  assert.equal(success.data.fixtureStationCount, 3);
  assert.equal(success.data.paymentStatus, "not_paid");
  assert.equal(success.data.prodFirestoreWritten, false);
  assert.equal(success.data.odooWritten, false);
  assert.equal(success.data.activationAttempted, false);
  assert.equal(calls, 1);

  const wrongPayload = await simulatedRequest(server, {body: JSON.stringify({
    stationIds: ["real_station"], adminUid: UID})});
  assert.equal(wrongPayload.status, 400);
  assert.equal(calls, 1);
  const noSession = await simulatedRequest(server, {token: ""});
  assert.equal(noSession.status, 401);
  assert.equal(calls, 1);
  const disabled = await simulatedRequest(createServer({...options,
    fixturePreflight: undefined}));
  assert.equal(disabled.status, 404);
  const invalid = await simulatedRequest(createServer({...options,
    fixturePreflight: async () => ({testOnly: true, action: "activate",
      reference: "SPHOT-ADM-TEST-AE2CF757C9C18535"})}));
  assert.equal(invalid.status, 503);
});

test("ADMIN fixture Flutter : aucune donnée réelle envoyée, bouton TEST isolé", () => {
  const service = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/admin/services/admin_odoo_local_preflight_service.dart"),
  "utf8");
  const fixtureMethod = service.slice(service.indexOf("Future<Map<String, dynamic>> verifyFixture()"));
  assert.match(fixtureMethod, /uri\.replace\(path: '\/admin\/fixture-preflight'\)/);
  assert.match(fixtureMethod, /body: '\{\}'/);
  assert.doesNotMatch(fixtureMethod, /stationIds|billingSiret|SIREN|SIRET/);
  const panel = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/admin/pages/admin_subscription_panel.dart"), "utf8");
  assert.match(panel, /AdminOdooLocalPreflightService\.fixtureConfigured/);
  assert.match(panel, /3 postes fictifs, sans lien avec/);
  assert.match(panel, /TEST ODOO — DOSSIER FICTIF \(3 POSTES\)/);
});
