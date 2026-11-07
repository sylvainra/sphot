/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// SPHOT ADMIN : scénario de collectivité TOTALEMENT FICTIF, C4 TEST seul.
// La preuve de filtrage Super Admin et le bon de commande sont SIMULÉS.
// Ce script ne touche ni à Odoo ni aux anciens dossiers PUBLICITAIRE.
const crypto = require("node:crypto");
const {adminQuote} = require("../commercial_quote_pricing");
const {computeDiscountCents} = require("../commercial_discounts");
const {prepareAdminCheckout} = require("./odoo_admin_checkout_contract");
const {assertAdminTestCloud} = require("./odoo_admin_test_firestore_sync");
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");

const ADMIN_UID = "sphot_admin_collectivite_fictive_2026";
const TERRITORY_ID = "sphot_territoire_fictif_2026";
const CYCLE_ID = "sphot_cycle_fictif_2026";
const SIRET = "00000000000000"; // Sentinelle TEST, aucune personne morale réelle.
const STATION_IDS = ["sphot_station_fictive_01", "sphot_station_fictive_02",
  "sphot_station_fictive_03"];
const SOURCE = "sphot_admin_test_fixture_v1";
const YEAR = 2026;

function fixture() {
  const base = adminQuote({publishedVersion: 3,
    publishedPrices: [499, 399, 299, 199]}, STATION_IDS.length);
  // Tarifs de validation TECHNIQUE : ne sont pas une publication commerciale.
  const quote = {...base,
    ...computeDiscountCents(base.amountExclTax, 0),
    fromServerPublishedCatalog: true};
  const ht = quote.payableExclTaxCents / 100;
  const vat = Math.round(quote.payableExclTaxCents * .2) / 100;
  const prepared = prepareAdminCheckout({
    adminUid: ADMIN_UID, requestId: ADMIN_UID, cycleId: CYCLE_ID, year: YEAR,
    approval: {status: "approved", adminUid: ADMIN_UID,
      territoireId: TERRITORY_ID, siret: SIRET,
      siren: SIRET.slice(0, 9)},
    buyer: {verified: true, relation: "manager", siret: SIRET,
      legalName: "COLLECTIVITE FICTIVE SPHOT TEST",
      billingEmail: "fixture-admin@example.invalid"},
    stations: STATION_IDS.map((spotDocumentId) => ({spotDocumentId,
      belongsToAdminTerritory: true, isRescueStation: true})),
    quote, fiscality: {status: "validated", calculationVerified: true,
      amountExclTax: ht, taxAmount: vat,
      amountInclTax: ht + vat, legalBasis: "FISCALITE_SIMULEE_TEST"},
    legalAcceptance: {verified: true, adminUid: ADMIN_UID,
      version: "CGV_ADMIN_FICTIVES_TEST_V1",
      acceptedAt: "2026-10-31T12:00:00.000Z"},
    paymentMethod: "public_invoice", partnerId: 8,
    adminTierProductIds: [2, 3, 4, 5],
  });
  const hash = crypto.createHash("sha256")
      .update(`DOCUMENT_FICTIF_SANS_VALEUR_CONTRACTUELLE|${prepared.reference}|`)
      .update(prepared.fingerprint).digest("hex");
  return {prepared, documentHash: hash};
}

function fixtureRecords(when = new Date()) {
  if (!(when instanceof Date) || !Number.isFinite(when.getTime())) {
    throw new Error("Horodatage TEST invalide.");
  }
  const {prepared, documentHash} = fixture();
  const now = when.toISOString();
  const marker = {testOnly: true, source: SOURCE};
  const entries = [
    ["territoires", TERRITORY_ID, {...marker,
      territoireId: TERRITORY_ID, ville: "COMMUNE FICTIVE TEST",
      pays: "France"}],
    ...STATION_IDS.map((stationId) => [
      `territoires/${TERRITORY_ID}/spots`, stationId,
      {...marker, spotDocumentId: stationId, territoireId: TERRITORY_ID,
        type: "surveille", isRescueStation: true}]),
    ["adminRequests", ADMIN_UID, {...marker, uid: ADMIN_UID,
      status: "approved", territoire: {territoireId: TERRITORY_ID,
        ville: "COMMUNE FICTIVE TEST"},
      structure: {nom: "COLLECTIVITE FICTIVE SPHOT TEST",
        siret: SIRET, siren: SIRET.slice(0, 9)},
      approvedAt: now}],
    ["admins", ADMIN_UID, {...marker, uid: ADMIN_UID,
      role: "ADMIN", accessStatus: "approved",
      territoireId: TERRITORY_ID, diffusionAccessGranted: false}],
    ["subscriptions", ADMIN_UID, {...marker, adminUid: ADMIN_UID,
      billingCycle: "annual", status: "awaiting_subscription",
      selectedRescueStationIds: [...STATION_IDS],
      billingOrganisation: "COLLECTIVITE FICTIVE SPHOT TEST",
      billingSiret: SIRET, odooAdminManaged: false}],
    ["adminOdooReviewEvidence", ADMIN_UID, {...marker,
      testOnly: true, source: "test_fixture_superadmin_review",
      verifiedSuperAdminReview: true, status: "approved",
      adminUid: ADMIN_UID, territoireId: TERRITORY_ID,
      siren: SIRET.slice(0, 9), siret: SIRET,
      reviewedByUid: "SIMULATED_SUPERADMIN_NOT_AUTHENTICATED",
      reviewedAt: now, superAdminChecks: {locality: true, siren: true,
        siret: true}}],
    ["adminOdooEngagementEvidence", prepared.reference, {...marker,
      status: "verified", documentType: "purchase_order",
      signerAuthorityVerified: true, buyerSiret: SIRET,
      orderReference: prepared.reference,
      orderFingerprint: prepared.fingerprint,
      documentHash, verifiedAt: now,
      verificationSource: "test_fixture_simulation",
      note: "BON DE COMMANDE SIMULE : AUCUN ENGAGEMENT REEL"}],
    ["adminOdooFixtureManifests", ADMIN_UID, {...marker,
      adminUid: ADMIN_UID, territoryId: TERRITORY_ID,
      orderReference: prepared.reference,
      orderFingerprint: prepared.fingerprint,
      selectedRescueStationIds: [...STATION_IDS], createdAt: now,
      disclaimer: "DONNEES ENTIEREMENT FICTIVES POUR TEST ODOO/FIRESTORE"}],
  ];
  return {prepared, entries};
}

function assertFixtureWrite(db) {
  assertAdminTestCloud(db);
  if (process.env.SPHOT_ADMIN_TEST_FIXTURE_WRITES !== "true") {
    throw new Error("FIXTURE_ADMIN_TEST_EXPLICIT_OPT_IN_REQUIRED");
  }
}

async function seedFixture(db, when = new Date()) {
  assertFixtureWrite(db);
  const {prepared, entries} = fixtureRecords(when);
  if (when.getUTCFullYear() !== YEAR) {
    throw new Error("FIXTURE_ADMIN_YEAR_EXPIRED");
  }
  return db.runTransaction(async (tx) => {
    const refs = entries.map(([collection, id]) => db.collection(collection).doc(id));
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    if (snapshots.some((snapshot) => snapshot.exists)) {
      // Une reprise est idempotente uniquement si tous les documents TEST
      // appartiennent déjà à ce scénario sans modification de sa liaison.
      if (snapshots.every((snapshot, index) => {
        if (!snapshot.exists) return false;
        const existing = snapshot.data() || {};
        const expected = entries[index][2];
        const volatile = new Set(["approvedAt", "reviewedAt",
          "verifiedAt", "createdAt"]);
        return Object.keys(expected).filter((key) => !volatile.has(key))
            .every((key) => JSON.stringify(existing[key]) ===
              JSON.stringify(expected[key]));
      })) {
        return {action: "none", testOnly: true,
          reason: "fixture_already_present", reference: prepared.reference};
      }
      throw new Error("FIXTURE_ADMIN_COLLISION_OR_PARTIAL_RECORDS");
    }
    for (let i = 0; i < refs.length; i++) {
      tx.create(refs[i], entries[i][2]);
    }
    return {action: "created", testOnly: true,
      documentCount: refs.length, reference: prepared.reference};
  });
}

async function main() {
  const {readC4Credentials} = require("./start_c4_bridge");
  readC4Credentials();
  const admin = require("firebase-admin");
  const app = admin.initializeApp({projectId: TEST_PROJECT_ID,
    credential: admin.credential.applicationDefault()},
  "sphot-admin-test-fixture");
  try {
    const result = await seedFixture(admin.firestore(app));
    console.log("DOSSIER ADMIN FICTIF FIRESTORE TEST :", JSON.stringify(result));
    console.log("AUCUNE COMMANDE ODOO ET AUCUNE ACTIVATION FIRESTORE.");
  } finally {
    await app.delete();
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error("DOSSIER ADMIN TEST REFUSE :", err.message);
    process.exitCode = 1;
  });
}

module.exports = {ADMIN_UID, TERRITORY_ID, STATION_IDS, fixture,
  fixtureRecords, assertFixtureWrite, seedFixture, main};
