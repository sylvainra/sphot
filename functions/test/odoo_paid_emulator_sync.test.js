"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {preparePaidCampaignSeed} =
  require("../local/odoo_paid_emulator_sync");
const {createLocalBridge} =
  require("../local/odoo_community_bridge_server");
const {secureReferenceFor} =
  require("../local/odoo_secure_checkout_client");
const {referenceFor} = require("../advertiser_initial_order");

const requestId = "TESTREALODOOCONNECT29";

/**
 * @return {Object} Dossier conforme aux champs réellement sauvés en phase 2.
 */
function dossier() {
  return {status: "approved", firebaseUid: "uid-real-test",
    advertisingSpotCompleted: true, diffusionCompleted: true,
    planningCompleted: true,
    acceptedDocuments: {cgu: true, privacy: true, rgpd: true,
      advertiserCgv: true},
    legalAcceptance: {representativeDeclaration: true},
    advertisingTerritory: {level: "radius_5km", radiusKm: 5},
    advertisingSpot: {latitude: 46.4, longitude: -1.5,
      bannerUrl: "https://example.test/saved-spot.webp"},
    approvedApplication: {visual: {
      url: "https://example.test/first-application.webp",
    }},
    diffusion: {visibilityType: "pack"},
    establishment: {businessName: "Annonceur enregistré"},
    application: {destinationUrl: "https://example.test/"},
    planning: {durationLabel: "1 semaine",
      campaignStartDate: new Date("2026-10-28T12:00:00Z"),
      campaignEndDate: new Date("2026-11-04T12:00:00Z")},
  };
}

/**
 * Encode le dossier comme une réponse REST Firestore existante.
 * @param {*} value Donnée côté serveur.
 * @return {Object} Format JSON Firestore.
 */
function firestoreValue(value) {
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "number") return {integerValue: String(value)};
  if (typeof value === "boolean") return {booleanValue: value};
  if (value == null) return {nullValue: null};
  return {mapValue: {fields: Object.fromEntries(Object.entries(value)
      .map(([key, item]) => [key, firestoreValue(item)]))}};
}

test("C3 : transforme le vrai dossier, sans coordonnées privées", () => {
  const original = dossier();
  const before = structuredClone(original);
  const {request, campaign} = preparePaidCampaignSeed(requestId, original);
  assert.equal(campaign.advertiserRequestId, requestId);
  assert.equal(campaign.bannerUrl,
      "https://example.test/saved-spot.webp");
  assert.equal(request.approvedApplication.visual.url, campaign.bannerUrl);
  assert.equal(campaign.centerLat, 46.4);
  assert.equal(campaign.centerLng, -1.5);
  assert.equal(campaign.radiusKm, 5);
  assert.equal(campaign.visibilityType, "pack");
  assert.equal(campaign.status, "draft");
  assert.equal(campaign.advertiserName, "Annonceur enregistré");
  assert.equal(Object.hasOwn(campaign, "contactEmail"), false);
  assert.equal(Object.hasOwn(request, "firebaseUid"), false);
  assert.deepEqual(original, before);
});

test("C3 : refuse le dossier incomplet ou la zone non prise en charge", () => {
  const changes = [
    (d) => {
      d.status = "pending";
    },
    (d) => {
      d.planningCompleted = false;
    },
    (d) => {
      d.advertisingTerritory.level = "country";
    },
    (d) => {
      d.advertisingSpot.latitude = 150;
    },
    (d) => {
      d.advertisingSpot.bannerUrl = "http://example.test/a.png";
    },
  ];
  for (const change of changes) {
    const original = dossier();
    change(original);
    assert.throws(() => preparePaidCampaignSeed(requestId, original));
  }
});

/**
 * @param {boolean} paid Si Odoo a enregistré le paiement.
 * @return {Object} Passerelle avec lecture Odoo authentifiée simulée.
 */
function bridgeFixture(paid) {
  const data = dossier();
  data.order = {origin: "sphot_advertiser_initial_v1",
    reference: referenceFor(requestId),
    publishedVersion: 1, pricingReference: "FR_ADVERTISER_RADIUS-V1",
    currency: "EUR", baseAmountExclTaxCents: 12900,
    discountPercent: 0, payableExclTaxCents: 12900};
  data.quoteOrderCompleted = true;
  const quote = {market: "ADVERTISER_RADIUS", version: 1,
    pricingReference: "FR_ADVERTISER_RADIUS-V1", currency: "EUR",
    previewOnly: true, amountExclTax: 129, discountPercent: 0,
    payableExclTaxCents: 12900};
  const fetchImpl = async (url) => {
    const payload = url.includes("firestore.googleapis.com") ?
      {fields: firestoreValue(data).mapValue.fields} :
      {success: true, quote};
    return {ok: true, status: 200, json: async () => payload};
  };
  const order = {id: 7, name: "S00007", state: "sale",
    client_order_ref: secureReferenceFor(requestId),
    amount_untaxed: 129, amount_tax: 25.8, amount_total: 154.8};
  const invoice = {id: 12, name: "FAC/2026/00007", state: "posted",
    payment_state: paid ? "paid" : "not_paid",
    currency_id: [1, "EUR"], amount_untaxed: 129,
    amount_tax: 25.8, amount_total: 154.8,
    amount_residual: paid ? 0 : 154.8,
    matched_payment_ids: paid ? [35] : []};
  const evidence = {stripe_providers: [{id: 7, code: "stripe",
    is_live: false, is_published: true}],
  demo_providers: [{id: 8, code: "demo", is_published: false}],
  transactions: paid ? [{id: 51, reference: "FAC/2026/00007",
    state: "done", provider_code: "stripe", provider_id: 7,
    amount: 154.8, currency_id: 1, invoice_ids: [12]}] : []};
  const published = [];
  const emulatorSync = {sync: async (input) => {
    published.push(input);
    return {simulationOnly: true, phase: "active", action: "activate"};
  }};
  const bridge = createLocalBridge({fetchImpl,
    verifyToken: async () => ({uid: "uid-real-test", role: "ANNONCEUR",
      advertiserRequestId: requestId}),
    odooClient: {call: async () => []},
    secureOdooClient: {call: async () => {
      throw new Error("Lecture brute interdite");
    }},
    secureCheckoutClient: {status: async () => ({order, invoice}),
      stripeEvidence: async () => evidence},
    securePartnerId: 8, secureProductId: 1, emulatorSync});
  return {bridge, published};
}

test("C3 : Odoo vérifié déclenche le raccordement local", async () => {
  const {bridge, published} = bridgeFixture(true);
  const status = await bridge.handle({action: "secure_stripe_status",
    requestId, token: "fake-firebase-token"});
  assert.equal(status.paymentConfirmed, true);
  assert.equal(status.campaignActivationAllowed, false);
  assert.equal(status.localPublication.action, "activate");
  assert.equal(published.length, 1);
  assert.equal(published[0].requestId, requestId);
  assert.equal(published[0].order.reference,
      secureReferenceFor(requestId));
  assert.equal(published[0].invoice.odooInvoiceName, "FAC/2026/00007");
});

test("C3 : paiement Odoo absent ne lance aucune écriture", async () => {
  const {bridge, published} = bridgeFixture(false);
  const status = await bridge.handle({action: "secure_stripe_status",
    requestId, token: "fake-firebase-token"});
  assert.equal(status.paymentConfirmed, false);
  assert.equal(status.campaignActivationAllowed, false);
  assert.equal(published.length, 0);
});
