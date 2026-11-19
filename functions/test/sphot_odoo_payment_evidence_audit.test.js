"use strict";

// Tests 100 % hors ligne, sans Odoo reel ni paiement Stripe.
const test = require("node:test");
const assert = require("node:assert/strict");
const {createReadOnlyClient, inspectPaymentEvidence, SCENARIOS, CLONE} =
    require("../local/sphot_odoo_payment_evidence_audit");

function mockClient(changes = {}) {
  const calls = [];
  const fingerprint = "b".repeat(64);
  async function call(model, method, body) {
    calls.push({model, method, body});
    const scenario = model === "sale.order" ?
      SCENARIOS.find(x => x.reference === body.domain[0][2]) :
      model === "account.move" ?
        SCENARIOS.find(x => x.invoiceId === body.ids[0]) :
        SCENARIOS[1];
    assert.ok(scenario);
    const isAdmin = scenario.market === "ADMIN";
    if (model === "sale.order" && method === "search_read") {
      const order = {
        id: scenario.orderId, name: "S000" + scenario.orderId,
        state: "sale", invoice_ids: [scenario.invoiceId],
        x_sphot_reference: scenario.reference,
        x_sphot_fingerprint: fingerprint,
      };
      Object.assign(order, changes.order || {});
      return [order];
    }
    if (model === "account.move" && method === "read") {
      const untaxed = isAdmin ? 500 : 149;
      const tax = isAdmin ? 100 : 29.8;
      const invoice = {
        id: scenario.invoiceId, name: "INV/TEST/" + scenario.invoiceId,
        state: "posted", move_type: "out_invoice",
        payment_state: "not_paid",
        amount_untaxed: untaxed, amount_tax: tax,
        amount_total: untaxed + tax, amount_residual: untaxed + tax,
        currency_id: [1, "EUR"],
        x_sphot_reference: scenario.reference,
        x_sphot_fingerprint: fingerprint,
        x_sphot_sale_order_id: [scenario.orderId, "S"],
      };
      Object.assign(invoice, changes.invoice || {});
      return [invoice];
    }
    if (model === "sphot.advertiser.checkout" &&
        method === "read_stripe_checkout_evidence") {
      const response = {
        contract: "sphot_advertiser_stripe_evidence_v1",
        reference: scenario.reference,
        fingerprint,
        invoice_id: scenario.invoiceId,
        stripe_providers: [], demo_providers: [], transactions: [],
      };
      Object.assign(response, changes.stripe || {});
      return response;
    }
    throw Error("Operation de lecture inattendue");
  }
  return {client: {call}, calls};
}

test("2 factures TEST impayees, preuve Stripe lue sans certifier de paiement",
    async () => {
      const f = mockClient();
      const results = await inspectPaymentEvidence({odooClient: f.client});
      assert.equal(results.length, 2);
      assert.deepEqual(results.map(x => x.invoiceId), [18, 19]);
      assert.ok(results.every(x => x.paymentState === "not_paid"));
      assert.equal(results[1].stripeProviders, 0);
      assert.equal(results[1].transactions, 0);
      assert.equal(f.calls.length, 5);
      assert.deepEqual(f.calls.map(x => x.method), [
        "search_read", "read", "search_read", "read",
        "read_stripe_checkout_evidence",
      ]);
    });

test("facture indiquee payee : pas de faux succes de l'audit TEST",
    async () => {
      const f = mockClient({invoice: {
        payment_state: "paid", amount_residual: 0,
      }});
      await assert.rejects(
          inspectPaymentEvidence({odooClient: f.client}),
          /facture non neutralisee/);
      assert.equal(f.calls.length, 2);
    });

test("commande rattachee a une autre facture refusee", async () => {
  const f = mockClient({order: {invoice_ids: [999]}});
  await assert.rejects(inspectPaymentEvidence({odooClient: f.client}),
      /rattachement/);
});

test("preuve Stripe incorrecte ou non conforme refusee", async () => {
  const f = mockClient({stripe: {contract: "fake_evidence"}});
  await assert.rejects(inspectPaymentEvidence({odooClient: f.client}),
      /incompatible/);
});

test("API Odoo locale bornee a trois methodes de LECTURE", async () => {
  const requests = [];
  const client = createReadOnlyClient({
    apiKey: "CLE_FACTICE_TEST_12345",
    fetchImpl: async (url, options) => {
      requests.push({url, options});
      return {ok: true, json: async () => []};
    },
  });
  await client.call("sale.order", "search_read", {domain: []});
  await client.call("account.move", "read", {ids: [19]});
  await client.call("sphot.advertiser.checkout",
      "read_stripe_checkout_evidence", {
        sphot_reference: "test", sphot_fingerprint: "a".repeat(64),
        invoice_id: 19,
      });
  assert.equal(requests.length, 3);
  for (const {url, options} of requests) {
    assert.match(url, /^http:\/\/127\.0\.0\.1:8069\/json\/2\//);
    assert.equal(options.headers["X-Odoo-Database"], CLONE);
    assert.equal(options.method, "POST");
    assert.equal(options.redirect, "error");
  }
  await assert.rejects(client.call("account.move", "create", {}),
      /lecture seule/);
  await assert.rejects(client.call("sale.order", "write", {}),
      /lecture seule/);
  await assert.rejects(
      client.call("sphot.advertiser.checkout",
          "confirm_and_post_one_invoice", {}),
      /lecture seule/);
  assert.equal(requests.length, 3);
});

test("aucune cle API : audit impossible", () => {
  assert.throws(() => createReadOnlyClient({apiKey: ""}), /Cle API/);
});
