/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// EXCLUSIVEMENT scénario fictif : engagement public simulé, JAMAIS un paiement.
// preflight : lecture seule Odoo + Firestore TEST.
// activate : projection idempotente des droits TEST avec opt-in explicite.
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");
const {CHECKOUT_TEST_DATABASE} = require("./odoo_secure_checkout_client");
const {fixtureRecords} = require("./odoo_admin_test_fixture");
const {createAdminCheckoutClient} = require("./odoo_admin_checkout_client");
const {createAdminTestFirestoreSync, assertAdminTestCloud} =
  require("./odoo_admin_test_firestore_sync");
const {assertDestination} = require("./odoo_admin_test_fixture_invoice");

const ORDER_ID = 9;
const INVOICE_ID = 15;
const INVOICE_TOTAL_CENTS = 155640;
const SAFE_CHANGED_FIELDS = new Map([
  ["subscriptions", new Set(["status", "odooAdminManaged"])],
  ["admins", new Set(["diffusionAccessGranted"])],
]);
const TIMESTAMPS = new Set([
  "approvedAt", "reviewedAt", "verifiedAt", "createdAt",
]);

function rejected(reason) {
  const err = new Error(`SPHOT ADMIN ACTIVATION FICTIVE : ${reason}`);
  err.code = "TEST_ADMIN_ACTIVATION_REFUSED";
  return err;
}

function assertActivationOptIn(db) {
  assertAdminTestCloud(db);
  if (process.env.SPHOT_ADMIN_TEST_ACTIVATE !== "true") {
    throw rejected("EXPLICIT_ACTIVATION_OPT_IN_REQUIRED");
  }
}

async function verifyFixtureStillValid(db) {
  const {prepared, entries} = fixtureRecords();
  const snapshots = await Promise.all(entries.map(([path, id]) =>
    db.collection(path).doc(id).get()));
  for (let i = 0; i < snapshots.length; i++) {
    const [path, , expected] = entries[i];
    const snap = snapshots[i];
    if (!snap.exists) throw rejected(`MISSING_FIXTURE:${path}`);
    const actual = snap.data() || {};
    const mutable = SAFE_CHANGED_FIELDS.get(path) || new Set();
    if (Object.keys(expected).filter((key) =>
      !TIMESTAMPS.has(key) && !mutable.has(key)).some((key) =>
      JSON.stringify(actual[key]) !== JSON.stringify(expected[key]))) {
      throw rejected(`ALTERED_FIXTURE:${path}`);
    }
  }
  return prepared;
}

function verifyInvoiceUnpaid(status, prepared) {
  const order = status?.order;
  const invoice = status?.invoice;
  if (!order || order.id !== ORDER_ID || order.name !== "S00009" ||
      order.state !== "sale" || order.x_sphot_reference !== prepared.reference ||
      order.x_sphot_fingerprint !== prepared.fingerprint ||
      !invoice || invoice.id !== INVOICE_ID ||
      invoice.name !== "FAC/2026/00009" ||
      invoice.state !== "posted" || invoice.payment_state !== "not_paid" ||
      Math.round(invoice.amount_total * 100) !== INVOICE_TOTAL_CENTS ||
      Math.round(invoice.amount_residual * 100) !== INVOICE_TOTAL_CENTS) {
    throw rejected("ODOO_TEST_POSTED_INVOICE_NOT_UNPAID_OR_UNLINKED");
  }
}

function stamp(value) {
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  return NaN;
}

async function verifyCycleProjection(db, prepared) {
  const [cycleSnap, subSnap, adminSnap, requestSnap] = await Promise.all([
    db.collection("adminOdooCycles").doc(prepared.reference).get(),
    db.collection("subscriptions").doc(prepared.locked.adminUid).get(),
    db.collection("admins").doc(prepared.locked.adminUid).get(),
    db.collection("adminRequests").doc(prepared.locked.adminUid).get(),
  ]);
  const cycle = cycleSnap.exists ? cycleSnap.data() || {} : null;
  const subscription = subSnap.exists ? subSnap.data() || {} : null;
  const administrative = adminSnap.exists ? adminSnap.data() || {} : null;
  const request = requestSnap.exists ? requestSnap.data() || {} : null;
  const {entries} = fixtureRecords();
  const contractRecord = entries.find(([name]) =>
    name === "adminOdooEngagementEvidence")?.[2];
  if (!cycle || !subscription || !administrative || !request ||
      cycle.source !== "odoo_admin_v1" ||
      cycle.testOnly !== true || cycle.adminUid !== prepared.locked.adminUid ||
      cycle.orderReference !== prepared.reference ||
      cycle.orderFingerprint !== prepared.fingerprint ||
      cycle.odooOrderId !== ORDER_ID || cycle.odooInvoiceId !== INVOICE_ID ||
      cycle.paymentMethod !== "public_invoice" ||
      cycle.activationBasis !== "verified_public_commitment" ||
      cycle.paymentStatus !== "not_paid" ||
      cycle.commitmentDocumentHash !== contractRecord?.documentHash ||
      JSON.stringify(cycle.selectedRescueStationIds) !==
        JSON.stringify(prepared.locked.stationIds) ||
      stamp(cycle.validUntilExclusive) !==
        new Date("2026-12-31T23:00:00.000Z").getTime() ||
      subscription.adminUid !== prepared.locked.adminUid ||
      subscription.status !== "active" ||
      subscription.odooAdminManaged !== true ||
      subscription.odooPaymentStatus !== "not_paid" ||
      subscription.odooAdminCycleRef !== prepared.reference ||
      JSON.stringify(subscription.selectedRescueStationIds) !==
        JSON.stringify(prepared.locked.stationIds) ||
      stamp(subscription.subscriptionEndDate) !==
        new Date("2026-12-31T22:59:59.999Z").getTime() ||
      administrative.diffusionAccessGranted !== true ||
      administrative.odooAdminCycleRef !== prepared.reference ||
      request.accessPhase !== "subscription_active") {
    throw rejected("FIRESTORE_CYCLE_PROJECTION_INCONSISTENT");
  }
  return {testOnly: true, rightsActive: true,
    activationBasis: cycle.activationBasis,
    paymentStatus: cycle.paymentStatus,
    reference: prepared.reference,
    validUntilInclusiveParis: "31/12/2026",
    firestoreCycleVerified: true};
}

async function runFixtureActivation({db, database, checkoutClient,
  mode = "preflight", now = new Date()} = {}) {
  assertDestination(db, database);
  if (!["preflight", "activate"].includes(mode) ||
      !checkoutClient || typeof checkoutClient.status !== "function" ||
      typeof checkoutClient.verifiedStripePayment !== "function" ||
      !(now instanceof Date) || !Number.isFinite(now.getTime()) ||
      now.getUTCFullYear() !== 2026 ||
      now >= new Date("2026-12-31T23:00:00.000Z")) {
    throw rejected("MODE_OR_ODOO_CLIENT_INVALID");
  }
  if (mode === "activate") assertActivationOptIn(db);
  const prepared = await verifyFixtureStillValid(db);
  const odoo = await checkoutClient.status(prepared);
  verifyInvoiceUnpaid(odoo, prepared);
  if (mode === "preflight") {
    const existingCycle = await db.collection("adminOdooCycles")
        .doc(prepared.reference).get();
    if (existingCycle.exists) {
      return {testOnly: true, action: "none",
        ...(await verifyCycleProjection(db, prepared)),
        reason: "already_active"};
    }
    return {testOnly: true, action: "none", readyToActivate: true,
      orderId: ORDER_ID, invoiceId: INVOICE_ID,
      amountResidualCents: INVOICE_TOTAL_CENTS,
      paymentStatus: "not_paid", reference: prepared.reference};
  }
  const sync = createAdminTestFirestoreSync({db, checkoutClient});
  const result = await sync.activate({prepared, activatedAt: now});
  const verified = await verifyCycleProjection(db, prepared);
  return {...result, ...verified};
}

async function main(mode = "preflight") {
  if (!process.env.SPHOT_ODOO_LOCAL_API_KEY) {
    throw rejected("ODOO_TEST_API_KEY_MISSING_IN_VSCODE_TERMINAL");
  }
  const {readC4Credentials} = require("./start_c4_bridge");
  readC4Credentials();
  const admin = require("firebase-admin");
  const {createOdooClient} = require("./odoo_community_bridge_server");
  const app = admin.initializeApp({projectId: TEST_PROJECT_ID,
    credential: admin.credential.applicationDefault()},
  "sphot-admin-fixture-activation-test");
  try {
    const odooClient = createOdooClient({
      apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
      database: CHECKOUT_TEST_DATABASE,
    });
    const result = await runFixtureActivation({db: admin.firestore(app),
      database: CHECKOUT_TEST_DATABASE,
      checkoutClient: createAdminCheckoutClient({
        database: CHECKOUT_TEST_DATABASE, odooClient}), mode});
    console.log("SPHOT ADMIN - ACTIVATION FIRESTORE TEST :",
        JSON.stringify(result));
    console.log("ENGAGEMENT SIMULE, FACTURE ODOO NON PAYEE, PAS DE PRODUCTION.");
  } finally {
    await app.delete();
  }
}

if (require.main === module) {
  main(process.argv[2] || "preflight").catch((error) => {
    console.error("ACTIVATION ADMIN TEST REFUSEE :", error.message);
    process.exitCode = 1;
  });
}

module.exports = {assertActivationOptIn, verifyFixtureStillValid,
  verifyInvoiceUnpaid, verifyCycleProjection, runFixtureActivation, main};
