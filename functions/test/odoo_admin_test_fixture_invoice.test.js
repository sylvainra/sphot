/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {fixtureRecords} = require("../local/odoo_admin_test_fixture");
const {runFixtureInvoice} =
  require("../local/odoo_admin_test_fixture_invoice");

const PROJECT = "sphot-c4-test-20261029";
const DATABASE = "sphot_publicitaire_checkout_test";

function fakeDb() {
  const entries = new Map(fixtureRecords(new Date("2026-10-31T12:00:00Z"))
      .entries.map(([path, id, data]) => [`${path}/${id}`, data]));
  const reads = [];
  const db = {
    projectId: PROJECT,
    entries, reads,
    collection(path) {
      return {doc(id) {
        const key = `${path}/${id}`;
        return {async get() {
          reads.push(key);
          return {exists: entries.has(key), data: () => entries.get(key)};
        }};
      }};
    },
  };
  return db;
}

function fakeOdoo({productPrice = 0, partnerName =
  "SPHOT CLIENT API - TEST NEUTRALISE"} = {}) {
  const calls = [];
  const odooClient = {async call(model, method, args) {
    calls.push(`${model}/${method}`);
    assert.equal(method, "read");
    if (model === "product.product") {
      assert.deepEqual(args.ids, [2, 3, 4, 5]);
      return [1, 2, 3, 4].map((i) => ({id: i + 1,
        default_code: `SPHOT-ADM-TEST-T${i}`,
        name: `SPHOT ADMIN TEST - TRANCHE ${i}`,
        type: "service", invoice_policy: "order", active: true,
        sale_ok: true, list_price: productPrice}));
    }
    assert.equal(model, "res.partner");
    assert.deepEqual(args.ids, [8]);
    return [{id: 8, name: partnerName,
      is_company: true, active: true, country_id: [75, "France"],
      street: "TEST STREET", zip: "00000", city: "TEST"}];
  }};
  return {odooClient, calls};
}

function checkoutMock({existing = null, paid = false} = {}) {
  const calls = [];
  const order = {id: 99, name: "S00099", state: "sale"};
  const invoice = {id: 33, name: "FAC/2026/00033", state: "posted",
    payment_state: paid ? "paid" : "not_paid",
    amount_total: 1556.4, amount_residual: paid ? 0 : 1556.4};
  return {calls, create() {
    return {
      async status() {calls.push("status"); return existing;},
      async draft() {calls.push("draft"); return {order};},
      async invoice() {calls.push("invoice");
        return {outcome: "created", order, invoice};},
    };
  }};
}

async function optin(callback) {
  const keys = ["SPHOT_ADMIN_TEST_ODOO_WRITES",
    "SPHOT_ADMIN_TEST_ODOO_DATABASE"];
  const previous = Object.fromEntries(keys.map((key) => [key,
    process.env[key]]));
  process.env.SPHOT_ADMIN_TEST_ODOO_WRITES = "true";
  process.env.SPHOT_ADMIN_TEST_ODOO_DATABASE = DATABASE;
  try {return await callback();} finally {
    for (const key of keys) {
      if (previous[key] === undefined) delete process.env[key];
      else process.env[key] = previous[key];
    }
  }
}

test("ADMIN Odoo fictif : prévol lit les dix documents sans écriture", async () => {
  const db = fakeDb();
  const {odooClient, calls} = fakeOdoo();
  const checkout = checkoutMock();
  const result = await runFixtureInvoice({db, database: DATABASE, odooClient,
    checkoutFactory: checkout.create});
  assert.equal(result.action, "none");
  assert.equal(result.expectedHtCents, 129700);
  assert.equal(result.expectedTtcCents, 155640);
  assert.equal(result.firestoreVerified, true);
  assert.equal(db.reads.length, 11);
  assert.deepEqual(calls, ["product.product/read", "res.partner/read"]);
  assert.deepEqual(checkout.calls, ["status"]);
});

test("ADMIN Odoo fictif : PROD et autre base bloqués avant les RPC", async () => {
  const db = fakeDb();
  const {odooClient, calls} = fakeOdoo();
  await assert.rejects(runFixtureInvoice({db: {...db,
    projectId: "sphot-ab80b"}, database: DATABASE, odooClient}),
  /DESTINATION_TEST_ONLY/);
  await assert.rejects(runFixtureInvoice({db,
    database: "sphot_publicitaire_test", odooClient}),
  /DESTINATION_TEST_ONLY/);
  assert.equal(calls.length, 0);
});

test("ADMIN Odoo fictif : sans opt-in, aucune facture créée", async () => {
  const db = fakeDb();
  const {odooClient, calls} = fakeOdoo();
  await assert.rejects(runFixtureInvoice({db, database: DATABASE,
    odooClient, mode: "invoice"}), /ODOO_WRITE_EXPLICIT_OPT_IN_REQUIRED/);
  assert.equal(calls.length, 0);
});

test("ADMIN Odoo fictif : mutation du SIRET bloque avant l'ordre", async () => {
  await optin(async () => {
    const db = fakeDb();
    const {odooClient, calls} = fakeOdoo();
    db.entries.get("adminRequests/sphot_admin_collectivite_fictive_2026")
        .structure.siret = "12345678900012";
    await assert.rejects(runFixtureInvoice({db, database: DATABASE,
      odooClient, mode: "invoice"}), /FIXTURE_RECORD_MISSING_OR_ALTERED/);
    assert.equal(calls.length, 0);
  });
});

test("ADMIN Odoo fictif : produit ou payeur modifié refuse la facturation", async () => {
  await optin(async () => {
    const db = fakeDb();
    const changedProduct = fakeOdoo({productPrice: 50});
    const checkout = checkoutMock();
    await assert.rejects(runFixtureInvoice({db, database: DATABASE,
      odooClient: changedProduct.odooClient,
      checkoutFactory: checkout.create, mode: "invoice"}),
    /TEST_TIER_PRODUCTS_DIFFERENT_FROM_APPROVED_SETUP/);
    assert.deepEqual(checkout.calls, []);
    const changedPartner = fakeOdoo({partnerName: "INCONNU"});
    await assert.rejects(runFixtureInvoice({db, database: DATABASE,
      odooClient: changedPartner.odooClient,
      checkoutFactory: checkout.create, mode: "invoice"}),
    /ODOO_TEST_PARTNER_INCOMPLETE_OR_CHANGED/);
  });
});

test("ADMIN Odoo fictif : facture unique POSTED/NOT_PAID après opt-in", async () => {
  await optin(async () => {
    const db = fakeDb();
    const {odooClient} = fakeOdoo();
    const checkout = checkoutMock();
    const result = await runFixtureInvoice({db, database: DATABASE,
      odooClient, checkoutFactory: checkout.create, mode: "invoice"});
    assert.equal(result.invoiceStatus, "posted");
    assert.equal(result.paymentStatus, "not_paid");
    assert.equal(result.residual, 1556.4);
    assert.equal(result.firestoreActivationAttempted, false);
    assert.deepEqual(checkout.calls, ["status", "draft", "invoice"]);
  });
});

test("ADMIN Odoo fictif : facture payée avant reprise bloquée", async () => {
  await optin(async () => {
    const db = fakeDb();
    const {odooClient} = fakeOdoo();
    const checkout = checkoutMock({existing: {order: {id: 99},
      invoice: {payment_state: "paid"}}});
    await assert.rejects(runFixtureInvoice({db, database: DATABASE,
      odooClient, checkoutFactory: checkout.create, mode: "invoice"}),
    /TEST_INVOICE_IS_NOT_UNPAID/);
    assert.deepEqual(checkout.calls, ["status"]);
  });
});
