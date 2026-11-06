"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {prepareCheckoutFromFirestore} =
  require("../odoo_checkout_verified_preparation");
const UID = "admin_1234567890";
const AD = "advert_123456789";
const CYCLE = "INITIAL_2026";
const siret = "12345678901234";
const hash = (x) => crypto.createHash("sha256")
    .update(JSON.stringify(x)).digest("hex");
const discountApi = {
  validateCustomer: (m, uid) => `${m}__${uid}`,
  validatePercent: (x) => x,
  computeDiscountCents: (amount, pct) => ({
    baseAmountExclTaxCents: amount * 100,
    discountPercent: pct,
    discountAmountCents: amount * pct,
    payableExclTaxCents: amount * (100 - pct),
  }),
};
const pricingApi = {
  publishedState: (snap, type) => {
    if (!snap.exists || snap.data().type !== type) throw Error("prix absents");
    return snap.data();
  },
  adminQuote: (_pub, count) => ({
    market: "ADMIN", version: 4, pricingReference: "FR_ADMIN-V4",
    country: "FR", currency: "EUR", numberOfRescueStations: count,
    amountExclTax: 400 * count,
    lines: Array.from({length: 4}, (_, i) => ({
      tier: i + 1, count: i === 0 ? count : 0,
      unitExclTax: 400, amountExclTax: i === 0 ? count * 400 : 0,
    })),
  }),
  advertiserQuote: (_pub, territory, offer, duration) => ({
    market: "ADVERTISER_RADIUS", version: 3,
    pricingReference: "FR_ADVERTISER_RADIUS-V3", country: "FR",
    currency: "EUR", amountExclTax: 149, territory, offer, duration,
  }),
};
function draft({quote, partnerId, productIds, sphotReference}) {
  const line = quote.market === "ADMIN" ? {
    name: `SPHOT ADMIN / Tranche 1 / Tarif ${quote.pricingReference}`,
    product_id: productIds.adminTiers[0], product_uom_qty: 2,
    price_unit: 400, discount: 0,
  } : {
    name: `SPHOT PUBLICITAIRE / ${quote.territory} / ${quote.offer} / ` +
      `${quote.duration} / Tarif ${quote.pricingReference}`,
    product_id: productIds.advertiser, product_uom_qty: 1,
    price_unit: 149, discount: 0,
  };
  return {expectedUntaxedCents: quote.payableExclTaxCents,
    values: {partner_id: partnerId, client_order_ref: sphotReference,
      origin: `SPHOT ${quote.pricingReference}`, order_line: [[0, 0, line]]}};
}
function fixture(market = "ADMIN") {
  const admin = market === "ADMIN";
  const uid = UID;
  const requestId = admin ? UID : AD;
  const legalId = admin ? "adminCgv" : "advertiserCgv";
  const stations = ["LONGE_09", "LONGE_13"];
  const dossier = admin ? {
    uid, territoireId: "territoire_longer_2026", accessStatus: "approved",
  } : {
    firebaseUid: uid, status: "approved", commercialCycleKey: CYCLE,
    advertisingSpotCompleted: true, diffusionCompleted: true,
    planningCompleted: true, campaignActivated: false,
    advertisingTerritory: {level: "radius_5km"},
    diffusion: {visibilityType: "map"}, planning: {durationLabel: "1 mois"},
    acceptedDocuments: {advertiserCgv: true, advertiserCgvVersion: "1.0",
      documentRevisions: {advertiserCgv: 2},
      acceptedAt: {seconds: 1793872800}},
  };
  const subscription = {
    selectedRescueStationIds: stations, numberOfRescueStations: 2,
    publishedPricingReference: "FR_ADMIN-V4", publishedPricingVersion: 4,
    billingPayerRelation: "manager", billingSiret: siret,
    billingCycle: "annual", commercialCycleKey: CYCLE,
    commercialCgvAcceptance: {adminUid: uid, documentId: "adminCgv",
      accepted: true, version: "1.0", revision: 2,
      acceptedAt: {seconds: 1793872800}},
  };
  const verification = {
    market, requestId, ownerUid: uid, cycleKey: CYCLE,
    status: "verified", testOnly: false,
    source: "sphot_server_odoo_verified_v1",
    verifiedAt: "2026-11-05T10:00:00Z", verifiedBy: "trusted_server",
    buyerEvidenceId: "partner_verified_1234",
    taxEvidenceId: "tax_verified_1234", partnerId: 45,
    productId: 21, adminTierProductIds: [11, 12, 13, 14],
    pricingReference: admin ? "FR_ADMIN-V4" : "FR_ADVERTISER_RADIUS-V3",
    cgvVersion: "1.0", cgvRevision: 2,
    expectedUntaxedCents: admin ? 80000 : 14900,
    expectedTotalCents: admin ? 96000 : 17880,
    buyerCountry: "FR", buyerLegalId: siret, buyerSiret: siret,
    choicesHash: hash(admin ? {stationIds: stations.slice().sort()} :
      {territory: "radius_5km", offer: "map", duration: "1 mois"}),
    stationIdsHash: hash(stations.slice().sort()),
    territoireId: dossier.territoireId,
  };
  const saved = new Map();
  const put = (c, id, x) => saved.set(`${c}/${id}`, x);
  put("commercialPricingMarkets", admin ? "FR_ADMIN" :
      "FR_ADVERTISER_RADIUS", {type: admin ? "ADMIN" : "ADVERTISER_RADIUS"});
  put("legalDocuments", legalId, {version: "1.0", revision: 2, published: true});
  if (admin) {
    put("subscriptions", requestId, subscription);
    put("odooAdminCgvAcceptanceEvidence", uid, {
      ...subscription.commercialCgvAcceptance,
      source: "sphot_admin_cgv_server_acceptance_v1", testOnly: false,
    });
  }
  put("odooCommercialVerifications", `${market}_${requestId}_${CYCLE}`,
      verification);
  const db = {collection(c) {return {doc(id) {return {
    async get() {const data = saved.get(`${c}/${id}`);
      return {exists: Boolean(data), data: () => data};},
  };}};}};
  const identity = {uid, market, requestId, dossier};
  const deps = {identity, db, admin: {}, pricingApi, discountApi,
    odooDraftBuilder: draft};
  return {deps, saved, dossier, subscription, verification, legalId,
    requestId};
}

test("ADMIN: preparation serveur des 2 postes, CGV versionnee, preuve TTC", async () => {
  const f = fixture();
  const p = await prepareCheckoutFromFirestore(f.deps);
  assert.equal(p.market, "ADMIN");
  assert.equal(p.expectedUntaxedCents, 80000);
  assert.equal(p.expectedTotalCents, 96000);
  assert.equal(p.verification.cgvVersion, "1.0");
  assert.match(p.reference, /^SPHOT-ADM-/);
  assert.match(p.fingerprint, /^[a-f0-9]{64}$/);
  assert.equal(p.testOnly, false);
});

test("PUBLICITAIRE: dossier approuve, devis serveur, CGV courantes", async () => {
  const f = fixture("ADVERTISER");
  const p = await prepareCheckoutFromFirestore(f.deps);
  assert.equal(p.market, "ADVERTISER");
  assert.equal(p.expectedUntaxedCents, 14900);
  assert.equal(p.expectedTotalCents, 17880);
  assert.match(p.reference, /^SPHOT-PUB-/);
});

test("la reference est stable pour le meme dossier et cycle", async () => {
  const f = fixture();
  const a = await prepareCheckoutFromFirestore(f.deps);
  const b = await prepareCheckoutFromFirestore(f.deps);
  assert.equal(a.reference, b.reference);
  assert.equal(a.fingerprint, b.fingerprint);
});

test("CGV Admin absentes bloquees", async () => {
  const f = fixture();
  f.saved.delete(`odooAdminCgvAcceptanceEvidence/${UID}`);
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /CGV/);
});

test("CGV annonceur perimees bloquees", async () => {
  const f = fixture("ADVERTISER");
  f.dossier.acceptedDocuments.documentRevisions.advertiserCgv = 1;
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /CGV/);
});

test("cycle manquant bloque avant la validation Odoo", async () => {
  const f = fixture();
  delete f.subscription.commercialCycleKey;
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /Cycle/);
});

test("changement de tarif bloque", async () => {
  const f = fixture();
  f.subscription.publishedPricingReference = "FR_ADMIN-V3";
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /Tarif/);
});

test("absence de verification Odoo cote serveur bloque", async () => {
  const f = fixture();
  f.saved.delete(`odooCommercialVerifications/ADMIN_${UID}_${CYCLE}`);
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /Odoo/);
});

test("TVA non verifiee bloque", async () => {
  const f = fixture();
  f.verification.expectedUntaxedCents = 70000;
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /Odoo/);
});

test("choix publicitaires modifies apres verification bloques", async () => {
  const f = fixture("ADVERTISER");
  f.dossier.diffusion.visibilityType = "pack";
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /Choix commerciaux/);
});

test("preuve des postes differente bloque", async () => {
  const f = fixture();
  f.verification.stationIdsHash = "invalid";
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /Postes/);
});

test("identite incoherente bloque", async () => {
  const f = fixture("ADVERTISER");
  f.deps.identity.requestId = "wrongID_00000";
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /Odoo/);
});

test("le preparateur ne declenche aucune ecriture ni paiement", async () => {
  const f = fixture();
  let calls = 0;
  f.deps.db.collection = new Proxy(f.deps.db.collection, {
    apply(target, thiz, args) {
      ++calls;
      return Reflect.apply(target, thiz, args);
    },
  });
  const p = await prepareCheckoutFromFirestore(f.deps);
  assert.ok(calls >= 4);
  assert.equal(p.verification.source, "sphot_server_firestore_verified");
});

test("CGV Admin falsifiees dans subscriptions ne donnent aucun droit", async () => {
  const f = fixture();
  f.saved.delete(`odooAdminCgvAcceptanceEvidence/${UID}`);
  f.subscription.commercialCgvAcceptance = {
    adminUid: UID, documentId: "adminCgv", accepted: true,
    version: "1.0", revision: 2, acceptedAt: {seconds: 1793872800},
  };
  await assert.rejects(() => prepareCheckoutFromFirestore(f.deps), /CGV/);
});
