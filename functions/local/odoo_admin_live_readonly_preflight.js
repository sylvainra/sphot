/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Passerelle locale ADMIN : lecture seule Firebase SPHOT + Odoo TEST.
// Pas de commande, de facture, de paiement ni d'écriture Firestore.
const crypto = require("node:crypto");
const {adminQuote, publishedState} = require("../commercial_quote_pricing");
const {computeDiscountCents, validatePercent} =
  require("../commercial_discounts");
const {CHECKOUT_TEST_DATABASE} = require("./odoo_secure_checkout_client");

const FIREBASE_PROJECT_ID = "sphot-ab80b";
const TEST_DATABASE = CHECKOUT_TEST_DATABASE;
const PRODUCT_IDS = [2, 3, 4, 5];
const USER_ID = /^[a-zA-Z0-9_-]{6,128}$/;
const STATION_ID = /^[a-zA-Z0-9_-]{1,128}$/;
const SIRET = /^\d{14}$/;
const SIREN = /^\d{9}$/;

function blocked(reason, status = 409) {
  const error = new Error(reason);
  error.httpStatus = status;
  return error;
}

function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

function safeStations(values) {
  if (!Array.isArray(values) || values.length < 1 || values.length > 1000 ||
      values.some((id) => !STATION_ID.test(id)) ||
      new Set(values).size !== values.length) {
    throw blocked("ADMIN_STATION_SELECTION_INVALID", 400);
  }
  return [...values].sort();
}

function approvalFingerprint(uid, territoryId, siren, siret, locality) {
  return crypto.createHash("sha256")
      .update(JSON.stringify({requestId: uid,
        territoryId, siren, siret, locality})).digest("hex");
}

function assertInitialApproval(uid, request, administrator, subscription, proof) {
  const structure = request?.structure || {};
  const territory = request?.territoire || {};
  const siren = clean(structure.siren);
  const siret = clean(structure.siret);
  const territoryId = clean(territory.territoireId);
  const locality = {
    pays: clean(territory.pays), region: clean(territory.region),
    departement: clean(territory.departement), ville: clean(territory.ville),
  };
  const expected = approvalFingerprint(
      uid, territoryId, siren, siret, locality);
  if (!request || request.uid !== uid || request.status !== "approved" ||
      !administrator || administrator.uid !== uid ||
      clean(administrator.role).toLowerCase() !== "admin" ||
      administrator.accessStatus !== "approved" ||
      administrator.territoireId !== territoryId ||
      !subscription || subscription.adminUid !== uid ||
      !SIREN.test(siren) || !SIRET.test(siret) ||
      siret.slice(0, 9) !== siren ||
      !USER_ID.test(territoryId) ||
      !["france", "fr"].includes(locality.pays.toLowerCase()) ||
      !locality.region || !locality.departement || !locality.ville ||
      !proof || proof.source !== "server_review_archive" ||
      proof.status !== "approved" ||
      proof.verifiedSuperAdminReview !== true ||
      proof.adminUid !== uid ||
      proof.territoireId !== territoryId ||
      proof.siren !== siren || proof.siret !== siret ||
      proof.requestFingerprint !== expected ||
      !/^sphot-super-admin-[a-f0-9]{32}$/.test(clean(proof.reviewedByUid)) ||
      !proof.reviewedAt ||
      proof.superAdminChecks?.locality !== true ||
      proof.superAdminChecks?.siren !== true ||
      proof.superAdminChecks?.siret !== true) {
    throw blocked("ADMIN_SUPERADMIN_REVIEW_UNVERIFIED");
  }
  if (subscription.odooAdminManaged === true ||
      subscription.odooAdminCycleRef ||
      subscription.status === "active") {
    throw blocked("ADMIN_EXISTING_COMMERCIAL_CYCLE");
  }
  return {territoryId, locality};
}

function isRescueStation(data) {
  return data?.isPosteSecours === true ||
      clean(data?.typeSphot).toUpperCase().includes("POSTE DE SECOURS");
}

async function verifiedDoc(db, collection, id) {
  const snapshot = await db.collection(collection).doc(id).get();
  if (!snapshot.exists) throw blocked("ADMIN_REQUIRED_SERVER_RECORD_MISSING");
  return snapshot.data() || {};
}

async function assertOdooTierProducts(odooClient) {
  const products = await odooClient.call("product.product", "read", {
    ids: PRODUCT_IDS,
    fields: ["id", "default_code", "type", "invoice_policy",
      "sale_ok", "active", "list_price"],
  });
  if (!Array.isArray(products) || products.length !== 4 ||
      products.some((p, i) => p.id !== PRODUCT_IDS[i] ||
        p.default_code !== "SPHOT-ADM-TEST-T" + (i + 1) ||
        p.type !== "service" || p.invoice_policy !== "order" ||
        p.sale_ok !== true || p.active !== true || p.list_price !== 0)) {
    throw blocked("ODOO_ADMIN_TEST_PRODUCTS_UNVERIFIED");
  }
}

async function preflightAdminOffer({db, uid, stationIds,
  odooClient, database = TEST_DATABASE} = {}) {
  const ids = safeStations(stationIds);
  if (!db || db.projectId !== FIREBASE_PROJECT_ID ||
      !USER_ID.test(clean(uid)) ||
      database !== TEST_DATABASE ||
      !odooClient || typeof odooClient.call !== "function") {
    throw blocked("ADMIN_TEST_BRIDGE_DESTINATION_INVALID", 403);
  }
  const [request, administrator, subscription, review] = await Promise.all([
    verifiedDoc(db, "adminRequests", uid),
    verifiedDoc(db, "admins", uid),
    verifiedDoc(db, "subscriptions", uid),
    verifiedDoc(db, "adminOdooReviewEvidence", uid),
  ]);
  const {territoryId} = assertInitialApproval(uid,
      request, administrator, subscription, review);

  const spotCollection = "territoires/" + territoryId + "/spots";
  const spots = await Promise.all(ids.map((id) =>
    verifiedDoc(db, spotCollection, id)));
  if (spots.some((spot) => !isRescueStation(spot) ||
      (spot.territoireId && spot.territoireId !== territoryId))) {
    throw blocked("ADMIN_STATION_OUTSIDE_APPROVED_TERRITORY");
  }

  const [pricing, discountDoc] = await Promise.all([
    verifiedDoc(db, "commercialPricingMarkets", "FR_ADMIN"),
    db.collection("commercialCustomerDiscounts")
        .doc("ADMIN__" + uid).get(),
  ]);
  if (pricing.type !== "ADMIN") {
    throw blocked("ADMIN_PUBLISHED_PRICING_MARKET_INVALID");
  }
  const published = publishedState({exists: true, data: () => pricing},
      "ADMIN");
  const quote = adminQuote(published, ids.length);
  const discount = discountDoc.exists ?
    validatePercent(discountDoc.data()?.percent) : 0;
  const totals = computeDiscountCents(quote.amountExclTax, discount);
  await assertOdooTierProducts(odooClient);

  // Le SIRET du payeur, les CGV et le régime fiscal doivent être contrôlés
  // par une étape serveur distincte AVANT toute commande/facture Odoo.
  const buyerSiret = clean(subscription.billingSiret);
  const billingComplete = SIRET.test(buyerSiret) &&
      clean(subscription.billingOrganisation) !== "" &&
      clean(subscription.billingAddress) !== "" &&
      clean(subscription.billingPostalCode) !== "" &&
      clean(subscription.billingCity) !== "" &&
      /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
          clean(subscription.billingContactEmail));

  return Object.freeze({
    testOnly: true,
    action: "read_only_preflight",
    source: "authenticated_admin_server_verified",
    numberOfRescueStations: ids.length,
    pricingReference: quote.pricingReference,
    discountPercent: discount,
    baseExclTaxCents: totals.baseAmountExclTaxCents,
    payableExclTaxCents: totals.payableExclTaxCents,
    billingFieldsPresent: billingComplete,
    contractAndTaxVerified: false,
    odooProductsVerified: true,
    odooOrderCreated: false,
    odooInvoiceCreated: false,
    firestoreWriteAttempted: false,
    activationAllowed: false,
    nextGate: "BILLING_CGV_TAX_AND_ODOO_PARTNER_VERIFICATION",
  });
}

module.exports = {FIREBASE_PROJECT_ID, TEST_DATABASE,
  safeStations, assertInitialApproval, assertOdooTierProducts,
  preflightAdminOffer};
