/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createLocalBridge} = require("../local/odoo_community_bridge_server");

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
  const secureCheckoutClient = {
    async status(prepared) {calls.push({action: "status", prepared}); return null;},
    async draft(prepared) {
      calls.push({action: "draft", prepared});
      return {outcome: "created", order: {id: 6, name: "S00006",
        state: "draft", client_order_ref: prepared.reference,
        amount_untaxed: 99, amount_tax: 19.8, amount_total: 118.8},
      invoice: null};
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
  return {bridge, base, calls, fetchCalls};
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
