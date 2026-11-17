/* eslint-disable max-len, require-jsdoc, indent, object-curly-spacing, comma-dangle, brace-style */
"use strict";

// Consentement CONTRACTUEL ADMIN phase 2, distinct de la consultation des CGV.
// Requiert une session Firebase ADMIN approuvee. Les traces sont inscrites
// UNIQUEMENT par le serveur dans deux collections protegees par des regles
// Firestore fermant l'ecriture aux clients.
// AUCUNE commande, facture, modification d'abonnement ni paiement ici.
const crypto = require("node:crypto");
const {resolveOdooCheckoutIdentity} = require("./odoo_checkout_identity");

const DOCUMENT_ID = "adminCgv";
const CURRENT = "odooAdminCgvAcceptanceEvidence";
const HISTORY = "odooAdminCgvAcceptanceHistory";
const ORIGINS = new Set([
  "https://sphot.app", "https://www.sphot.app",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com",
]);
const VALID_ID = /^[A-Za-z0-9_-]{8,128}$/;

function refuse(status, message) {
  const e = new Error(message);
  e.httpStatus = status;
  return e;
}
function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}
function validRevision(value) {
  return Number.isSafeInteger(value) && value >= 0;
}
function historicalId(uid, version, revision) {
  const digest = crypto.createHash("sha256")
      .update(`${DOCUMENT_ID}|${uid}|${version}|${revision}`)
      .digest("hex").slice(0, 20);
  return `${uid}_${digest}`;
}

async function acceptAdminCgv({admin, authorization, requestId,
  expectedVersion, expectedRevision, accepted} = {}) {
  if (accepted !== true || !VALID_ID.test(clean(requestId)) ||
      !clean(expectedVersion) || !validRevision(expectedRevision)) {
    throw refuse(400, "Confirmation des CGV incomplete.");
  }
  const identity = await resolveOdooCheckoutIdentity({
    admin, authorization, market: "ADMIN", requestId,
  });
  const db = admin.firestore();
  const legalRef = db.collection("legalDocuments").doc(DOCUMENT_ID);
  const subRef = db.collection("subscriptions").doc(identity.uid);
  const currentRef = db.collection(CURRENT).doc(identity.uid);
  const historyRef = db.collection(HISTORY).doc(
      historicalId(identity.uid, expectedVersion, expectedRevision));

  // Le document est publie sous forme de chapitres Firestore.
  // Un document vide n'est jamais acceptable contractuellement.
  const chapterSnap = await legalRef.collection("chapters").limit(1).get();
  if (chapterSnap.empty) {
    throw refuse(409, "CGV ADMIN sans article publie.");
  }
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  return db.runTransaction(async (tx) => {
    const [legalSnap, subSnap, evidenceSnap, historicalSnap] = await Promise.all([
      tx.get(legalRef), tx.get(subRef), tx.get(currentRef), tx.get(historyRef),
    ]);
    const doc = legalSnap.data() || {};
    if (!legalSnap.exists || doc.published === false ||
        doc.testOnly === true || clean(doc.version) !== expectedVersion ||
        !validRevision(doc.revision) || doc.revision !== expectedRevision) {
      throw refuse(409, "Version des CGV modifiee : relisez le document.");
    }
    const subscription = subSnap.data() || {};
    if (!subSnap.exists || subscription.adminUid !== identity.uid) {
      throw refuse(403, "Abonnement ADMIN non associe a cet administrateur.");
    }
    const current = evidenceSnap.data() || {};
    if (evidenceSnap.exists && current.documentId === DOCUMENT_ID &&
        current.adminUid === identity.uid && current.accepted === true &&
        current.version === expectedVersion &&
        current.revision === expectedRevision &&
        current.source === "sphot_admin_cgv_server_acceptance_v1" &&
        current.testOnly === false) {
      return {alreadyAccepted: true, version: expectedVersion,
        revision: expectedRevision};
    }
    if (historicalSnap.exists) {
      throw refuse(409, "Historique juridique incoherent : operation interrompue.");
    }
    const acceptance = {
      adminUid: identity.uid, documentId: DOCUMENT_ID, accepted: true,
      version: expectedVersion, revision: expectedRevision,
      acceptedAt: stamp(), source: "sphot_admin_cgv_server_acceptance_v1",
      testOnly: false,
    };
    // Trace courante lue par le preparateur Odoo. Ne pas l'alimenter
    // depuis le navigateur ni depuis la collection subscriptions modifiable.
    tx.set(currentRef, acceptance);
    tx.create(historyRef, {...acceptance, requestId: identity.requestId,
      evidenceId: historyRef.id});
    // Copie d'affichage seulement : le preparateur Odoo lit CURRENT.
    tx.update(subRef, {commercialCgvAcceptance: acceptance,
      updatedAt: stamp()});
    return {alreadyAccepted: false, version: expectedVersion,
      revision: expectedRevision};
  });
}

async function readAdminCgvAcceptanceStatus({admin, authorization,
  requestId} = {}) {
  const identity = await resolveOdooCheckoutIdentity({
    admin, authorization, market: "ADMIN", requestId,
  });
  const db = admin.firestore();
  const [legalSnap, acceptedSnap] = await Promise.all([
    db.collection("legalDocuments").doc(DOCUMENT_ID).get(),
    db.collection(CURRENT).doc(identity.uid).get(),
  ]);
  const legal = legalSnap.data() || {};
  const saved = acceptedSnap.data() || {};
  const version = clean(legal.version);
  const revision = legal.revision;
  const accepted = legalSnap.exists && legal.published !== false &&
    legal.testOnly !== true && version.length > 0 &&
    validRevision(revision) && acceptedSnap.exists &&
    saved.adminUid === identity.uid && saved.documentId === DOCUMENT_ID &&
    saved.accepted === true && saved.version === version &&
    saved.revision === revision &&
    saved.source === "sphot_admin_cgv_server_acceptance_v1" &&
    saved.testOnly === false;
  return {accepted, version, revision: validRevision(revision) ? revision : null};
}

function registerAdminCgvAcceptance({admin, onRequest}) {
  return onRequest({region: "us-central1", cpu: 1, memory: "256MiB",
    maxInstances: 5}, async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    const origin = req.get?.("Origin") || "";
    if (origin) {
      if (!ORIGINS.has(origin)) {
        res.status(403).json({success: false, error: "Origin refusée."});
        return;
      }
      res.set("Access-Control-Allow-Origin", origin);
      res.set("Vary", "Origin");
      res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
      res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    }
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({success: false, error: "Methode refusee."});
      return;
    }
    const body = req.body;
    const keys = body && typeof body === "object" && !Array.isArray(body) ?
      Object.keys(body).sort().join("|") : "";
    const statusRequest = keys === "action|requestId" &&
      body.action === "status";
    const acceptRequest = keys ===
      ["accepted", "expectedRevision", "expectedVersion", "requestId"]
          .sort().join("|");
    if (!statusRequest && !acceptRequest) {
      res.status(400).json({success: false, error: "Requete invalide."});
      return;
    }
    try {
      const authorization = req.get("Authorization") || "";
      const result = statusRequest ?
        await readAdminCgvAcceptanceStatus({admin, authorization,
          requestId: body.requestId}) :
        await acceptAdminCgv({admin, authorization,
          requestId: body.requestId, expectedVersion: body.expectedVersion,
          expectedRevision: body.expectedRevision, accepted: body.accepted});
      res.status(200).json({success: true, ...result});
    } catch (error) {
      const status = error.httpStatus || 500;
      if (status === 500) console.error("ADMIN CGV acceptance failed", error);
      res.status(status).json({success: false,
        error: status === 500 ?
          "Acceptation indisponible temporairement." : error.message});
    }
  });
}

module.exports = {acceptAdminCgv, readAdminCgvAcceptanceStatus,
  registerAdminCgvAcceptance, historicalId};
