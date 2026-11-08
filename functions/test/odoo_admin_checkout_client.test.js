/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {adminQuote} = require("../commercial_quote_pricing");
const {computeDiscountCents} = require("../commercial_discounts");
const {prepareAdminCheckout} =
  require("../local/odoo_admin_checkout_contract");
const {createAdminCheckoutClient, MODEL, DRAFT_METHOD, INVOICE_METHOD,
  STRIPE_EVIDENCE_METHOD, ORDER_CONTRACT, INVOICE_CONTRACT,
  STRIPE_EVIDENCE_CONTRACT} =
  require("../local/odoo_admin_checkout_client");

const DATABASE = "sphot_publicitaire_checkout_test";

function prepared() {
  const base = adminQuote({publishedVersion: 3,
    publishedPrices: [499, 399, 299, 199]}, 3);
  const quote = {...base, ...computeDiscountCents(base.amountExclTax, 10),
    fromServerPublishedCatalog: true};
  const net = quote.payableExclTaxCents / 100;
  const tax = Math.round(quote.payableExclTaxCents * 0.2) / 100;
  return prepareAdminCheckout({
    adminUid: "admin_uid_001", requestId: "admin_uid_001",
    cycleId: "cycle_2026_001", year: 2026,
    approval: {status: "approved", adminUid: "admin_uid_001",
      territoireId: "territoire_001", siret: "21630123400012",
      siren: "216301234"},
    buyer: {verified: true, relation: "manager", siret: "21630123400012",
      legalName: "Commune de Test", billingEmail: "compta@example.fr"},
    stations: ["station_001", "station_002", "station_003"].map(
        (spotDocumentId) => ({spotDocumentId,
          belongsToAdminTerritory: true, isRescueStation: true})),
    quote,
    fiscality: {status: "validated", calculationVerified: true,
      amountExclTax: net, taxAmount: tax, amountInclTax: net + tax,
      legalBasis: "TAX_DECISION_TEST"},
    legalAcceptance: {verified: true, adminUid: "admin_uid_001",
      version: "CGV_ADMIN_V3", acceptedAt: "2026-10-31T12:00:00Z"},
    paymentMethod: "public_invoice", partnerId: 42,
    adminTierProductIds: [11, 12, 13, 14],
  });
}

function makeOdoo(prep) {
  const calls = [];
  const lines = prep.locked.orderLines.map((line, i) => ({
    id: 100 + i, product_id: [line.productId, `Tranche ${i + 1}`],
    product_uom_qty: line.quantity, price_unit: line.priceUnit,
    discount: line.discount,
  }));
  const order = {
    id: 77, name: "S00077", state: "draft",
    client_order_ref: prep.reference,
    x_sphot_reference: prep.reference,
    x_sphot_fingerprint: prep.fingerprint,
    partner_id: [42, "Commune de Test"], currency_id: [1, "EUR"],
    amount_untaxed: prep.expectedUntaxedCents / 100,
    amount_tax: (prep.expectedTotalCents - prep.expectedUntaxedCents) / 100,
    amount_total: prep.expectedTotalCents / 100,
    order_line: lines.map((line) => line.id), invoice_ids: [],
  };
  const invoice = {
    id: 88, name: "FAC/2026/00088", invoice_origin: order.name,
    partner_id: [42, "Commune de Test"], currency_id: [1, "EUR"],
    move_type: "out_invoice", state: "posted", payment_state: "not_paid",
    amount_untaxed: order.amount_untaxed, amount_tax: order.amount_tax,
    amount_total: order.amount_total, amount_residual: order.amount_total,
    matched_payment_ids: [],
    x_sphot_reference: prep.reference,
    x_sphot_fingerprint: prep.fingerprint,
    x_sphot_sale_order_id: [order.id, order.name],
  };
  const fake = {calls, lines, order, invoice, hasOrder: false,
    async call(model, method, body) {
      calls.push({model, method, body});
      if (model === "sale.order" && method === "search_read") {
        return this.hasOrder ? [this.order] : [];
      }
      if (model === "sale.order.line" && method === "read") {
        return this.lines;
      }
      if (model === "account.move" && method === "read") {
        return [this.invoice];
      }
      if (model === MODEL && method === DRAFT_METHOD) {
        assert.equal(body.sphot_reference, prep.reference);
        assert.equal(body.expected_total_cents, prep.expectedTotalCents);
        assert.equal(body.order_values.order_line.length, 2);
        this.hasOrder = true;
        return {outcome: "created", contract: ORDER_CONTRACT,
          reference: prep.reference, fingerprint: prep.fingerprint,
          order: this.order};
      }
      if (model === MODEL && method === INVOICE_METHOD) {
        assert.equal(body.sale_order_id, order.id);
        this.order.state = "sale";
        this.order.invoice_ids = [this.invoice.id];
        return {outcome: "created", contract: INVOICE_CONTRACT,
          reference: prep.reference, fingerprint: prep.fingerprint,
          order: this.order, invoice: this.invoice};
      }
      if (model === MODEL && method === STRIPE_EVIDENCE_METHOD) {
        assert.equal(body.invoice_id, this.invoice.id);
        return {contract: STRIPE_EVIDENCE_CONTRACT,
          reference: prep.reference, fingerprint: prep.fingerprint,
          invoice_id: this.invoice.id,
          stripe_providers: [{id: 5, code: "stripe", is_live: false}],
          demo_providers: [{id: 6, code: "demo", is_published: false}],
          transactions: [{id: 99, reference: "STRIPE-TEST-001",
            provider_code: "stripe", provider_id: [5, "Stripe TEST"],
            currency_id: [1, "EUR"], invoice_ids: [this.invoice.id],
            state: "done", amount: this.invoice.amount_total}]};
      }
      throw new Error(`RPC inattendu ${model}.${method}`);
    },
  };
  return fake;
}

function client(fake, database = DATABASE) {
  return createAdminCheckoutClient({database, odooClient: fake});
}

function writeCalls(fake) {
  return fake.calls.filter((call) => call.model === MODEL &&
      [DRAFT_METHOD, INVOICE_METHOD].includes(call.method));
}

test("ADMIN Odoo : aucune connexion aux bases autres que TEST", () => {
  assert.throws(() => client(makeOdoo(prepared()), "sphot-ab80b"),
      /réservée à Odoo TEST/);
  assert.throws(() => client(makeOdoo(prepared()), "sphot_publicitaire"),
      /réservée à Odoo TEST/);
});

test("ADMIN Odoo : création multitranches et reprise idempotente", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  const checkout = client(fake);
  assert.equal(await checkout.status(prep), null);
  const first = await checkout.draft(prep);
  assert.equal(first.outcome, "created");
  assert.equal(first.order.id, 77);
  assert.equal(first.invoice, null);
  assert.equal((await checkout.draft(prep)).outcome, "existing");
  assert.deepEqual(writeCalls(fake).map((call) => call.method), [DRAFT_METHOD]);
});

test("ADMIN Odoo : ligne altérée refuse l'édition ou la facturation", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  fake.hasOrder = true;
  fake.lines[1].price_unit = 999;
  await assert.rejects(client(fake).invoice(prep), /Tranche ADMIN Odoo/);
  assert.equal(writeCalls(fake).length, 0);
});

test("ADMIN Odoo : données de commande modifiées refusées avant tout RPC", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  const altered = {...prep, orderValues: {...prep.orderValues,
    order_line: prep.orderValues.order_line.map((command) =>
      [0, 0, {...command[2]}])}};
  altered.orderValues.order_line[0][2].price_unit += 1;
  await assert.rejects(client(fake).draft(altered), /Lignes ADMIN/);
  assert.equal(fake.calls.length, 0);
});

test("ADMIN Odoo : total ou taxes Odoo incohérents bloquent toute écriture", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  fake.hasOrder = true;
  fake.order.amount_tax += 1;
  await assert.rejects(client(fake).invoice(prep),
      /Commande ADMIN Odoo incompatible/);
  assert.equal(writeCalls(fake).length, 0);
});

test("ADMIN Odoo : duplication de référence détectée", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  const original = fake.call.bind(fake);
  fake.call = async (model, method, body) =>
    model === "sale.order" && method === "search_read" ?
      [fake.order, {...fake.order, id: 78}] : original(model, method, body);
  await assert.rejects(client(fake).draft(prep), /dupliquée/);
  assert.equal(writeCalls(fake).length, 0);
});

test("ADMIN Odoo : confirmation et une seule facture, avec reprise", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  const checkout = client(fake);
  await checkout.draft(prep);
  const created = await checkout.invoice(prep);
  assert.equal(created.outcome, "created");
  assert.equal(created.order.state, "sale");
  assert.equal(created.invoice.state, "posted");
  assert.equal(created.invoice.payment_state, "not_paid");
  assert.equal((await checkout.invoice(prep)).outcome, "existing");
  assert.deepEqual(writeCalls(fake).map((call) => call.method),
      [DRAFT_METHOD, INVOICE_METHOD]);
});

test("ADMIN Odoo : facture déjà payée lue sans nouvelle écriture", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  fake.hasOrder = true;
  fake.order.state = "sale";
  fake.order.invoice_ids = [88];
  fake.invoice.payment_state = "paid";
  fake.invoice.amount_residual = 0;
  fake.invoice.matched_payment_ids = [50];
  const result = await client(fake).invoice(prep);
  assert.equal(result.outcome, "existing");
  assert.equal(result.invoice.payment_state, "paid");
  assert.equal(writeCalls(fake).length, 0);
});

test("ADMIN Odoo : engagement public possible après confirmation avant facture", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  fake.hasOrder = true;
  fake.order.state = "sale";
  const current = await client(fake).status(prep);
  assert.equal(current.order.state, "sale");
  assert.equal(current.invoice, null);
  assert.equal(writeCalls(fake).length, 0);
});

test("ADMIN Odoo : preuve Stripe seulement par la méthode restreinte", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  const checkout = client(fake);
  const evidence = await checkout.stripeEvidence(prep, fake.invoice);
  assert.equal(evidence.contract, STRIPE_EVIDENCE_CONTRACT);
  assert.deepEqual(fake.calls.map((call) => call.model), [MODEL]);
  assert.equal(fake.calls[0].method, STRIPE_EVIDENCE_METHOD);
});

test("ADMIN Odoo : paiement confirmé seulement après Stripe et rapprochement", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  fake.hasOrder = true;
  fake.order.state = "sale";
  fake.order.invoice_ids = [88];
  fake.invoice.payment_state = "paid";
  fake.invoice.amount_residual = 0;
  fake.invoice.matched_payment_ids = [50];
  const payment = await client(fake).verifiedStripePayment(prep);
  assert.equal(payment.transactionState, "done");
  assert.equal(payment.invoicePaymentState, "paid");
  assert.deepEqual(fake.calls.map((call) => call.model),
      ["sale.order", "sale.order.line", "account.move", MODEL]);
});

test("ADMIN Odoo : facture marquée payée sans rapprochement ne suffit pas", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  fake.hasOrder = true;
  fake.order.state = "sale";
  fake.order.invoice_ids = [88];
  fake.invoice.payment_state = "paid";
  fake.invoice.amount_residual = 0;
  await assert.rejects(client(fake).verifiedStripePayment(prep),
      /Facture ADMIN Odoo incompatible/);
  assert.equal(fake.calls.some((call) => call.model === MODEL), false);
});

test("ADMIN Odoo : prestataire Démo publié refuse le paiement Stripe", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  fake.hasOrder = true;
  fake.order.state = "sale";
  fake.order.invoice_ids = [88];
  fake.invoice.payment_state = "paid";
  fake.invoice.amount_residual = 0;
  fake.invoice.matched_payment_ids = [50];
  const original = fake.call.bind(fake);
  fake.call = async (model, method, body) => {
    const result = await original(model, method, body);
    if (model === MODEL && method === STRIPE_EVIDENCE_METHOD) {
      result.demo_providers[0].is_published = true;
    }
    return result;
  };
  await assert.rejects(client(fake).verifiedStripePayment(prep),
      /prestataires Odoo TEST/);
});

test("ADMIN Odoo : résultat atomique de mauvais contrat refusé", async () => {
  const prep = prepared();
  const fake = makeOdoo(prep);
  const original = fake.call.bind(fake);
  fake.call = async (model, method, body) => {
    const result = await original(model, method, body);
    return model === MODEL ? {...result, contract: "other_market"} : result;
  };
  await assert.rejects(client(fake).draft(prep), /Réponse atomique ADMIN/);
});
