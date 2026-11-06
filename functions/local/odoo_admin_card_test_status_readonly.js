/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Contrôle en lecture seule du cycle carte FICTIF déjà payé et activé.
// Il ne crée ni commande, ni facture, ni paiement, ni droit Firestore.
const {runCardCycle, buildCardFixture} =
  require("./odoo_admin_card_test_cycle");
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");
const {CHECKOUT_TEST_DATABASE} = require("./odoo_secure_checkout_client");
const {assertDestination} = require("./odoo_admin_test_fixture_invoice");

function refused(reason) {
  const error = new Error("ADMIN_CARD_STATUS_" + reason);
  error.code = "ADMIN_CARD_STATUS_REFUSED";
  return error;
}

function data(snapshot) {
  return snapshot && snapshot.exists ? snapshot.data() || {} : null;
}

async function readCardTestStatus({db, odooClient, database =
  CHECKOUT_TEST_DATABASE, checkoutFactory} = {}) {
  assertDestination(db, database);
  const prepared = buildCardFixture();
  const status = await runCardCycle({db, odooClient, database,
    mode: "preflight", ...(checkoutFactory ? {checkoutFactory} : {})});
  if (status.testOnly !== true || status.action !== "none" ||
      status.reference !== prepared.reference) {
    throw refused("ODOO_READ_CONTRACT_INVALID");
  }

  const uid = prepared.locked.adminUid;
  const [cycleSnap, subSnap, adminSnap, requestSnap] = await Promise.all([
    db.collection("adminOdooCycles").doc(prepared.reference).get(),
    db.collection("subscriptions").doc(uid).get(),
    db.collection("admins").doc(uid).get(),
    db.collection("adminRequests").doc(uid).get(),
  ]);
  const cycle = data(cycleSnap);
  const subscription = data(subSnap);
  const admin = data(adminSnap);
  const request = data(requestSnap);
  const active = Boolean(cycle);
  // Les premiers cycles C4 TEST ont été écrits par set(..., {merge:true})
  // avec une clé littérale contenant un point. Préserver ce format existant
  // sans jamais accepter deux références contradictoires.
  const trackingRefs = [request?.commercialTracking?.odooAdminCycleRef,
    request?.["commercialTracking.odooAdminCycleRef"]]
      .filter((value) => value !== undefined);
  const trackingVerified = trackingRefs.length > 0 &&
    trackingRefs.every((value) => value === prepared.reference);
  if (active) {
    if (status.paymentStatus !== "paid" ||
        status.stripeVerified !== true ||
        cycle.testOnly !== true || cycle.source !== "odoo_admin_v1" ||
        cycle.orderReference !== prepared.reference ||
        cycle.orderFingerprint !== prepared.fingerprint ||
        cycle.adminUid !== uid || cycle.paymentMethod !== "card" ||
        cycle.paymentStatus !== "paid" ||
        cycle.activationBasis !== "stripe_verified" ||
        !Array.isArray(cycle.selectedRescueStationIds) ||
        JSON.stringify([...cycle.selectedRescueStationIds].sort()) !==
          JSON.stringify(prepared.locked.stationIds) ||
        subscription?.status !== "active" ||
        subscription?.odooAdminManaged !== true ||
        subscription?.odooAdminCycleRef !== prepared.reference ||
        subscription?.odooPaymentStatus !== "paid" ||
        admin?.diffusionAccessGranted !== true ||
        admin?.odooAdminCycleRef !== prepared.reference ||
        request?.accessPhase !== "subscription_active" ||
        !trackingVerified) {
      throw refused("ACTIVATION_EVIDENCE_INCONSISTENT");
    }
  } else if (subscription?.status === "active" ||
      subscription?.odooAdminCycleRef ||
      admin?.diffusionAccessGranted === true ||
      request?.accessPhase === "subscription_active") {
    throw refused("RIGHTS_WITHOUT_CYCLE");
  }

  return {testOnly: true, fixtureOnly: true, action: "none",
    reference: prepared.reference,
    stationCount: prepared.locked.stationIds.length,
    expectedHtCents: prepared.expectedUntaxedCents,
    expectedTtcCents: prepared.expectedTotalCents,
    paymentStatus: status.paymentStatus || "not_started",
    stripeVerified: status.stripeVerified === true,
    activationVerified: active,
    activationBasis: active ? "stripe_verified" : null,
    nextGate: active ? "TEST_CYCLE_COMPLETE" : status.nextGate,
    firestoreProject: TEST_PROJECT_ID,
    odooDatabase: CHECKOUT_TEST_DATABASE,
    prodFirestoreWritten: false, odooWritten: false,
    activationAttempted: false};
}

module.exports = {readCardTestStatus};
