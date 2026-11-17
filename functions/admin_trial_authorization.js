/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// SPHOT ADMIN : seule la décision distincte du Super Admin déclenche l'essai.
// Aucun tarif, facture Odoo, paiement ou renouvellement n'est traité ici.
const crypto = require("node:crypto");
const {assertReviewer} = require("./admin_initial_approval");

const TRIAL_DAYS = 8;
const UID = /^[A-Za-z0-9_-]{8,128}$/;
const REVIEW_SOURCE = "server_review_archive";
const TRIAL_SOURCE = "server_trial_authorization_v1";

function fail(code, httpStatus = 409) {
  const error = new Error(code);
  error.httpStatus = httpStatus;
  return error;
}

function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

async function authorizeTrial({db, fieldValue, requestId, token,
  now = new Date()} = {}) {
  if (!db || !fieldValue || typeof fieldValue.serverTimestamp !== "function" ||
      !UID.test(clean(requestId)) || !(now instanceof Date) ||
      !Number.isFinite(now.getTime())) {
    throw fail("TRIAL_INPUT_INVALID", 400);
  }
  const reviewerUid = assertReviewer(token, now.getTime());

  const requestRef = db.collection("adminRequests").doc(requestId);
  const adminRef = db.collection("admins").doc(requestId);
  const subscriptionRef = db.collection("subscriptions").doc(requestId);
  const reviewRef = db.collection("adminOdooReviewEvidence").doc(requestId);
  const trialRef = db.collection("adminTrialAuthorizations").doc(requestId);

  return db.runTransaction(async (tx) => {
    const [requestSnap, adminSnap, subscriptionSnap, reviewSnap, trialSnap] =
      await Promise.all([tx.get(requestRef), tx.get(adminRef),
        tx.get(subscriptionRef), tx.get(reviewRef), tx.get(trialRef)]);
    if (!requestSnap.exists || !adminSnap.exists ||
        !subscriptionSnap.exists || !reviewSnap.exists) {
      throw fail("TRIAL_ADMIN_RECORDS_MISSING", 404);
    }
    const request = requestSnap.data() || {};
    const administrator = adminSnap.data() || {};
    const subscription = subscriptionSnap.data() || {};
    const review = reviewSnap.data() || {};
    const territory = request.territoire || {};
    const structure = request.structure || {};
    const trialRequest = request.trialRequest || {};
    const acceptedDocuments = trialRequest.acceptedDocuments || {};
    const tracking = request.trialTracking || {};
    const locality = {pays: clean(territory.pays),
      region: clean(territory.region),
      departement: clean(territory.departement),
      ville: clean(territory.ville)};
    const reviewFingerprint = crypto.createHash("sha256")
        .update(JSON.stringify({requestId,
          territoryId: territory.territoireId,
          siren: structure.siren, siret: structure.siret, locality}))
        .digest("hex");
    const trialStatus = clean(request.trialRequestStatus ||
      tracking.status || trialRequest.status).toLowerCase();

    if (trialSnap.exists) {
      const prior = trialSnap.data() || {};
      if (prior.source === TRIAL_SOURCE && prior.requestId === requestId &&
          prior.status === "approved" && subscription.status === "trial" &&
          subscription.trialStartDate && subscription.trialEndDate &&
          !subscription.odooAdminCycleRef) {
        return {action: "none", reason: "trial_already_authorized", requestId};
      }
      throw fail("TRIAL_AUTHORIZATION_CONFLICT");
    }
    if (request.status !== "approved" || request.uid !== requestId ||
        administrator.uid !== requestId ||
        administrator.accessStatus !== "approved" ||
        subscription.adminUid !== requestId ||
        !["awaiting_configuration", "awaiting_trial"].includes(subscription.status) ||
        subscription.trialStartDate || subscription.trialEndDate ||
        subscription.subscriptionStartDate || subscription.subscriptionEndDate ||
        subscription.lastPaymentDate || subscription.odooAdminCycleRef ||
        subscription.odooAdminManaged === true) {
      throw fail("TRIAL_NOT_ELIGIBLE");
    }
    if (review.source !== REVIEW_SOURCE ||
        review.verifiedSuperAdminReview !== true ||
        review.status !== "approved" || review.adminUid !== requestId ||
        !review.reviewedByUid || !review.reviewedAt ||
        review.territoireId !== territory.territoireId ||
        review.territoireId !== administrator.territoireId ||
        review.siren !== structure.siren || review.siret !== structure.siret ||
        review.requestFingerprint !== reviewFingerprint ||
        !review.superAdminChecks ||
        review.superAdminChecks.locality !== true ||
        review.superAdminChecks.siren !== true ||
        review.superAdminChecks.siret !== true) {
      throw fail("TRIAL_INITIAL_REVIEW_NOT_PROVEN");
    }
    if (trialStatus !== "pending" ||
        trialRequest.trialDurationDays !== TRIAL_DAYS ||
        trialRequest.certifyRepresentative !== true ||
        trialRequest.legalReadConfirmed !== true ||
        trialRequest.privacyReadConfirmed !== true ||
        trialRequest.rgpdAccepted !== true ||
        !clean(acceptedDocuments.version) ||
        !acceptedDocuments.acceptedAt ||
        acceptedDocuments.cgu !== true ||
        acceptedDocuments.privacy !== true ||
        acceptedDocuments.rgpd !== true) {
      throw fail("TRIAL_REQUEST_OR_LEGAL_ACCEPTANCE_MISSING");
    }

    const recipient = clean(request.profile?.email || request.proConnect?.email);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipient)) {
      throw fail("TRIAL_CONTACT_MISSING");
    }
    const territoryId = clean(administrator.territoireId);
    if (!territoryId) throw fail("TRIAL_TERRITORY_MISSING");

    const startAt = new Date(now);
    const endAt = new Date(now.getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000);
    const at = fieldValue.serverTimestamp();
    tx.update(requestRef, {
      "trialRequestStatus": "approved", "accessPhase": "trial_active",
      "trialRequest.status": "approved", "trialRequest.approvedAt": at,
      "trialTracking.status": "approved",
      "trialTracking.approvedAt": at,
      "trialTracking.approvedByRole": "super_admin",
      "commercialTracking.status": "trial_active",
      "commercialTracking.trialActivatedAt": at,
      "trialApprovalEmail": {status: "pending", recipient,
        sentAt: null, messageId: null, error: null, updatedAt: at},
      "lastEvent": {type: "trial_approved", category: "commercial",
        label: "Période d’essai SPHOT ADMIN validée",
        createdAt: at, createdByRole: "super_admin"},
      "updatedAt": at,
    });
    tx.set(subscriptionRef, {
      adminUid: requestId, status: "trial", trialDurationDays: TRIAL_DAYS,
      trialStartDate: startAt, trialEndDate: endAt,
      billingCycle: "annual", trialActivatedAt: at, updatedAt: at,
    }, {merge: true});
    tx.set(adminRef, {
      uid: requestId, accessStatus: "approved",
      diffusionAccessGranted: true, diffusionAccessOpenedAt: at,
      updatedAt: at,
    }, {merge: true});
    tx.create(trialRef, {
      source: TRIAL_SOURCE, status: "approved",
      requestId, adminUid: requestId, territoireId: territoryId,
      authorizedByUid: reviewerUid, authorizedAt: at,
      startsAt: startAt, endsAt: endAt,
      durationDays: TRIAL_DAYS,
      initialReviewSource: REVIEW_SOURCE,
    });
    return {action: "started", requestId, durationDays: TRIAL_DAYS,
      endsAt: endAt.toISOString()};
  });
}

const ORIGINS = new Set(["https://sphot.app", "https://www.sphot.app",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com"]);

function endpoint({admin, onRequest}) {
  return onRequest({region: "us-central1", cpu: 1, memory: "256MiB"},
      async (req, res) => {
        const origin = clean(req.headers.origin);
        if (ORIGINS.has(origin) ||
            /^http:\/\/(localhost|127\.0\.0\.1):\d{2,5}$/.test(origin)) {
          res.set("Access-Control-Allow-Origin", origin);
          res.set("Vary", "Origin");
        }
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
        res.set("Cache-Control", "no-store");
        if (req.method === "OPTIONS") return res.status(204).send("");
        if (req.method !== "POST") {
          return res.status(405).json({success: false, error: "METHOD_NOT_ALLOWED"});
        }
        try {
          const header = clean(req.headers.authorization);
          if (!header.startsWith("Bearer ")) {
            throw fail("MISSING_SUPERADMIN_TOKEN", 401);
          }
          const token = await admin.auth().verifyIdToken(header.slice(7), true);
          const result = await authorizeTrial({db: admin.firestore(),
            fieldValue: admin.firestore.FieldValue,
            requestId: req.body?.requestId, token});
          return res.status(200).json({success: true, ...result});
        } catch (error) {
          return res.status(error.httpStatus || 403).json({success: false,
            error: error.httpStatus ? error.message : "TRIAL_REFUSED"});
        }
      });
}

module.exports = {TRIAL_DAYS, TRIAL_SOURCE, authorizeTrial, endpoint};
