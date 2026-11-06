/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// SPHOT ADMIN : projection Firestore uniquement sur le projet TEST C4.
// AUCUN endpoint, aucun déploiement, aucune écriture possible sans opt-in.
// L'engagement vérifié est une preuve CONTRACTUELLE, jamais de paiement.
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");
const {buildAdminActivationProjection} =
  require("./odoo_admin_firestore_projection");

const APPROVAL_COLLECTION = "adminOdooReviewEvidence";
const COMMITMENT_COLLECTION = "adminOdooEngagementEvidence";
const CONTRACT_TYPES = new Set([
  "purchase_order", "notified_public_contract", "accepted_quote",
]);

function error(reason) {
  const result = new Error(`SPHOT ADMIN TEST : ${reason}`);
  result.code = reason;
  return result;
}

function assertAdminTestCloud(db) {
  if (!db || db.projectId !== TEST_PROJECT_ID ||
      process.env.SPHOT_ADMIN_TEST_FIRESTORE_WRITES !== "true" ||
      process.env.SPHOT_ADMIN_TEST_PROJECT_ID !== TEST_PROJECT_ID ||
      process.env.GCLOUD_PROJECT !== TEST_PROJECT_ID ||
      process.env.GOOGLE_CLOUD_PROJECT !== TEST_PROJECT_ID ||
      process.env.FIRESTORE_EMULATOR_HOST) {
    throw error("TEST_FIRESTORE_ONLY");
  }
}

function read(snapshot) {
  return snapshot && snapshot.exists ? snapshot.data() || {} : null;
}

function assertInitialSuperAdminReview(review, request, admin, prepared) {
  const terms = prepared.locked;
  const requestTerritory = request?.territoire || {};
  const structure = request?.structure || {};
  // Les preuves simulées sont permises exclusivement par ce writer C4 TEST,
  // avec une origine explicitement marquée. Elles ne certifient rien en réel.
  const simulated = review?.source === "test_fixture_superadmin_review" &&
    review?.testOnly === true &&
    review?.superAdminChecks?.locality === true &&
    review?.superAdminChecks?.siren === true &&
    review?.superAdminChecks?.siret === true;
  if (!review || review.verifiedSuperAdminReview !== true ||
      !(review.source === "server_review_archive" || simulated) ||
      review.status !== "approved" ||
      review.adminUid !== terms.adminUid ||
      review.territoireId !== terms.territoireId ||
      review.siren !== terms.managerSiret.slice(0, 9) ||
      review.siret !== terms.managerSiret ||
      typeof review.reviewedByUid !== "string" ||
      !review.reviewedByUid.trim() ||
      !review.reviewedAt ||
      !request || request.status !== "approved" ||
      request.uid !== terms.adminUid ||
      requestTerritory.territoireId !== terms.territoireId ||
      structure.siret !== terms.managerSiret ||
      structure.siren !== terms.managerSiret.slice(0, 9) ||
      !admin || admin.uid !== terms.adminUid ||
      String(admin.role).toUpperCase() !== "ADMIN" ||
      admin.accessStatus !== "approved" ||
      admin.territoireId !== terms.territoireId) {
    throw error("INITIAL_SUPERADMIN_REVIEW_NOT_PROVEN");
  }
}

function verifiedInstitutionalCommitment(evidence, prepared) {
  if (!evidence || evidence.status !== "verified" ||
      !CONTRACT_TYPES.has(evidence.documentType) ||
      evidence.signerAuthorityVerified !== true ||
      evidence.buyerSiret !== prepared.locked.buyerSiret ||
      evidence.orderReference !== prepared.reference ||
      evidence.orderFingerprint !== prepared.fingerprint ||
      typeof evidence.documentHash !== "string" ||
      !/^[a-f0-9]{64}$/.test(evidence.documentHash) ||
      !evidence.verifiedAt ||
      !(["institutional_registry", "superadmin_exceptional_review"].includes(
          evidence.verificationSource) ||
        (evidence.verificationSource === "test_fixture_simulation" &&
          evidence.testOnly === true))) {
    throw error("PUBLIC_CONTRACT_NOT_VERIFIED");
  }
  return {
    status: "verified",
    orderReference: evidence.orderReference,
    orderFingerprint: evidence.orderFingerprint,
    documentHash: evidence.documentHash,
    verifiedAt: evidence.verifiedAt,
    verificationSource: evidence.verificationSource,
  };
}

function stationIdsEqual(a, b) {
  return Array.isArray(a) && a.length === b.length &&
      a.every((id, i) => id === b[i]);
}

function createAdminTestFirestoreSync({db, checkoutClient} = {}) {
  assertAdminTestCloud(db);
  if (!checkoutClient || typeof checkoutClient.status !== "function" ||
      typeof checkoutClient.verifiedStripePayment !== "function") {
    throw error("ODOO_CLIENT_NOT_VERIFIED");
  }

  async function activate({prepared, activatedAt} = {}) {
    assertAdminTestCloud(db);
    if (!prepared || prepared.testOnly !== true ||
        !/^SPHOT-ADM-TEST-[A-F0-9]{16}$/.test(prepared.reference) ||
        !(activatedAt instanceof Date) || !Number.isFinite(activatedAt.getTime())) {
      throw error("PREPARED_ADMIN_TEST_REQUIRED");
    }

    // Première barrière : la commande est relue ET validée par l'adaptateur
    // Odoo. Il ne suffit jamais d'envoyer un statut ou une preuve du client.
    const verifiedOdooStatus = await checkoutClient.status(prepared);
    if (!verifiedOdooStatus || verifiedOdooStatus.order?.state !== "sale") {
      throw error("ODOO_ORDER_NOT_CONFIRMED");
    }
    const payment = prepared.paymentMethod === "card" ?
      await checkoutClient.verifiedStripePayment(prepared) : null;

    const uid = prepared.locked.adminUid;
    const cycleRef = db.collection("adminOdooCycles").doc(prepared.reference);
    const subRef = db.collection("subscriptions").doc(uid);
    const adminRef = db.collection("admins").doc(uid);
    const requestRef = db.collection("adminRequests").doc(uid);
    const reviewRef = db.collection(APPROVAL_COLLECTION).doc(uid);
    const commitmentRef = db.collection(COMMITMENT_COLLECTION)
        .doc(prepared.reference);

    // Les preuves administratives et contractuelles sont relues DANS la
    // transaction de projection afin d'éviter les décisions obsolètes.
    return db.runTransaction(async (tx) => {
      const [cycleSnap, subSnap, adminSnap, requestSnap, reviewSnap,
        commitmentSnap] = await Promise.all([
        tx.get(cycleRef), tx.get(subRef), tx.get(adminRef),
        tx.get(requestRef), tx.get(reviewRef),
        prepared.paymentMethod === "public_invoice" ?
          tx.get(commitmentRef) : Promise.resolve(null),
      ]);
      assertInitialSuperAdminReview(read(reviewSnap), read(requestSnap),
          read(adminSnap), prepared);

      const commitment = prepared.paymentMethod === "public_invoice" ?
        verifiedInstitutionalCommitment(read(commitmentSnap), prepared) : null;
      const projection = buildAdminActivationProjection({prepared,
        verifiedOdooStatus, payment, commitment, activatedAt});
      const existingCycle = read(cycleSnap);
      const subscription = read(subSnap);
      const selected = prepared.locked.stationIds;
      const selectedFromSubscription = Array.isArray(
          subscription?.selectedRescueStationIds) ?
        [...subscription.selectedRescueStationIds].sort() : [];
      if (!subscription || subscription.adminUid !== uid ||
          !stationIdsEqual(selectedFromSubscription, selected)) {
        throw error("SUBSCRIPTION_SELECTION_CHANGED");
      }

      if (existingCycle) {
        if (existingCycle.testOnly !== true ||
            existingCycle.source !== "odoo_admin_v1" ||
            existingCycle.adminUid !== uid ||
            existingCycle.orderReference !== prepared.reference ||
            existingCycle.orderFingerprint !== prepared.fingerprint ||
            existingCycle.odooOrderId !== verifiedOdooStatus.order.id ||
            existingCycle.activationBasis !== projection.cycle.activationBasis ||
            subscription.odooAdminCycleRef !== prepared.reference ||
            subscription.status !== "active") {
          throw error("EXISTING_CYCLE_DIFFERENT");
        }
        return {testOnly: true, action: "none", reason: "already_recorded"};
      }
      if ((subscription.status === "active" &&
          subscription.odooAdminCycleRef !== prepared.reference) ||
          (subscription.odooAdminCycleRef &&
            subscription.odooAdminCycleRef !== prepared.reference) ||
          !["trial", "awaiting_subscription", "awaiting_renewal",
            "overdue"].includes(subscription.status)) {
        throw error("OTHER_ACTIVE_CYCLE_PRESENT");
      }

      tx.create(cycleRef, projection.cycle);
      tx.set(subRef, projection.subscriptionPatch, {merge: true});
      tx.set(adminRef, {diffusionAccessGranted: true,
        odooAdminCycleRef: prepared.reference}, {merge: true});
      tx.set(requestRef, {accessPhase: "subscription_active",
        "commercialTracking.status": "subscription_active",
        "commercialTracking.odooAdminCycleRef": prepared.reference},
      {merge: true});
      return {testOnly: true, action: "activate",
        reference: prepared.reference,
        basis: projection.cycle.activationBasis};
    });
  }

  return {activate};
}

module.exports = {assertAdminTestCloud, assertInitialSuperAdminReview,
  verifiedInstitutionalCommitment, createAdminTestFirestoreSync};
