/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Dossier entièrement fictif : raccordement Odoo TEST uniquement.
// Mode preflight: lecture seule Firestore + Odoo.
// Mode invoice: ordre de vente + UNE facture Odoo TEST, après opt-in.
// Ne change aucun document Firebase, aucun droit, aucun paiement.
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");
const {CHECKOUT_TEST_DATABASE} = require("./odoo_secure_checkout_client");
const {createAdminCheckoutClient} = require("./odoo_admin_checkout_client");
const {fixture, fixtureRecords} = require("./odoo_admin_test_fixture");

const PARTNER_ID = 8;
const PRODUCT_IDS = [2, 3, 4, 5];
const VOLATILE_FIELDS = new Set([
  "approvedAt", "reviewedAt", "verifiedAt", "createdAt",
]);

function refuse(message) {
  const err = new Error(`SPHOT ADMIN FICTIF ODOO TEST : ${message}`);
  err.code = "TEST_FIXTURE_INVOICE_REFUSED";
  return err;
}

function assertDestination(db, database) {
  if (!db || db.projectId !== TEST_PROJECT_ID ||
      database !== CHECKOUT_TEST_DATABASE ||
      process.env.FIRESTORE_EMULATOR_HOST ||
      (process.env.GCLOUD_PROJECT &&
        process.env.GCLOUD_PROJECT !== TEST_PROJECT_ID) ||
      (process.env.GOOGLE_CLOUD_PROJECT &&
        process.env.GOOGLE_CLOUD_PROJECT !== TEST_PROJECT_ID)) {
    throw refuse("DESTINATION_TEST_ONLY");
  }
}

function assertOdooWriteAuthorized() {
  if (process.env.SPHOT_ADMIN_TEST_ODOO_WRITES !== "true" ||
      process.env.SPHOT_ADMIN_TEST_ODOO_DATABASE !==
        CHECKOUT_TEST_DATABASE) {
    throw refuse("ODOO_WRITE_EXPLICIT_OPT_IN_REQUIRED");
  }
}

async function verifySeededFixture(db) {
  const {prepared, entries} = fixtureRecords();
  const refs = entries.map(([collection, id]) => db.collection(collection).doc(id));
  const snapshots = await Promise.all(refs.map((ref) => ref.get()));
  for (let i = 0; i < refs.length; i++) {
    const snapshot = snapshots[i];
    const expected = entries[i][2];
    if (!snapshot.exists || Object.keys(expected)
        .filter((key) => !VOLATILE_FIELDS.has(key))
        .some((key) => JSON.stringify(snapshot.data()?.[key]) !==
          JSON.stringify(expected[key]))) {
      throw refuse(`FIXTURE_RECORD_MISSING_OR_ALTERED:${entries[i][0]}`);
    }
  }
  const existingCycle = await db.collection("adminOdooCycles")
      .doc(prepared.reference).get();
  if (existingCycle.exists) {
    throw refuse("ENTITLEMENT_CYCLE_ALREADY_PRESENT");
  }
  return prepared;
}

async function verifyOdooConfiguration(odooClient) {
  const products = await odooClient.call("product.product", "read", {
    ids: PRODUCT_IDS,
    fields: ["id", "name", "default_code", "type", "invoice_policy",
      "sale_ok", "active", "list_price"],
  });
  if (!Array.isArray(products) || products.length !== PRODUCT_IDS.length ||
      products.some((product, index) => product.id !== PRODUCT_IDS[index] ||
        product.default_code !== `SPHOT-ADM-TEST-T${index + 1}` ||
        product.type !== "service" || product.invoice_policy !== "order" ||
        product.sale_ok !== true || product.active !== true ||
        product.list_price !== 0)) {
    throw refuse("TEST_TIER_PRODUCTS_DIFFERENT_FROM_APPROVED_SETUP");
  }
  const partners = await odooClient.call("res.partner", "read", {
    ids: [PARTNER_ID],
    fields: ["id", "name", "is_company", "active", "country_id",
      "street", "zip", "city"],
  });
  if (!Array.isArray(partners) || partners.length !== 1 ||
      partners[0].id !== PARTNER_ID ||
      partners[0].name !== "SPHOT CLIENT API - TEST NEUTRALISE" ||
      partners[0].is_company !== true || partners[0].active !== true ||
      !partners[0].country_id || !partners[0].street ||
      !partners[0].zip || !partners[0].city) {
    throw refuse("ODOO_TEST_PARTNER_INCOMPLETE_OR_CHANGED");
  }
}

async function runFixtureInvoice({db, database, odooClient,
  checkoutFactory = createAdminCheckoutClient, mode = "preflight"} = {}) {
  assertDestination(db, database);
  if (!["preflight", "invoice"].includes(mode) ||
      !odooClient || typeof odooClient.call !== "function") {
    throw refuse("TEST_CLIENT_OR_MODE_INVALID");
  }
  if (mode === "invoice") assertOdooWriteAuthorized();
  const prepared = await verifySeededFixture(db);
  await verifyOdooConfiguration(odooClient);
  const checkout = checkoutFactory({database, odooClient});
  const previous = await checkout.status(prepared);
  if (previous?.invoice && previous.invoice.payment_state !== "not_paid") {
    throw refuse("TEST_INVOICE_IS_NOT_UNPAID");
  }
  if (mode === "preflight") {
    return {testOnly: true, action: "none", reference: prepared.reference,
      firestoreVerified: true, productsVerified: true,
      expectedHtCents: prepared.expectedUntaxedCents,
      expectedTtcCents: prepared.expectedTotalCents,
      odooOrderExists: Boolean(previous?.order),
      odooInvoiceExists: Boolean(previous?.invoice)};
  }

  // Atomic/idempotent RPCs de l'addon ADMIN uniquement. Toute erreur après
  // création de commande est récupérable par un nouvel appel avec la même
  // référence et empreinte; jamais de nouvelle référence à la volée.
  const draft = await checkout.draft(prepared);
  if (!draft?.order || !["draft", "sent", "sale"].includes(draft.order.state)) {
    throw refuse("ODOO_ADMIN_ORDER_NOT_VERIFIED");
  }
  const invoiced = await checkout.invoice(prepared);
  if (!invoiced?.order || invoiced.order.state !== "sale" ||
      !invoiced.invoice || invoiced.invoice.state !== "posted" ||
      invoiced.invoice.payment_state !== "not_paid" ||
      invoiced.invoice.amount_residual <= 0) {
    throw refuse("ODOO_TEST_INVOICE_NOT_POSTED_AND_UNPAID");
  }
  return {testOnly: true, action: invoiced.outcome,
    reference: prepared.reference,
    orderNumber: invoiced.order.name, orderId: invoiced.order.id,
    invoiceNumber: invoiced.invoice.name, invoiceId: invoiced.invoice.id,
    invoiceStatus: invoiced.invoice.state,
    paymentStatus: invoiced.invoice.payment_state,
    totalInclTax: invoiced.invoice.amount_total,
    residual: invoiced.invoice.amount_residual,
    firestoreActivationAttempted: false};
}

async function main(mode = "preflight") {
  if (!process.env.SPHOT_ODOO_LOCAL_API_KEY) {
    throw refuse("ODOO_TEST_API_KEY_MISSING_IN_VSCODE_TERMINAL");
  }
  const {readC4Credentials} = require("./start_c4_bridge");
  readC4Credentials();
  const admin = require("firebase-admin");
  const {createOdooClient} = require("./odoo_community_bridge_server");
  const app = admin.initializeApp({projectId: TEST_PROJECT_ID,
    credential: admin.credential.applicationDefault()},
  "sphot-admin-fixture-odoo-test");
  try {
    const result = await runFixtureInvoice({db: admin.firestore(app),
      odooClient: createOdooClient({
        apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
        database: CHECKOUT_TEST_DATABASE,
      }), database: CHECKOUT_TEST_DATABASE, mode});
    console.log("SPHOT ADMIN FICTIF ODOO TEST :", JSON.stringify(result));
  } finally {
    await app.delete();
  }
}

if (require.main === module) {
  main(process.argv[2] || "preflight").catch((err) => {
    console.error("RACCORDEMENT ODOO TEST REFUSE :", err.message);
    process.exitCode = 1;
  });
}

module.exports = {assertDestination, assertOdooWriteAuthorized,
  verifySeededFixture, verifyOdooConfiguration, runFixtureInvoice, main};
