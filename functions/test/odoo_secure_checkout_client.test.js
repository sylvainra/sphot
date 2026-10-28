/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {CHECKOUT_TEST_DATABASE, CHECKOUT_MODEL, DRAFT_METHOD,
  INVOICE_METHOD, ORDER_CONTRACT, INVOICE_CONTRACT,
  trustedFingerprint, secureReferenceFor, prepareTrustedOrder,
  createSecureCheckoutClient} = require("../local/odoo_secure_checkout_client");

const quote = {market: "ADVERTISER_RADIUS", version: 1,
  pricingReference: "FR_ADVERTISER_RADIUS-V1", currency: "EUR",
  amountExclTax: 99, discountPercent: 0, payableExclTaxCents: 9900,
  territory: "radius_5km", offer: "map", duration: "15 jours"};

function fixture() {
  const prepared = prepareTrustedOrder({requestId: "TESTDOSSIER20261028",
    quote, partnerId: 8, productId: 1});
  const calls = [];
  const order = {id: 6, name: "S00006", state: "draft",
    client_order_ref: prepared.reference, partner_id: [8, "Client test"],
    currency_id: [1, "EUR"], amount_untaxed: 99,
    amount_tax: 19.8, amount_total: 118.8, order_line: [17], invoice_ids: [],
    x_sphot_reference: prepared.reference,
    x_sphot_fingerprint: prepared.fingerprint};
  const line = {id: 17, product_id: [1, "Service publicitaire"],
    product_uom_qty: 1, price_unit: 99, discount: 0};
  const invoice = {id: 11, name: "FAC/2026/00006",
    invoice_origin: "S00006", partner_id: [8, "Client test"],
    currency_id: [1, "EUR"], move_type: "out_invoice", state: "posted",
    payment_state: "not_paid", amount_untaxed: 99, amount_tax: 19.8,
    amount_total: 118.8, amount_residual: 118.8, matched_payment_ids: [],
    x_sphot_reference: prepared.reference,
    x_sphot_fingerprint: prepared.fingerprint,
    x_sphot_sale_order_id: [6, "S00006"]};
  let hasOrder = false;
  const client = createSecureCheckoutClient({
    database: CHECKOUT_TEST_DATABASE,
    odooClient: {async call(model, method, body) {
      calls.push({model, method, body});
      if (model === "sale.order" && method === "search_read") {
        return hasOrder ? [{...order}] : [];
      }
      if (model === "sale.order.line" && method === "read") return [{...line}];
      if (model === "account.move" && method === "read") return [{...invoice}];
      if (model !== CHECKOUT_MODEL) throw new Error("Modèle interdit");
      if (method === DRAFT_METHOD) {
        assert.equal(body.sphot_reference, prepared.reference);
        assert.equal(body.sphot_fingerprint, prepared.fingerprint);
        assert.equal(body.expected_untaxed_cents, 9900);
        assert.deepEqual(body.order_values, prepared.orderValues);
        hasOrder = true;
        return {contract: ORDER_CONTRACT, outcome: "created",
          reference: prepared.reference, fingerprint: prepared.fingerprint,
          order: {...order}, line: {...line}};
      }
      if (method === INVOICE_METHOD) {
        assert.equal(body.sale_order_id, 6);
        assert.equal(body.expected_total_cents, 11880);
        order.state = "sale";
        order.invoice_ids = [11];
        return {contract: INVOICE_CONTRACT, outcome: "created",
          reference: prepared.reference, fingerprint: prepared.fingerprint,
          order: {...order}, invoice: {...invoice}};
      }
      throw new Error("Méthode interdite");
    }},
  });
  return {prepared, client, calls, order, line, invoice,
    setHasOrder: (value) => {hasOrder = value;}};
}

test("empreinte connue du 27/10/2026 et référence de dossier déterministe", () => {
  assert.equal(trustedFingerprint({
    reference: "SPHOT-PUB-PROD-20261027ABCDEF01", partnerId: 8,
    productId: 1, amountExclTaxCents: 9900, discountPercent: 0,
  }), "6a504500135df7ed1b2457a8dcebd4dd9fd4f6e15c53e33ae6380f9d10b512a7");
  assert.match(secureReferenceFor("TESTDOSSIER20261028"),
      /^SPHOT-PUB-PROD-[A-F0-9]{16}$/);
  assert.notEqual(secureReferenceFor("TESTDOSSIER20261028"),
      secureReferenceFor("TESTDOSSIER20261029"));
  assert.throws(() => trustedFingerprint({reference: "SPHOT-PUB-TEST-123",
    partnerId: 8, productId: 1, amountExclTaxCents: 9900,
    discountPercent: 0}), /invalides/);
});

test("interdiction de la base historique et d'une base de production", () => {
  for (const database of ["sphot_publicitaire_test", "production", "", null]) {
    assert.throws(() => createSecureCheckoutClient({database,
      odooClient: {call: async () => ({})}}), /neutralisée/);
  }
});

test("commande puis facture selon les signatures Python exactes", async () => {
  const f = fixture();
  assert.equal(await f.client.status(f.prepared), null);
  const draft = await f.client.draft(f.prepared);
  assert.equal(draft.outcome, "created");
  assert.equal(draft.order.state, "draft");
  const posted = await f.client.invoice(f.prepared);
  assert.equal(posted.outcome, "created");
  assert.equal(posted.invoice.state, "posted");
  assert.equal(posted.invoice.payment_state, "not_paid");
  assert.equal(f.calls.filter((call) => call.model === CHECKOUT_MODEL).length, 2);
});

test("après paiement : lecture seule, aucune nouvelle commande ni facture", async () => {
  const f = fixture();
  await f.client.draft(f.prepared);
  await f.client.invoice(f.prepared);
  f.invoice.payment_state = "paid";
  f.invoice.amount_residual = 0;
  f.invoice.matched_payment_ids = [55];
  const writesBefore = f.calls.filter((call) => call.model === CHECKOUT_MODEL).length;
  assert.equal((await f.client.draft(f.prepared)).outcome, "existing");
  assert.equal((await f.client.invoice(f.prepared)).outcome, "existing");
  assert.equal(f.calls.filter((call) => call.model === CHECKOUT_MODEL).length,
      writesBefore);
});

test("ligne altérée : reprise refusée sans appel d'écriture", async () => {
  const f = fixture();
  f.setHasOrder(true);
  f.line.price_unit = 1;
  await assert.rejects(f.client.draft(f.prepared), /Ligne de vente/);
  assert.equal(f.calls.filter((call) => call.model === CHECKOUT_MODEL).length, 0);
});

test("incohérence du devis refusée avant toute connexion Odoo", () => {
  assert.throws(() => prepareTrustedOrder({requestId: "TESTDOSSIER20261028",
    quote: {...quote, payableExclTaxCents: 500}, partnerId: 8,
    productId: 1}), /incoherent/i);
});
