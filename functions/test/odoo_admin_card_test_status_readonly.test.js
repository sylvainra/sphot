"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {Readable} = require("node:stream");
const test = require("node:test");
const {TEST_PROJECT_ID} = require("../local/odoo_c4_test_firestore");
const {CHECKOUT_TEST_DATABASE} = require("../local/odoo_secure_checkout_client");
const {cardRecords, buildCardFixture, UID} =
  require("../local/odoo_admin_card_test_cycle");
const {readCardTestStatus} =
  require("../local/odoo_admin_card_test_status_readonly");
const {createServer} = require("../local/start_admin_odoo_readonly");

const prepared = buildCardFixture();

function harness({activated = false, paid = false} = {}) {
  const docs = new Map(cardRecords().entries.map(([collection, id, fields]) =>
    [collection + "/" + id, {...fields}]));
  const calls = [];
  if (activated) {
    docs.set("adminOdooCycles/" + prepared.reference, {
      testOnly: true, source: "odoo_admin_v1", adminUid: UID,
      orderReference: prepared.reference,
      orderFingerprint: prepared.fingerprint, paymentMethod: "card",
      paymentStatus: "paid", activationBasis: "stripe_verified",
      selectedRescueStationIds: [...prepared.locked.stationIds],
    });
    Object.assign(docs.get("subscriptions/" + UID), {
      status: "active", odooAdminManaged: true,
      odooAdminCycleRef: prepared.reference, odooPaymentStatus: "paid",
    });
    Object.assign(docs.get("admins/" + UID), {
      diffusionAccessGranted: true, odooAdminCycleRef: prepared.reference,
    });
    Object.assign(docs.get("adminRequests/" + UID), {
      accessPhase: "subscription_active",
      commercialTracking: {odooAdminCycleRef: prepared.reference},
    });
  }
  const db = {projectId: TEST_PROJECT_ID, collection(collection) {
    return {doc(id) {const key = collection + "/" + id;
      return {async get() {calls.push(["read", key]);
        return {exists: docs.has(key), data: () => docs.get(key)};}};}};
  }};
  const odooClient = {async call(model, method) {
    calls.push(["odoo", model, method]);
    if (model === "product.product" && method === "read") {
      return [2, 3, 4, 5].map((id, i) => ({id,
        default_code: "SPHOT-ADM-TEST-T" + (i + 1), type: "service",
        invoice_policy: "order", sale_ok: true, active: true, list_price: 0}));
    }
    if (model === "res.partner" && method === "read") {
      return [{id: 8, name: "SPHOT CLIENT API - TEST NEUTRALISE",
        is_company: true, active: true, country_id: [1, "France"],
        street: "rue fictive", zip: "75000", city: "TEST"}];
    }
    throw Error("UNEXPECTED_ODOO_RPC");
  }};
  const checkoutFactory = () => ({
    status: async () => ({order: {id: 10, name: "S00010", state: "sale"},
      invoice: {id: 16, name: "FAC/2026/00010", state: "posted",
        payment_state: paid ? "paid" : "not_paid"}}),
    verifiedStripePayment: async () => {
      calls.push(["verifiedStripePayment"]);
      return {verified: true};
    },
    stripeEvidence: async () => ({stripe_providers: [{code: "stripe",
      is_live: false, is_published: true}],
    demo_providers: [{is_published: false}], transactions: []}),
  });
  return {docs, calls, db, odooClient, checkoutFactory,
    read: () => readCardTestStatus({db, odooClient,
      database: CHECKOUT_TEST_DATABASE, checkoutFactory})};
}

test("CARTE UI : paiement et activation C4 TEST réellement concordants", async () => {
  const h = harness({activated: true, paid: true});
  const result = await h.read();
  assert.equal(result.testOnly, true);
  assert.equal(result.fixtureOnly, true);
  assert.equal(result.action, "none");
  assert.equal(result.reference, prepared.reference);
  assert.equal(result.activationVerified, true);
  assert.equal(result.stripeVerified, true);
  assert.equal(result.paymentStatus, "paid");
  assert.equal(result.nextGate, "TEST_CYCLE_COMPLETE");
  assert.equal(result.expectedHtCents, 89800);
  assert.equal(result.expectedTtcCents, 107760);
  assert.ok(h.calls.every(([name]) =>
    ["read", "odoo", "verifiedStripePayment"].includes(name)));
});

test("CARTE UI : état impayé visible sans aucun droit", async () => {
  const h = harness();
  const result = await h.read();
  assert.equal(result.activationVerified, false);
  assert.equal(result.stripeVerified, false);
  assert.equal(result.paymentStatus, "not_paid");
  assert.equal(result.nextGate, "STRIPE_TEST_PAYMENT_IN_ODOO_UI");
  assert.equal(h.calls.some(([name]) => name === "verifiedStripePayment"), false);
});

test("CARTE UI : ancien historique Firestore au format point accepté", async () => {
  const h = harness({activated: true, paid: true});
  const request = h.docs.get("adminRequests/" + UID);
  delete request.commercialTracking;
  request["commercialTracking.odooAdminCycleRef"] = prepared.reference;
  const result = await h.read();
  assert.equal(result.activationVerified, true);
  assert.equal(result.nextGate, "TEST_CYCLE_COMPLETE");
});

test("CARTE UI : historique absent ou références contradictoires refusés", async () => {
  const missing = harness({activated: true, paid: true});
  delete missing.docs.get("adminRequests/" + UID).commercialTracking;
  await assert.rejects(missing.read(), /ACTIVATION_EVIDENCE_INCONSISTENT/);

  const conflicting = harness({activated: true, paid: true});
  conflicting.docs.get("adminRequests/" + UID)
      ["commercialTracking.odooAdminCycleRef"] = "ANOTHER_CYCLE";
  await assert.rejects(conflicting.read(), /ACTIVATION_EVIDENCE_INCONSISTENT/);

  const wrongFlat = harness({activated: true, paid: true});
  const request = wrongFlat.docs.get("adminRequests/" + UID);
  delete request.commercialTracking;
  request["commercialTracking.odooAdminCycleRef"] = "ANOTHER_CYCLE";
  await assert.rejects(wrongFlat.read(), /ACTIVATION_EVIDENCE_INCONSISTENT/);
});

test("CARTE UI : activation artificielle, droits orphelins et PROD refusés", async () => {
  const unpaid = harness({activated: true, paid: false});
  await assert.rejects(unpaid.read(), /ACTIVATION_EVIDENCE_INCONSISTENT/);
  const mismatched = harness({activated: true, paid: true});
  mismatched.docs.get("adminOdooCycles/" + prepared.reference)
      .orderFingerprint = "faux";
  await assert.rejects(mismatched.read(), /ACTIVATION_EVIDENCE_INCONSISTENT/);
  const orphan = harness();
  orphan.docs.get("admins/" + UID).diffusionAccessGranted = true;
  await assert.rejects(orphan.read(), /RIGHTS_WITHOUT_CYCLE/);
  const prod = harness({activated: true, paid: true});
  prod.db.projectId = "sphot-ab80b";
  await assert.rejects(prod.read(), /DESTINATION_TEST_ONLY/);
  assert.equal(prod.calls.length, 0);
});

async function request(server, {url = "/admin/card-test-status",
  body = "{}", authorization = "Bearer valid"} = {}) {
  return new Promise((resolve, reject) => {
    const req = Readable.from([body]);
    req.method = "POST";
    req.url = url;
    req.headers = {host: "127.0.0.1:8768",
      origin: "http://localhost:51234", authorization};
    const res = {headers: {}, status: 0,
      setHeader(key, value) {this.headers[key] = value;},
      writeHead(status, headers) {this.status = status;
        Object.assign(this.headers, headers);},
      end(value) {resolve({status: this.status, body: JSON.parse(value || "{}")});}};
    try {server.emit("request", req, res);} catch (error) {reject(error);}
  });
}

test("CARTE UI : endpoint désactivé par défaut, bearer et corps vide obligatoires", async () => {
  let count = 0;
  const h = harness({activated: true, paid: true});
  const result = await h.read();
  const config = {verifyToken: async () => ({uid: "admin_connected"}),
    db: {projectId: "sphot-ab80b"},
    odooClient: {call: async () => null},
    cardTestStatus: async () => {count++; return result;}};
  assert.equal((await request(createServer({...config,
    cardTestStatus: undefined}))).status, 404);
  const server = createServer(config);
  assert.equal((await request(server,
      {authorization: ""})).status, 401);
  assert.equal((await request(server,
      {body: '{"stationIds":["real_admin_station"]}'})).status, 400);
  assert.equal(count, 0);
  const ok = await request(server);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.activationVerified, true);
  assert.equal(count, 1);
  const invalid = createServer({...config,
    cardTestStatus: async () => ({...result, action: "activate"})});
  assert.equal((await request(invalid)).status, 503);
});

test("CARTE UI : aucun identifiant réel et commande réelle toujours verrouillée", () => {
  const service = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/admin/services/admin_odoo_local_preflight_service.dart"),
  "utf8");
  const statusMethod = service.slice(service.indexOf(
      "Future<Map<String, dynamic>> verifyCardTestStatus()"));
  assert.match(statusMethod, /uri\.replace\(path: '\/admin\/card-test-status'\)/);
  assert.match(statusMethod, /body: '\{\}'/);
  assert.doesNotMatch(statusMethod, /stationIds|billingSiret|SIREN|SIRET|apiKey/);
  const panel = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/admin/pages/admin_subscription_panel.dart"), "utf8");
  assert.match(panel, /VÉRIFIER CARTE FICTIVE C4 TEST/);
  assert.match(panel, /Aucun droit sur ce compte ADMIN/);
  assert.match(panel, /CONFIRMER MA COMMANDE/);
  assert.match(panel, /onPressed: null,\s*icon: const Icon\(Icons\.lock_outline_rounded/);
  const bridge = fs.readFileSync(path.resolve(__dirname,
      "../local/start_admin_odoo_readonly.js"), "utf8");
  assert.doesNotMatch(bridge, /\.set\(|\.update\(|\.runTransaction\(|\.delete\(/);
});
