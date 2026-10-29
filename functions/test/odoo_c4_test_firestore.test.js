"use strict";
/* eslint-disable require-jsdoc */

const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {secureReferenceFor} = require("../local/odoo_secure_checkout_client");
const {TEST_PROJECT_ID, createC4TestCloudSync} =
  require("../local/odoo_c4_test_firestore");

// Base intégralement fictive : ces tests n'utilisent aucune connexion réseau.
process.env.SPHOT_C4_TEST_CLOUD_WRITES = "true";
process.env.SPHOT_C4_PROJECT_ID = TEST_PROJECT_ID;
process.env.GCLOUD_PROJECT = TEST_PROJECT_ID;
process.env.GOOGLE_CLOUD_PROJECT = TEST_PROJECT_ID;
delete process.env.FIRESTORE_EMULATOR_HOST;

function mockDatabase() {
  const store = new Map();
  let queue = Promise.resolve();
  function doc(path) {
    const id = path.split("/").at(-1);
    return {id, path,
      get: async () => ({id, ref: doc(path), exists: store.has(path),
        data: () => structuredClone(store.get(path))}),
      collection: (name) => collection(`${path}/${name}`)};
  }
  function collection(path) {
    return {doc: (id) => doc(`${path}/${id}`),
      where: (field, op, value) => ({get: async () => {
        assert.equal(op, "==");
        const matches = [...store.entries()].filter(([key, data]) =>
          key.startsWith(`${path}/`) &&
          key.slice(path.length + 1).indexOf("/") === -1 &&
          data[field] === value);
        return {docs: await Promise.all(matches.map(([key]) =>
          doc(key).get()))};
      }})};
  }
  async function runTransaction(callback) {
    const previous = queue;
    let release;
    queue = new Promise((resolve) => {
      release = resolve;
    });
    await previous;
    const writes = [];
    let hasWritten = false;
    const tx = {get: async (ref) => {
      if (hasWritten) throw new Error("Lecture après écriture.");
      return ref.get();
    }, create: (ref, value) => {
      hasWritten = true;
      writes.push({path: ref.path, value, kind: "create"});
    }, update: (ref, value) => {
      hasWritten = true;
      writes.push({path: ref.path, value, kind: "update"});
    }};
    try {
      const result = await callback(tx);
      const staged = new Map(store);
      for (const write of writes) {
        if (write.kind === "create" && staged.has(write.path)) {
          throw new Error("Doublon.");
        }
        staged.set(write.path, write.kind === "update" ?
          {...staged.get(write.path), ...structuredClone(write.value)} :
          structuredClone(write.value));
      }
      store.clear();
      for (const [key, value] of staged) store.set(key, value);
      return result;
    } finally {
      release();
    }
  }
  return {projectId: TEST_PROJECT_ID,
    collection, runTransaction,
    get: (path) => store.get(path),
    count: (prefix) => [...store.keys()]
        .filter((key) => key.startsWith(prefix)).length};
}

function fixture() {
  const requestId = "c4_trial_20261029";
  return {requestId, source: {
    status: "approved", advertisingSpotCompleted: true,
    diffusionCompleted: true, planningCompleted: true,
    advertisingTerritory: {level: "radius_5km", radiusKm: 5},
    advertisingSpot: {latitude: 46.4, longitude: -1.5,
      bannerUrl: "https://example.test/approved.webp"},
    approvedApplication: {visual: {
      url: "https://example.test/first-visual.webp"}},
    diffusion: {visibilityType: "pack"},
    establishment: {businessName: "C4 annonceur"},
    application: {destinationUrl: "https://example.test/"},
    planning: {campaignStartDate: "2026-10-28T00:00:00Z",
      campaignEndDate: "2026-11-01T00:00:00Z"},
  }, order: {testOnly: true, odooState: "sale", odooOrderId: 7,
    reference: secureReferenceFor(requestId), odooTotalCents: 15480},
  invoice: {testOnly: true, odooInvoiceId: 12,
    odooInvoiceName: "FAC/2026/00007", state: "posted",
    paymentState: "paid", amountTotalCents: 15480,
    amountResidualCents: 0, odooPaymentRecorded: true},
  payment: {paymentConfirmed: true, transactions: [{
    id: 51, reference: "FAC/2026/00007", state: "done",
    provider: "stripe", currency: "EUR", amountCents: 15480,
    testOnly: true,
  }]}, nowMs: Date.parse("2026-10-29T09:00:00Z")};
}

test("C4 : seul le projet Firebase TEST autorisé", async () => {
  const db = mockDatabase();
  const previous = db.projectId;
  db.projectId = "sphot-ab80b";
  assert.throws(() => createC4TestCloudSync(db), /refusé/);
  db.projectId = previous;
  const service = createC4TestCloudSync(db);
  process.env.GCLOUD_PROJECT = "sphot-ab80b";
  await assert.rejects(service.sync(fixture()), /refusé/);
  process.env.GCLOUD_PROJECT = TEST_PROJECT_ID;
  assert.equal(db.count("adRequests/"), 0);
});

test("C4 : reconnaît l'objet Firestore réel du SDK Firebase Admin", () => {
  const app = admin.initializeApp({projectId: TEST_PROJECT_ID},
      "c4-real-sdk-guard-test");
  const firestore = admin.firestore(app);
  assert.equal(firestore.projectId, TEST_PROJECT_ID);
  assert.doesNotThrow(() => createC4TestCloudSync(firestore));
});

test("C4 : Odoo payé, campagne visible et activation unique", async () => {
  const db = mockDatabase();
  const service = createC4TestCloudSync(db);
  const input = fixture();
  assert.equal((await service.sync(input)).action, "activate");
  assert.equal((await service.sync(input)).action, "none");
  assert.equal(db.count("c4TestPaymentClaims/"), 1);
  assert.equal(db.count(`adRequests/${input.requestId}/c4TestHistory/`), 1);
  const ads = await service.publicAdvertisements(input.nowMs);
  assert.equal(ads.length, 1);
  assert.equal(ads[0].advertiserName, "C4 annonceur");
  assert.equal(Object.hasOwn(ads[0], "firebaseUid"), false);
  await service.reconcile(Date.parse("2026-11-02T00:00:00Z"));
  assert.equal((await service.publicAdvertisements(
      Date.parse("2026-11-02T00:00:00Z"))).length, 0);
});

test("C4 : programmation, retrait d'approbation et facture", async () => {
  const db = mockDatabase();
  const service = createC4TestCloudSync(db);
  const input = fixture();
  input.nowMs = Date.parse("2026-10-27T00:00:00Z");
  assert.equal((await service.sync(input)).phase, "scheduled");
  assert.deepEqual(await service.publicAdvertisements(input.nowMs), []);
  await service.reconcile(Date.parse("2026-10-29T00:00:00Z"));
  assert.equal((await service.publicAdvertisements(
      Date.parse("2026-10-29T00:00:00Z"))).length, 1);
  db.get(`advertiserRequests/${input.requestId}`).status = "rejected";
  assert.deepEqual(await service.publicAdvertisements(
      Date.parse("2026-10-29T00:00:00Z")), []);
  const second = fixture();
  second.requestId = "another_c4_20261029";
  second.order.reference = secureReferenceFor(second.requestId);
  assert.equal((await service.sync(second)).reason, "invoice_already_claimed");
  assert.equal(db.count("c4TestPaymentClaims/"), 1);
});

test("C4 : aucun paiement = aucune écriture", async () => {
  const db = mockDatabase();
  const service = createC4TestCloudSync(db);
  const input = fixture();
  input.payment.paymentConfirmed = false;
  assert.equal((await service.sync(input)).phase, "blocked");
  assert.equal(db.count("adRequests/"), 0);
});
