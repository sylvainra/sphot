/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {fixtureRecords} = require("../local/odoo_admin_test_fixture");
const {runFixtureActivation} =
  require("../local/odoo_admin_test_fixture_activate");

const PROJECT = "sphot-c4-test-20261029";
const DATABASE = "sphot_publicitaire_checkout_test";
const NOW = new Date("2026-10-31T12:00:00.000Z");

function fakeDb() {
  const entries = new Map(fixtureRecords(NOW).entries.map(([path, id, data]) =>
    [`${path}/${id}`, data]));
  const writes = [];
  const db = {
    projectId: PROJECT, entries, writes,
    collection(path) {
      return {doc(id) {
        const key = `${path}/${id}`;
        return {key, async get() {
          return {exists: entries.has(key), data: () => entries.get(key)};
        }};
      }};
    },
    async runTransaction(callback) {
      const ops = [];
      const tx = {
        async get(ref) {
          return {exists: entries.has(ref.key),
            data: () => entries.get(ref.key)};
        },
        create(ref, data) {
          ops.push({type: "create", key: ref.key, data});
        },
        set(ref, data, options) {
          ops.push({type: "set", key: ref.key, data, options});
        },
      };
      const result = await callback(tx);
      if (ops.some((op) => op.type === "create" && entries.has(op.key))) {
        throw new Error("duplicate-create");
      }
      for (const op of ops) {
        entries.set(op.key, {...(op.options?.merge ? entries.get(op.key) : {}),
          ...op.data});
        writes.push(op);
      }
      return result;
    },
  };
  return db;
}

function fakeClient({paid = false, otherInvoice = false} = {}) {
  const {prepared} = fixtureRecords(NOW);
  const status = {order: {id: 9, name: "S00009", state: "sale",
    client_order_ref: prepared.reference,
    x_sphot_reference: prepared.reference,
    x_sphot_fingerprint: prepared.fingerprint},
  invoice: {id: otherInvoice ? 88 : 15,
    name: otherInvoice ? "FAC/2026/00088" : "FAC/2026/00009",
    state: "posted", payment_state: paid ? "paid" : "not_paid",
    amount_total: 1556.4, amount_residual: paid ? 0 : 1556.4}};
  return {
    async status() {return status;},
    async verifiedStripePayment() {
      throw new Error("Aucune transaction CB pour engagement public");
    },
  };
}

async function withActivationEnv(callback) {
  const keys = ["SPHOT_ADMIN_TEST_FIRESTORE_WRITES",
    "SPHOT_ADMIN_TEST_PROJECT_ID", "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT",
    "SPHOT_ADMIN_TEST_ACTIVATE", "FIRESTORE_EMULATOR_HOST"];
  const prev = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  Object.assign(process.env, {
    SPHOT_ADMIN_TEST_FIRESTORE_WRITES: "true",
    SPHOT_ADMIN_TEST_PROJECT_ID: PROJECT,
    GCLOUD_PROJECT: PROJECT, GOOGLE_CLOUD_PROJECT: PROJECT,
    SPHOT_ADMIN_TEST_ACTIVATE: "true",
  });
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try {return await callback();} finally {
    for (const key of keys) {
      if (prev[key] === undefined) delete process.env[key];
      else process.env[key] = prev[key];
    }
  }
}

test("ADMIN activation TEST : prévol sans la moindre écriture", async () => {
  const db = fakeDb();
  const result = await runFixtureActivation({db, database: DATABASE,
    checkoutClient: fakeClient(), now: NOW});
  assert.equal(result.readyToActivate, true);
  assert.equal(result.invoiceId, 15);
  assert.equal(result.amountResidualCents, 155640);
  assert.equal(result.paymentStatus, "not_paid");
  assert.equal(db.writes.length, 0);
});

test("ADMIN activation TEST : production et autre DB refusées", async () => {
  const db = fakeDb();
  await assert.rejects(runFixtureActivation({db: {...db,
    projectId: "sphot-ab80b"}, database: DATABASE,
  checkoutClient: fakeClient()}), /DESTINATION_TEST_ONLY/);
  await assert.rejects(runFixtureActivation({db,
    database: "sphot_publicitaire_test", checkoutClient: fakeClient()}),
  /DESTINATION_TEST_ONLY/);
  assert.equal(db.writes.length, 0);
});

test("ADMIN activation TEST : opt-in absent refuse toute projection", async () => {
  const db = fakeDb();
  await assert.rejects(runFixtureActivation({db, database: DATABASE,
    checkoutClient: fakeClient(), mode: "activate", now: NOW}),
  /TEST_FIRESTORE_ONLY/);
  assert.equal(db.writes.length, 0);
});

test("ADMIN activation TEST : facture payée ou substituée refuse l'essai", async () => {
  const db = fakeDb();
  await assert.rejects(runFixtureActivation({db, database: DATABASE,
    checkoutClient: fakeClient({paid: true}), now: NOW}),
  /ODOO_TEST_POSTED_INVOICE_NOT_UNPAID_OR_UNLINKED/);
  await assert.rejects(runFixtureActivation({db, database: DATABASE,
    checkoutClient: fakeClient({otherInvoice: true}), now: NOW}),
  /ODOO_TEST_POSTED_INVOICE_NOT_UNPAID_OR_UNLINKED/);
  assert.equal(db.writes.length, 0);
});

test("ADMIN activation TEST : preuve fictive altérée bloque", async () => {
  await withActivationEnv(async () => {
    const db = fakeDb();
    db.entries.get("adminOdooEngagementEvidence/" +
        fixtureRecords(NOW).prepared.reference).buyerSiret = "12345678900012";
    await assert.rejects(runFixtureActivation({db, database: DATABASE,
      checkoutClient: fakeClient(), mode: "activate", now: NOW}),
    /ALTERED_FIXTURE/);
    assert.equal(db.writes.length, 0);
  });
});

test("ADMIN activation TEST : engagement simulé active sans paiement", async () => {
  await withActivationEnv(async () => {
    const db = fakeDb();
    const result = await runFixtureActivation({db, database: DATABASE,
      checkoutClient: fakeClient(), mode: "activate", now: NOW});
    assert.equal(result.action, "activate");
    assert.equal(result.rightsActive, true);
    assert.equal(result.paymentStatus, "not_paid");
    assert.equal(result.validUntilInclusiveParis, "31/12/2026");
    assert.equal(db.writes.length, 4);
    assert.equal(db.entries.get("subscriptions/" +
        fixtureRecords(NOW).prepared.locked.adminUid).status, "active");
    const second = await runFixtureActivation({db, database: DATABASE,
      checkoutClient: fakeClient(), mode: "activate", now: NOW});
    assert.equal(second.action, "none");
    assert.equal(db.writes.length, 4);
  });
});
