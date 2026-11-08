/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Cycle CB entièrement fictif et DISTINCT de l'engagement public C4 TEST.
// Aucun paiement n'est créé par ce script. Stripe se teste dans Odoo en mode
// TEST. Firestore TEST ne change que lors de seed/activate avec deux opt-in.
const {adminQuote} = require("../commercial_quote_pricing");
const {computeDiscountCents} = require("../commercial_discounts");
const {prepareAdminCheckout} = require("./odoo_admin_checkout_contract");
const {createAdminCheckoutClient} = require("./odoo_admin_checkout_client");
const {createAdminTestFirestoreSync, assertAdminTestCloud} =
  require("./odoo_admin_test_firestore_sync");
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");
const {CHECKOUT_TEST_DATABASE} = require("./odoo_secure_checkout_client");
const {assertDestination, verifyOdooConfiguration} =
  require("./odoo_admin_test_fixture_invoice");

const UID = "sphot_admin_carte_fictive_2026";
const TERRITORY = "sphot_territoire_carte_fictif_2026";
const CYCLE = "sphot_cycle_carte_fictif_2026";
const SIRET = "00000000000000";
const STATIONS = ["sphot_carte_station_fictive_01",
  "sphot_carte_station_fictive_02"];
const SOURCE = "sphot_admin_card_test_fixture_v1";
const YEAR = 2026;
const VOLATILE = new Set(["approvedAt", "reviewedAt", "createdAt"]);

function refuse(reason) {
  const error = new Error("CARTE ADMIN TEST : " + reason);
  error.code = "ADMIN_CARD_TEST_REFUSED";
  return error;
}

function buildCardFixture() {
  const base = adminQuote({publishedVersion: 3,
    publishedPrices: [499, 399, 299, 199]}, STATIONS.length);
  const quote = {...base, ...computeDiscountCents(base.amountExclTax, 0),
    fromServerPublishedCatalog: true};
  const ht = quote.payableExclTaxCents / 100;
  const vat = Math.round(quote.payableExclTaxCents * .2) / 100;
  const prepared = prepareAdminCheckout({
    adminUid: UID, requestId: UID, cycleId: CYCLE, year: YEAR,
    approval: {status: "approved", adminUid: UID,
      territoireId: TERRITORY, siret: SIRET, siren: SIRET.slice(0, 9)},
    buyer: {verified: true, relation: "manager", siret: SIRET,
      legalName: "COLLECTIVITE FICTIVE CARTE SPHOT TEST",
      billingEmail: "card-fixture@example.invalid"},
    stations: STATIONS.map((spotDocumentId) => ({spotDocumentId,
      belongsToAdminTerritory: true, isRescueStation: true})),
    quote, fiscality: {status: "validated", calculationVerified: true,
      amountExclTax: ht, taxAmount: vat,
      amountInclTax: ht + vat, legalBasis: "FISCALITE_SIMULEE_CARTE_TEST"},
    legalAcceptance: {verified: true, adminUid: UID,
      version: "CGV_ADMIN_CARTE_FICTIVES_TEST_V1",
      acceptedAt: "2026-10-31T12:00:00.000Z"},
    paymentMethod: "card", partnerId: 8,
    adminTierProductIds: [2, 3, 4, 5],
  });
  return prepared;
}

function cardRecords(when = new Date()) {
  if (!(when instanceof Date) || !Number.isFinite(when.getTime())) {
    throw refuse("DATE_TEST_INVALID");
  }
  const prepared = buildCardFixture();
  const marker = {testOnly: true, source: SOURCE};
  const now = when.toISOString();
  const entries = [
    ["territoires", TERRITORY, {...marker, territoireId: TERRITORY,
      ville: "COMMUNE FICTIVE CARTE TEST", pays: "France"}],
    ...STATIONS.map((id) => [
      `territoires/${TERRITORY}/spots`, id, {...marker,
        spotDocumentId: id, territoireId: TERRITORY,
        type: "surveille", isRescueStation: true}]),
    ["adminRequests", UID, {...marker, uid: UID, status: "approved",
      territoire: {territoireId: TERRITORY, ville: "COMMUNE FICTIVE CARTE TEST"},
      structure: {nom: "COLLECTIVITE FICTIVE CARTE SPHOT TEST",
        siret: SIRET, siren: SIRET.slice(0, 9)}, approvedAt: now}],
    ["admins", UID, {...marker, uid: UID, role: "ADMIN",
      accessStatus: "approved", territoireId: TERRITORY,
      diffusionAccessGranted: false}],
    ["subscriptions", UID, {...marker, adminUid: UID,
      status: "awaiting_subscription", billingCycle: "annual",
      selectedRescueStationIds: [...STATIONS],
      billingOrganisation: "COLLECTIVITE FICTIVE CARTE SPHOT TEST",
      billingSiret: SIRET, odooAdminManaged: false}],
    ["adminOdooReviewEvidence", UID, {...marker,
      source: "test_fixture_superadmin_review",
      verifiedSuperAdminReview: true, status: "approved",
      adminUid: UID, territoireId: TERRITORY,
      siren: SIRET.slice(0, 9), siret: SIRET,
      reviewedByUid: "SIMULATED_SUPERADMIN_NOT_AUTHENTICATED",
      reviewedAt: now,
      superAdminChecks: {locality: true, siren: true, siret: true}}],
    ["adminOdooFixtureManifests", UID, {...marker, adminUid: UID,
      territoryId: TERRITORY, orderReference: prepared.reference,
      orderFingerprint: prepared.fingerprint,
      selectedRescueStationIds: [...STATIONS], paymentMethod: "card",
      disclaimer: "CARTE STRIPE TEST : AUCUN PAIEMENT REEL",
      createdAt: now}],
  ];
  return {prepared, entries};
}

function assertTestTarget(db, database) {
  assertDestination(db, database);
  if (process.env.FIRESTORE_EMULATOR_HOST) throw refuse("EMULATOR_FORBIDDEN");
}

function matchesFixture(expected, actual, {activated = false} = {}) {
  const mutable = activated ? new Set(["status", "odooAdminManaged",
    "diffusionAccessGranted"]) : new Set();
  return Object.keys(expected).filter((key) =>
    !VOLATILE.has(key) && !mutable.has(key)).every((key) =>
    JSON.stringify(actual[key]) === JSON.stringify(expected[key]));
}

async function checkCardFixture(db, {allowActivated = false} = {}) {
  const {prepared, entries} = cardRecords();
  const snaps = await Promise.all(entries.map(([path, id]) =>
    db.collection(path).doc(id).get()));
  const present = snaps.filter((snap) => snap.exists).length;
  if (present === 0) return {prepared, readyToSeed: true};
  if (present !== snaps.length) throw refuse("PARTIAL_FIXTURE");
  for (let i = 0; i < snaps.length; i++) {
    const [path, , expected] = entries[i];
    if (!matchesFixture(expected, snaps[i].data() || {},
        {activated: allowActivated && ["admins", "subscriptions"].includes(path)})) {
      throw refuse("FIXTURE_ALTERED:" + path);
    }
  }
  return {prepared, readyToSeed: false};
}

async function seedCardFixture(db, when = new Date()) {
  assertAdminTestCloud(db);
  if (process.env.SPHOT_ADMIN_TEST_CARD_SEED !== "true" ||
      when.getUTCFullYear() !== YEAR) {
    throw refuse("SEED_EXPLICIT_OPT_IN_REQUIRED");
  }
  const {prepared, entries} = cardRecords(when);
  return db.runTransaction(async (tx) => {
    const refs = entries.map(([path, id]) => db.collection(path).doc(id));
    const snaps = await Promise.all(refs.map((ref) => tx.get(ref)));
    const present = snaps.filter((snap) => snap.exists).length;
    if (present > 0) {
      if (present !== snaps.length || snaps.some((snap, i) =>
        !matchesFixture(entries[i][2], snap.data() || {}))) {
        throw refuse("FIXTURE_COLLISION");
      }
      return {testOnly: true, action: "none", reference: prepared.reference};
    }
    for (let i = 0; i < entries.length; i++) {
      tx.create(refs[i], entries[i][2]);
    }
    return {testOnly: true, action: "seeded",
      documentCount: entries.length, reference: prepared.reference};
  });
}

function assertOdooWriteOptIn() {
  if (process.env.SPHOT_ADMIN_TEST_CARD_INVOICE !== "true" ||
      process.env.SPHOT_ADMIN_TEST_ODOO_WRITES !== "true" ||
      process.env.SPHOT_ADMIN_TEST_ODOO_DATABASE !== CHECKOUT_TEST_DATABASE) {
    throw refuse("INVOICE_EXPLICIT_OPT_IN_REQUIRED");
  }
}

function assertActivationOptIn(db) {
  assertAdminTestCloud(db);
  if (process.env.SPHOT_ADMIN_TEST_CARD_ACTIVATE !== "true") {
    throw refuse("ACTIVATION_EXPLICIT_OPT_IN_REQUIRED");
  }
}

async function verifyStripeReadiness(checkout, prepared, invoice) {
  const evidence = await checkout.stripeEvidence(prepared, invoice);
  const stripe = evidence.stripe_providers;
  const demo = evidence.demo_providers;
  const transactions = evidence.transactions;
  const blockers = [];
  if (stripe.length !== 1 || stripe[0].code !== "stripe" ||
      stripe[0].is_live !== false || stripe[0].is_published !== true) {
    blockers.push("STRIPE_TEST_NOT_PUBLISHED");
  }
  if (demo.length !== 1 || demo[0].is_published !== false) {
    blockers.push("DEMO_PROVIDER_MUST_BE_UNPUBLISHED");
  }
  if (transactions.length !== 0) {
    blockers.push("EXISTING_STRIPE_TRANSACTION_REVIEW_REQUIRED");
  }
  return {stripeTestAvailable: blockers.indexOf("STRIPE_TEST_NOT_PUBLISHED") < 0,
    demoUnpublished: blockers.indexOf("DEMO_PROVIDER_MUST_BE_UNPUBLISHED") < 0,
    transactionCount: transactions.length, blockers};
}

async function runCardCycle({db, odooClient, database,
  checkoutFactory = createAdminCheckoutClient, mode = "preflight",
  now = new Date()} = {}) {
  assertTestTarget(db, database);
  if (!["preflight", "seed", "invoice", "stripe", "activate"].includes(mode) ||
      !(now instanceof Date) || !Number.isFinite(now.getTime()) ||
      now.getUTCFullYear() !== YEAR ||
      !odooClient || typeof odooClient.call !== "function") {
    throw refuse("INVALID_MODE_OR_CLIENT");
  }
  // Refuser AVANT tout RPC et toute écriture si l'opt-in est absent.
  if (mode === "invoice") assertOdooWriteOptIn();
  if (mode === "activate") assertActivationOptIn(db);
  if (mode === "seed") {
    assertAdminTestCloud(db);
    if (process.env.SPHOT_ADMIN_TEST_CARD_SEED !== "true") {
      throw refuse("SEED_EXPLICIT_OPT_IN_REQUIRED");
    }
  }
  const checked = await checkCardFixture(db, {allowActivated: true});
  if (mode === "seed") return seedCardFixture(db, now);
  if (checked.readyToSeed) {
    if (mode !== "preflight") throw refuse("FIXTURE_NOT_SEEDED");
    return {testOnly: true, action: "none", reference: checked.prepared.reference,
      selectedStationCount: STATIONS.length,
      expectedHtCents: checked.prepared.expectedUntaxedCents,
      expectedTtcCents: checked.prepared.expectedTotalCents,
      nextGate: "SEED_FIRESTORE_C4_TEST"};
  }
  await verifyOdooConfiguration(odooClient);
  const checkout = checkoutFactory({database, odooClient});
  const prepared = checked.prepared;
  let current = await checkout.status(prepared);
  if (mode === "invoice") {
    const existingCycle = await db.collection("adminOdooCycles")
        .doc(prepared.reference).get();
    if (existingCycle.exists) throw refuse("ALREADY_ACTIVATED");
    if (current?.invoice && current.invoice.payment_state !== "not_paid") {
      throw refuse("CARD_INVOICE_ALREADY_PAID_OR_MODIFIED");
    }
    if (!current) await checkout.draft(prepared);
    const invoice = await checkout.invoice(prepared);
    current = await checkout.status(prepared);
    if (!current?.invoice || current.invoice.state !== "posted" ||
        current.invoice.payment_state !== "not_paid") {
      throw refuse("INVOICE_NOT_POSTED_AND_UNPAID");
    }
    return {testOnly: true, action: invoice.outcome,
      reference: prepared.reference,
      orderNumber: current.order.name, orderId: current.order.id,
      invoiceNumber: current.invoice.name, invoiceId: current.invoice.id,
      expectedHtCents: prepared.expectedUntaxedCents,
      expectedTtcCents: prepared.expectedTotalCents,
      paymentStatus: "not_paid", firestoreActivationAttempted: false};
  }
  if (!current?.invoice) {
    if (mode !== "preflight") throw refuse("CARD_INVOICE_NOT_FOUND");
    return {testOnly: true, action: "none", reference: prepared.reference,
      nextGate: "INVOICE_ODOO_TEST_EXPLICIT_OPT_IN"};
  }
  if (mode === "activate") {
    await checkout.verifiedStripePayment(prepared);
    const sync = createAdminTestFirestoreSync({db, checkoutClient: checkout});
    const result = await sync.activate({prepared, activatedAt: now});
    return {...result, paymentStatus: "paid", stripeVerified: true};
  }
  const invoice = current.invoice;
  if (["in_payment", "partial"].includes(invoice.payment_state)) {
    return {testOnly: true, action: "none",
      reference: prepared.reference,
      invoiceNumber: invoice.name, paymentStatus: invoice.payment_state,
      stripeVerified: false, nextGate: "ODOO_RECONCILIATION_PENDING"};
  }
  if (invoice.payment_state !== "not_paid" &&
      invoice.payment_state !== "paid") {
    throw refuse("INVOICE_INTERMEDIATE_PAYMENT_STATE");
  }
  if (invoice.payment_state === "paid") {
    await checkout.verifiedStripePayment(prepared);
    return {testOnly: true, action: "none", reference: prepared.reference,
      paymentStatus: "paid", stripeVerified: true,
      nextGate: "ACTIVATE_TEST_AFTER_EXPLICIT_OPT_IN"};
  }
  const stripe = await verifyStripeReadiness(checkout, prepared, invoice);
  return {testOnly: true, action: "none",
    reference: prepared.reference,
    orderNumber: current.order.name, invoiceNumber: invoice.name,
    invoiceId: invoice.id, paymentStatus: invoice.payment_state,
    expectedTtcCents: prepared.expectedTotalCents, ...stripe,
    nextGate: stripe.blockers.length ? "ODOO_TEST_PAYMENT_CONFIGURATION" :
      "STRIPE_TEST_PAYMENT_IN_ODOO_UI"};
}

async function main(mode = "preflight") {
  if (!process.env.SPHOT_ODOO_LOCAL_API_KEY) {
    throw refuse("ODOO_TEST_API_KEY_MISSING");
  }
  const {readC4Credentials} = require("./start_c4_bridge");
  readC4Credentials();
  const admin = require("firebase-admin");
  const {createOdooClient} = require("./odoo_community_bridge_server");
  const app = admin.initializeApp({projectId: TEST_PROJECT_ID,
    credential: admin.credential.applicationDefault()},
  "sphot-admin-card-test-only");
  try {
    const result = await runCardCycle({db: admin.firestore(app),
      odooClient: createOdooClient({
        database: CHECKOUT_TEST_DATABASE,
        apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY}),
      database: CHECKOUT_TEST_DATABASE, mode});
    console.log("SPHOT ADMIN CARTE TEST :", JSON.stringify(result));
    console.log("AUCUN PAIEMENT CREE PAR CE SCRIPT. AUCUNE PRODUCTION.");
  } finally {
    await app.delete();
  }
}

if (require.main === module) {
  main(process.argv[2] || "preflight").catch((error) => {
    console.error("CARTE ADMIN TEST REFUSEE :", error.message);
    process.exitCode = 1;
  });
}

module.exports = {UID, TERRITORY, STATIONS, buildCardFixture,
  cardRecords, checkCardFixture, seedCardFixture, verifyStripeReadiness,
  assertOdooWriteOptIn, assertActivationOptIn, runCardCycle, main};
