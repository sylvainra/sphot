"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {readOdooBillingStatus} = require("../odoo_billing_status");

const uid = "uid_admin_001";
const reference = "SPHOT-ADM-2026-ABCD1234";
const fingerprint = "a".repeat(64);

function adminWithCycle(cycle) {
  const documents = new Map([
    [`subscriptions/${uid}`, {odooAdminCycleRef: reference}],
    [`adminOdooCycles/${reference}`, cycle],
  ]);
  return {firestore: () => ({collection: (name) => ({doc: (id) => ({
    get: async () => ({exists: documents.has(`${name}/${id}`),
      data: () => documents.get(`${name}/${id}`)}),
  })})})};
}

function identity() {
  return {market: "ADMIN", requestId: uid, uid};
}

function readyCycle() {
  return {adminUid: uid, market: "ADMIN", orderReference: reference,
    orderFingerprint: fingerprint, testOnly: false};
}

test("Facturation: un cycle absent n'appelle jamais Odoo", async () => {
  let odooCalled = false;
  const result = await readOdooBillingStatus({
    admin: adminWithCycle(null), identity: identity(),
    odooClient: {call: async () => {odooCalled = true;}},
  });
  assert.deepEqual(result, {status: "not_linked"});
  assert.equal(odooCalled, false);
});

test("Facturation: un cycle TEST n'est jamais présenté comme réel", async () => {
  const result = await readOdooBillingStatus({
    admin: adminWithCycle({...readyCycle(), testOnly: true}),
    identity: identity(),
    odooClient: {call: async () => {throw new Error("Interdit");}},
  });
  assert.deepEqual(result, {status: "not_linked"});
});

test("Facturation: lecture d'une facture liée et rapprochée", async () => {
  const calls = [];
  const odooClient = {call: async (model, method, args) => {
    calls.push({model, method, args});
    if (model === "sale.order") return [{
      id: 12, name: "S0012", state: "sale",
      client_order_ref: reference,
      x_sphot_reference: reference, x_sphot_fingerprint: fingerprint,
      invoice_ids: [19],
    }];
    return [{
      id: 19, name: "FAC/2026/0019", state: "posted",
      move_type: "out_invoice", invoice_origin: "S0012",
      payment_state: "paid", currency_id: [1, "EUR"],
      amount_total: 120.45, amount_residual: 0,
      x_sphot_reference: reference, x_sphot_fingerprint: fingerprint,
      x_sphot_sale_order_id: [12, "S0012"],
    }];
  }};
  const result = await readOdooBillingStatus({
    admin: adminWithCycle(readyCycle()), identity: identity(), odooClient,
  });
  assert.equal(result.status, "invoice_found");
  assert.equal(result.invoiceNumber, "FAC/2026/0019");
  assert.equal(result.paymentState, "paid");
  assert.equal(result.amountTotalCents, 12045);
  assert.equal(result.activatesCommercialRights, false);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].model, "account.move");
});

test("Facturation: une facture d'une autre commande est rejetée", async () => {
  const odooClient = {call: async (model) => model === "sale.order" ? [{
    id: 12, name: "S0012", state: "sale",
    client_order_ref: reference,
    x_sphot_reference: reference, x_sphot_fingerprint: fingerprint,
    invoice_ids: [19],
  }] : [{
    id: 19, name: "FAC/2026/0019", state: "posted",
    move_type: "out_invoice", invoice_origin: "S0012",
    payment_state: "paid", currency_id: [1, "EUR"],
    amount_total: 10, amount_residual: 0,
    x_sphot_reference: reference, x_sphot_fingerprint: fingerprint,
    x_sphot_sale_order_id: [999, "Autre commande"],
  }]};
  await assert.rejects(readOdooBillingStatus({
    admin: adminWithCycle(readyCycle()), identity: identity(), odooClient,
  }), {httpStatus: 502});
});
