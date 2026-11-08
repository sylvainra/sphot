/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createLocalBridge, findStripeTestTransactions,
  stripeTestCheckoutUrl} = require("../local/odoo_community_bridge_server");

function firestoreValue(value) {
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (value == null) return {nullValue: null};
  return {mapValue: {fields: Object.fromEntries(Object.entries(value)
      .map(([key, item]) => [key, firestoreValue(item)]))}};
}

function fixture() {
  const requestId = "TESTSECUREDOSSIER28";
  const data = {status: "approved", firebaseUid: "uid-test",
    advertisingSpotCompleted: true, diffusionCompleted: true,
    planningCompleted: true,
    acceptedDocuments: {cgu: true, privacy: true, rgpd: true,
      advertiserCgv: true},
    legalAcceptance: {representativeDeclaration: true},
    advertisingTerritory: {level: "radius_5km"},
    diffusion: {visibilityType: "map"},
    planning: {durationLabel: "15 jours",
      campaignStartDate: new Date("2026-11-05T00:00:00.000Z")}};
  const quote = {market: "ADVERTISER_RADIUS", version: 1,
    pricingReference: "FR_ADVERTISER_RADIUS-V1", currency: "EUR",
    previewOnly: true, amountExclTax: 99, discountPercent: 0,
    payableExclTaxCents: 9900};
  const fetchCalls = [];
  const fetchImpl = async (url, options) => {
    fetchCalls.push({url, method: options?.method || "GET"});
    const value = url.includes("firestore.googleapis.com") ?
      {fields: firestoreValue(data).mapValue.fields} :
      url.includes("previewPublishedCommercialQuote") ?
        {success: true, quote} : null;
    if (!value) throw new Error("URL non attendue");
    return {ok: true, json: async () => value};
  };
  const calls = [];
  let currentStatus = null;
  let currentEvidence = null;
  const secureCheckoutClient = {
    async status(prepared) {
      calls.push({action: "status", prepared});
      return currentStatus;
    },
    async draft(prepared) {
      calls.push({action: "draft", prepared});
      return {outcome: "created", order: {id: 6, name: "S00006",
        state: "draft", client_order_ref: prepared.reference,
        amount_untaxed: 99, amount_tax: 19.8, amount_total: 118.8},
      invoice: null};
    },
    async stripeEvidence(prepared, invoice) {
      calls.push({action: "stripeEvidence", prepared, invoice});
      return currentEvidence;
    },
  };
  const legacyClient = {call: async () => {
    throw new Error("Ancien client Odoo ne doit pas être utilisé");
  }};
  const bridge = createLocalBridge({fetchImpl,
    verifyToken: async () => ({uid: "uid-test", role: "ANNONCEUR",
      advertiserRequestId: requestId}),
    odooClient: legacyClient, secureOdooClient: {call: async () => []},
    secureCheckoutClient, securePartnerId: 8, secureProductId: 1});
  const base = {token: "test-token", requestId};
  return {bridge, base, calls, fetchCalls,
    setStatus: (value) => {currentStatus = value;},
    setEvidence: (value) => {currentEvidence = value;}};
}

test("mode sécurisé : refuse les anciennes actions d'écriture", async () => {
  const f = fixture();
  await assert.rejects(f.bridge.handle({...f.base, action: "confirm"}),
      /Ancien parcours Odoo désactivé/);
  assert.equal(f.fetchCalls.length, 0);
});

test("mode sécurisé : devis serveur et référence PROD, sans écriture Firebase", async () => {
  const f = fixture();
  const response = await f.bridge.handle({...f.base, action: "secure_draft"});
  assert.equal(response.ok, true);
  assert.equal(response.testOnly, true);
  assert.equal(response.campaignActivationAllowed, false);
  assert.equal(response.order.odooState, "draft");
  assert.match(response.order.reference, /^SPHOT-PUB-PROD-[A-F0-9]{16}$/);
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].prepared.partnerId, 8);
  assert.equal(f.calls[0].prepared.productId, 1);
  assert.equal(f.calls[0].prepared.expectedUntaxedCents, 9900);
  assert.deepEqual(f.fetchCalls.map((call) => call.method), ["GET", "POST"]);
});

test("statut inexistant : aucun appel d'écriture Odoo", async () => {
  const f = fixture();
  const response = await f.bridge.handle({...f.base, action: "secure_status"});
  assert.equal(response.found, false);
  assert.equal(response.paymentConfirmed, false);
  assert.deepEqual(f.calls.map((call) => call.action), ["status"]);
});

function stripeInvoice() {
  return {id: 11, name: "FAC/2026/00006", state: "posted",
    payment_state: "not_paid", currency_id: [1, "EUR"],
    amount_untaxed: 99, amount_tax: 19.8, amount_total: 118.8,
    amount_residual: 118.8, matched_payment_ids: []};
}

function stripeEvidence() {
  return {stripe_providers: [{id: 7, code: "stripe", is_live: false,
    is_published: true}],
  demo_providers: [{id: 8, code: "demo", is_published: false}],
  transactions: []};
}

test("statut Stripe sécurisé : lecture restreinte, aucun accès direct aux modèles paiement", async () => {
  const f = fixture();
  const evidence = stripeEvidence();
  const invoice = stripeInvoice();
  f.setEvidence(evidence);
  // The authenticated dossier deterministically binds the SPHOT reference.
  const {secureReferenceFor} = require("../local/odoo_secure_checkout_client");
  const preparedReference = secureReferenceFor(f.base.requestId);
  const status = {order: {id: 6, name: "S00006", state: "sale",
    client_order_ref: preparedReference, amount_untaxed: 99,
    amount_tax: 19.8, amount_total: 118.8}, invoice};
  f.setStatus(status);
  const result = await f.bridge.handle({...f.base, action: "secure_stripe_status"});
  assert.equal(result.paymentConfirmed, false);
  assert.deepEqual(result.transactions, []);
  assert.deepEqual(f.calls.map(({action}) => action), ["status", "stripeEvidence"]);
});

test("preuve Stripe restreinte : refus Démo, montant incohérent ou statut incertain", async () => {
  const forbidden = {call: async () => {throw new Error("Lecture directe interdite");}};
  const invoice = stripeInvoice();
  const evidence = stripeEvidence();
  const empty = await findStripeTestTransactions(forbidden, invoice, evidence);
  assert.equal(empty.paymentConfirmed, false);

  evidence.transactions.push({id: 19, reference: "TEST-SANDBOX",
    state: "done", provider_code: "demo", provider_id: 8, amount: 118.8,
    currency_id: 1, invoice_ids: [11]});
  await assert.rejects(findStripeTestTransactions(forbidden, invoice, evidence),
      /Transaction Stripe TEST non conforme/);
  evidence.transactions[0].provider_code = "stripe";
  evidence.transactions[0].provider_id = 7;
  evidence.transactions[0].amount = 1;
  await assert.rejects(findStripeTestTransactions(forbidden, invoice, evidence),
      /Transaction Stripe TEST non conforme/);
  evidence.transactions[0].amount = 118.8;
  evidence.transactions[0].invoice_ids = [11, 99];
  await assert.rejects(findStripeTestTransactions(forbidden, invoice, evidence),
      /Transaction Stripe TEST non conforme/);
  evidence.transactions[0].invoice_ids = [11];
  const notPaid = await findStripeTestTransactions(forbidden, invoice, evidence);
  assert.equal(notPaid.paymentConfirmed, false);
  invoice.payment_state = "paid";
  invoice.amount_residual = 0;
  invoice.matched_payment_ids = [23];
  const paid = await findStripeTestTransactions(forbidden, invoice, evidence);
  assert.equal(paid.paymentConfirmed, true);
});

test("lien Stripe sécurisé : Démo publiée bloque toujours l'accès, sans lecture directe", async () => {
  const invoice = stripeInvoice();
  const evidence = stripeEvidence();
  const forbidden = {call: async () => {throw new Error("Lecture directe interdite");}};
  evidence.demo_providers[0].is_published = true;
  await assert.rejects(stripeTestCheckoutUrl(forbidden, invoice, evidence),
      /Masquez temporairement Démo/);
  evidence.demo_providers[0].is_published = false;
  const odoo = {call: async (model, method) => {
    assert.equal(model, "account.move");
    assert.equal(method, "get_portal_url");
    return "/my/invoices/11?access_token=test-only";
  }};
  const link = await stripeTestCheckoutUrl(odoo, invoice, evidence);
  assert.match(link, /^http:\/\/127\.0\.0\.1:8069\/my\/invoices\/11\?/);
});
