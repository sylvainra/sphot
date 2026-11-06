/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Première décision du Super Admin SPHOT. Elle ne lance NI essai,
// NI facture, NI paiement, NI activation Odoo/Firestore commerciale.
const crypto = require("node:crypto");

const ENDPOINT_NAME = "approveAdminInitialRequest";
const REVIEW_COLLECTION = "adminOdooReviewEvidence";
const UID = /^[A-Za-z0-9_-]{8,128}$/;
const SIREN = /^\d{9}$/;
const SIRET = /^\d{14}$/;
const APPROVED_SOURCE = "server_review_archive";

function failure(status, reason) {
  const error = new Error(reason);
  error.httpStatus = status;
  return error;
}

function string(value) {
  return typeof value === "string" ? value.trim() : "";
}

function uniqueNonEmpty(...values) {
  const items = values.map(string).filter(Boolean);
  if (!items.length || new Set(items).size !== 1) {
    throw failure(422, "IDENTITE_ADMIN_INCOHERENTE");
  }
  return items[0];
}

function assertReviewer(token, nowMs = Date.now()) {
  if (!token || token.role !== "SPHOT_SUPER_ADMIN" ||
      token.sphotSuperAdmin !== true ||
      !/^sphot-super-admin-[a-f0-9]{32}$/.test(string(token.uid)) ||
      !Number.isSafeInteger(token.sphotSaSessionExpiresAt) ||
      token.sphotSaSessionExpiresAt <= nowMs ||
      token.sphotSaSessionExpiresAt > nowMs + 2 * 60 * 60 * 1000) {
    throw failure(403, "SUPERADMIN_SESSION_NOT_VERIFIED");
  }
  return token.uid;
}

function reviewTerms(requestId, request) {
  if (!UID.test(string(requestId)) ||
      !request || request.status !== "pending" ||
      (request.uid && request.uid !== requestId)) {
    throw failure(422, "ADMIN_INITIAL_APPROVAL_NOT_READY");
  }
  const structure = request.structure || {};
  const proConnect = request.proConnect || {};
  const territory = request.territoire || {};
  const siren = uniqueNonEmpty(structure.siren, proConnect.siren);
  const siret = uniqueNonEmpty(structure.siret, proConnect.siret);
  const territoryId = uniqueNonEmpty(territory.territoireId,
      request.territoireId);
  if (!SIREN.test(siren) || !SIRET.test(siret) ||
      siret.slice(0, 9) !== siren ||
      !UID.test(territoryId)) {
    throw failure(422, "ADMIN_SIREN_SIRET_TERRITORY_INVALID");
  }
  const locality = {
    pays: string(territory.pays), region: string(territory.region),
    departement: string(territory.departement),
    ville: string(territory.ville),
  };
  if (!["france", "fr"].includes(locality.pays.toLowerCase()) ||
      !locality.region || !locality.departement || !locality.ville) {
    throw failure(422, "ADMIN_LOCALITY_INCOMPLETE");
  }
  const profile = request.profile || {};
  const email = string(profile.email || proConnect.email).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw failure(422, "ADMIN_EMAIL_INVALID");
  }
  const organisation = string(structure.nom || proConnect.organisation);
  if (!organisation) throw failure(422, "ADMIN_ORGANISATION_MISSING");
  // Conserver les informations du territoire déjà utilisées par le portail
  // (carte, logo, contacts), sans accepter d'autres champs non contrôlés.
  const territoryDetails = {};
  for (const key of ["adresse", "codePostal", "logoVille", "logoStoragePath",
    "logoFileName", "logoMimeType", "logoFileSizeBytes", "siteInternetVille",
    "arretesMunicipaux", "villeLat", "villeLng"]) {
    if (territory[key] !== undefined && territory[key] !== null) {
      territoryDetails[key] = territory[key];
    }
  }
  return {adminUid: requestId, territoryId, siren, siret, locality, email,
    organisation, territoryDetails,
    institutionnels: Array.isArray(request.institutionnels) ?
      request.institutionnels :
      (Array.isArray(territory.institutionnels) ? territory.institutionnels : []),
    facturation: request.facturation || {},
    sourceHash: crypto.createHash("sha256").update(JSON.stringify({
      requestId, territoryId, siren, siret, locality,
    })).digest("hex"),
  };
}

function compatibleTerritory(existing, terms) {
  if (!existing) return true;
  if (existing.territoireId && existing.territoireId !== terms.territoryId) {
    return false;
  }
  const fields = ["pays", "region", "departement", "ville"];
  return fields.every((key) => !existing[key] ||
    string(existing[key]) === terms.locality[key]);
}

async function approveInitialRequest({db, fieldValue, requestId, token,
  nowMs = Date.now()} = {}) {
  const reviewerUid = assertReviewer(token, nowMs);
  if (!db || !fieldValue ||
      typeof fieldValue.serverTimestamp !== "function" ||
      !UID.test(string(requestId))) {
    throw failure(400, "ADMIN_APPROVAL_INPUT_INVALID");
  }
  const requestRef = db.collection("adminRequests").doc(requestId);
  const adminRef = db.collection("admins").doc(requestId);
  const subscriptionRef = db.collection("subscriptions").doc(requestId);
  const evidenceRef = db.collection(REVIEW_COLLECTION).doc(requestId);

  return db.runTransaction(async (tx) => {
    const [requestSnap, adminSnap, subSnap, evidenceSnap] = await Promise.all([
      tx.get(requestRef), tx.get(adminRef), tx.get(subscriptionRef),
      tx.get(evidenceRef),
    ]);
    if (!requestSnap.exists) throw failure(404, "ADMIN_REQUEST_NOT_FOUND");
    const request = requestSnap.data() || {};
    if (evidenceSnap.exists) {
      const previous = evidenceSnap.data() || {};
      if (request.status === "approved" &&
          previous.source === APPROVED_SOURCE &&
          previous.status === "approved" &&
          previous.verifiedSuperAdminReview === true &&
          previous.reviewedByUid === reviewerUid &&
          previous.adminUid === requestId) {
        return {action: "none", reason: "already_archived", adminUid: requestId};
      }
      throw failure(409, "ADMIN_APPROVAL_ARCHIVE_CONFLICT");
    }
    const terms = reviewTerms(requestId, request);
    const territoryRef = db.collection("territoires").doc(terms.territoryId);
    const territorySnap = await tx.get(territoryRef);
    if (!compatibleTerritory(territorySnap.exists ? territorySnap.data() : null,
        terms)) {
      throw failure(409, "ADMIN_TERRITORY_CONFLICT");
    }
    const existingAdmin = adminSnap.exists ? adminSnap.data() || {} : {};
    if (adminSnap.exists &&
        ((existingAdmin.uid && existingAdmin.uid !== requestId) ||
          (existingAdmin.role &&
            string(existingAdmin.role).toUpperCase() !== "ADMIN") ||
          (existingAdmin.territoireId &&
            existingAdmin.territoireId !== terms.territoryId) ||
          (existingAdmin.siren && existingAdmin.siren !== terms.siren) ||
          (existingAdmin.siret && existingAdmin.siret !== terms.siret) ||
          !["pending", "rejected", undefined].includes(
              existingAdmin.accessStatus))) {
      throw failure(409, "ADMIN_ALREADY_GRANTED");
    }
    const existingSubscription = subSnap.exists ? subSnap.data() || {} : {};
    if (subSnap.exists &&
        ((existingSubscription.adminUid &&
          existingSubscription.adminUid !== requestId) ||
        !["pending", "awaiting_configuration", undefined].includes(
            existingSubscription.status) ||
        existingSubscription.trialStartDate ||
        existingSubscription.trialEndDate ||
        existingSubscription.subscriptionStartDate ||
        existingSubscription.subscriptionEndDate ||
        existingSubscription.lastPaymentDate)) {
      throw failure(409, "ADMIN_SUBSCRIPTION_ALREADY_RUNNING");
    }

    const at = fieldValue.serverTimestamp();
    tx.update(requestRef, {
      "uid": requestId, "status": "approved",
      "accessPhase": "configuration_access",
      "approvedAt": at, "updatedAt": at,
      "administrativeTracking.status": "approved",
      "administrativeTracking.approvedAt": at,
      "commercialTracking.status": "configuration_access_opened",
      "commercialTracking.configurationAccessOpenedAt": at,
      "setupProgress.accessGranted": true,
      "setupProgress.updatedAt": at,
      "approvalEmail": {status: "pending", recipient: terms.email,
        sentAt: null, messageId: null, error: null, updatedAt: at},
      "lastEvent": {type: "admin_request_approved",
        category: "administrative", label: "Demande administrateur approuvée",
        createdAt: at, createdByRole: "super_admin"},
    });
    tx.set(adminRef, {uid: requestId, email: terms.email,
      organisation: terms.organisation,
      siret: terms.siret, siren: terms.siren,
      territoireId: terms.territoryId,
      ...terms.locality, institutionnels: terms.institutionnels,
      role: "admin", accessStatus: "approved",
      configurationAccessGranted: true,
      configurationAccessOpenedAt: at, updatedAt: at,
      ...(adminSnap.exists ? {} : {createdAt: at})}, {merge: true});
    const billing = terms.facturation;
    tx.set(subscriptionRef, {
      adminUid: requestId, organisationId: requestId,
      billingOrganisation: string(billing.billingOrganisation || terms.organisation),
      billingSiret: string(billing.billingSiret || terms.siret),
      billingAddress: string(billing.billingAddress),
      billingPostalCode: string(billing.billingPostalCode),
      billingCity: string(billing.billingCity || terms.locality.ville),
      billingContactName: string(billing.billingContactName),
      billingContactEmail: string(billing.billingContactEmail || terms.email),
      purchaseOrderNumber: string(billing.purchaseOrderNumber),
      engagementNumber: string(billing.engagementNumber),
      chorusServiceCode: string(billing.chorusServiceCode),
      numberOfRescueStations: 0,
      trialDurationDays: 8,
      billingCycle: "annual", status: "awaiting_configuration",
      trialReadyAt: null,
      country: terms.locality.pays, region: terms.locality.region,
      department: terms.locality.departement, city: terms.locality.ville,
      updatedAt: at, ...(subSnap.exists ? {} : {createdAt: at,
        trialStartDate: null, trialEndDate: null,
        subscriptionStartDate: null, subscriptionEndDate: null,
        lastPaymentDate: null, nextInvoiceDate: null})}, {merge: true});
    tx.set(territoryRef, {territoireId: terms.territoryId,
      ...terms.locality, ...terms.territoryDetails,
      institutionnels: terms.institutionnels,
      updatedAt: at}, {merge: true});
    tx.create(evidenceRef, {source: APPROVED_SOURCE,
      status: "approved", verifiedSuperAdminReview: true,
      adminUid: requestId, requestDocumentId: requestId,
      territoireId: terms.territoryId, siren: terms.siren,
      siret: terms.siret, locality: terms.locality,
      // Champs de compatibilité avec les précontrôles d'essai et Odoo.
      // Les vérifications de cohérence sont désormais faites par le serveur,
      // et non attestées au moyen de cases cochées dans le navigateur.
      superAdminChecks: {locality: true, siren: true, siret: true},
      serverConsistencyChecks: {locality: true, siren: true, siret: true},
      verificationMethod: "server_consistency_and_superadmin_decision",
      reviewedByUid: reviewerUid, reviewedAt: at,
      requestFingerprint: terms.sourceHash,
      decisionVersion: "sphot_initial_admin_approval_v1"});
    return {action: "approved", adminUid: requestId};
  });
}

const ORIGINS = new Set(["https://sphot.app", "https://www.sphot.app",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com"]);

function endpoint({admin, onRequest}) {
  return onRequest({region: "us-central1", cpu: 1, memory: "256MiB"},
      async (req, res) => {
        const origin = string(req.headers.origin);
        if (ORIGINS.has(origin) ||
            /^http:\/\/(localhost|127\.0\.0\.1):\d{2,5}$/.test(origin)) {
          res.set("Access-Control-Allow-Origin", origin);
          res.set("Vary", "Origin");
        }
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
        res.set("Cache-Control", "no-store");
        if (req.method === "OPTIONS") {
          res.status(204).send("");
          return;
        }
        if (req.method !== "POST") {
          res.status(405).json({success: false, error: "METHOD_NOT_ALLOWED"});
          return;
        }
        try {
          const header = string(req.headers.authorization);
          if (!header.startsWith("Bearer ")) {
            throw failure(401, "MISSING_SUPERADMIN_ID_TOKEN");
          }
          const decoded = await admin.auth().verifyIdToken(header.slice(7), true);
          const result = await approveInitialRequest({db: admin.firestore(),
            fieldValue: admin.firestore.FieldValue,
            requestId: req.body?.requestId, token: decoded});
          res.status(200).json({success: true, ...result});
        } catch (err) {
          const status = err.httpStatus || 403;
          res.status(status).json({success: false,
            error: err.httpStatus ? err.message : "ADMIN_APPROVAL_REFUSED"});
        }
      });
}

module.exports = {ENDPOINT_NAME, assertReviewer, reviewTerms,
  approveInitialRequest, endpoint};
