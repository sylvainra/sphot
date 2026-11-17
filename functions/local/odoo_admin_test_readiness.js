/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Diagnostic LECTURE SEULE. Ne prépare aucune commande ni aucun abonnement.
// Les identifiants, noms, adresses et preuves ne sont jamais imprimés.
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");

const TEST_DATABASE = "sphot_publicitaire_checkout_test";
const KNOWN_REFERENCE = "SPHOT-ADM-TEST-014E00309CE1AFAC";
const KNOWN_FINGERPRINT =
  "6ac32f241dddee576f484d22c086e3ec52b6cb0f79dd829f0390e106bf532135";
const KNOWN_INVOICE_ID = 14;

function assertReadOnlyDestination(db, database) {
  if (!db || db.projectId !== TEST_PROJECT_ID ||
      database !== TEST_DATABASE || process.env.FIRESTORE_EMULATOR_HOST ||
      (process.env.GCLOUD_PROJECT &&
        process.env.GCLOUD_PROJECT !== TEST_PROJECT_ID) ||
      (process.env.GOOGLE_CLOUD_PROJECT &&
        process.env.GOOGLE_CLOUD_PROJECT !== TEST_PROJECT_ID)) {
    throw new Error("SPHOT ADMIN : diagnostic réservé à Odoo et Firestore TEST.");
  }
}

async function presence(db, name, approvedOnly = false) {
  const query = approvedOnly ? db.collection(name).where("status", "==", "approved") :
    db.collection(name);
  const snapshot = await query.limit(1).get();
  return !snapshot.empty;
}

async function checkAdminReadiness({db, odooClient, database} = {}) {
  assertReadOnlyDestination(db, database);
  if (!odooClient || typeof odooClient.call !== "function") {
    throw new Error("SPHOT ADMIN : client Odoo lecture seule absent.");
  }
  const model = await odooClient.call("sphot.admin.checkout", "search_read", {
    domain: [], fields: ["id"], limit: 1,
  });
  if (!Array.isArray(model)) {
    throw new Error("SPHOT ADMIN : addon Odoo inaccessible.");
  }
  const evidence = await odooClient.call("sphot.admin.checkout",
      "read_stripe_checkout_evidence", {
        sphot_reference: KNOWN_REFERENCE,
        sphot_fingerprint: KNOWN_FINGERPRINT,
        invoice_id: KNOWN_INVOICE_ID,
      });
  if (!evidence || evidence.contract !== "sphot_admin_stripe_evidence_v1" ||
      evidence.invoice_id !== KNOWN_INVOICE_ID ||
      evidence.reference !== KNOWN_REFERENCE ||
      evidence.fingerprint !== KNOWN_FINGERPRINT ||
      !Array.isArray(evidence.stripe_providers) ||
      !Array.isArray(evidence.demo_providers) ||
      !Array.isArray(evidence.transactions)) {
    throw new Error("SPHOT ADMIN : réponse des prestataires non vérifiable.");
  }

  const [approvedRequestPresent, initialReviewEvidencePresent,
    publicCommitmentEvidencePresent, cyclePresent] = await Promise.all([
    presence(db, "adminRequests", true),
    presence(db, "adminOdooReviewEvidence"),
    presence(db, "adminOdooEngagementEvidence"),
    presence(db, "adminOdooCycles"),
  ]);
  const demoPublished = evidence.demo_providers.some(
      (provider) => provider.is_published === true);
  const stripeTestPublished = evidence.stripe_providers.some(
      (provider) => provider.code === "stripe" &&
        provider.is_live === false && provider.is_published === true);
  return Object.freeze({
    destination: "ODOO_TEST + FIRESTORE_C4_TEST",
    addonOdooAccessible: true,
    invoiceControl: "POSTED_AND_LINKED_BY_RESTRICTED_ODOO_METHOD",
    stripeTestPublished,
    demoPublished,
    transactionsFound: evidence.transactions.length,
    approvedRequestPresent,
    initialReviewEvidencePresent,
    publicCommitmentEvidencePresent,
    cyclePresent,
    firestoreActivationAttempted: false,
    nextGate: !approvedRequestPresent ? "TEST_ADMIN_APPROVAL_REQUIRED" :
      !initialReviewEvidencePresent ? "SERVER_REVIEW_ARCHIVE_REQUIRED" :
        !publicCommitmentEvidencePresent ? "SERVER_CONTRACT_PROOF_REQUIRED" :
          "SERVER_EVIDENCE_AUDIT_REQUIRED",
  });
}

async function main() {
  if (!process.env.SPHOT_ODOO_LOCAL_API_KEY) {
    throw new Error("Clé Odoo TEST absente dans ce terminal VS Code.");
  }
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Émulateur Firestore actif : diagnostic cloud refusé.");
  }
  const {readC4Credentials} = require("./start_c4_bridge");
  readC4Credentials();
  const admin = require("firebase-admin");
  const {createOdooClient} = require("./odoo_community_bridge_server");
  const app = admin.initializeApp({projectId: TEST_PROJECT_ID,
    credential: admin.credential.applicationDefault()},
  "sphot-admin-readiness-only");
  try {
    const result = await checkAdminReadiness({db: admin.firestore(app),
      odooClient: createOdooClient({
        apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
        database: TEST_DATABASE,
      }), database: TEST_DATABASE});
    console.log("SPHOT ADMIN - DIAGNOSTIC SANS ECRITURE :");
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await app.delete();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error("DIAGNOSTIC REFUSE :", error.message);
    process.exitCode = 1;
  });
}

module.exports = {assertReadOnlyDestination, checkAdminReadiness};
