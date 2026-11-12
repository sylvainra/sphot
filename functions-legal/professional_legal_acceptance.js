"use strict";

// Un seul point serveur pour les acceptations récurrentes ADMIN/PUBLICITAIRE.
// Le Super Admin publie les CGU via legal_document_editor.js ; ce module
// compare toujours les versions courantes dans Firestore à chaque accès.
const ORIGINS = [
  "https://sphot.app", "https://www.sphot.app",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com",
  "http://localhost:5081", "http://127.0.0.1:5081",
];
const PROFILES = Object.freeze({
  ADMIN: {documentId: "adminCgu", count: 14, claim: "adminUid"},
  ANNONCEUR: {documentId: "advertiserCgu", count: 12,
    claim: "advertiserRequestId"},
});

function fail(status, message) {
  const error = new Error(message);
  error.httpStatus = status;
  return error;
}
function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}
function activeProfile(token) {
  const role = clean(token?.role).toUpperCase();
  const profile = PROFILES[role];
  if (!profile || !clean(token?.uid) ||
      !clean(token?.[profile.claim]) ||
      (role === "ADMIN" &&
        token.uid !== clean(token?.adminUid))) {
    throw fail(403, "PROFIL_PROFESSIONNEL_NON_AUTORISE");
  }
  return {role, ...profile, uid: token.uid};
}
function legalVersion(document, profile) {
  if (!document || document.published !== true ||
      document.testOnly === true ||
      !Array.isArray(document.chapters) ||
      document.chapters.length !== profile.count) return null;
  const version = clean(document.version);
  const revision = document.revision;
  if (!version || !Number.isSafeInteger(revision) || revision < 0) {
    return null;
  }
  return `${version}:r${revision}`;
}
function requiresAcceptance(current, acceptance) {
  return !acceptance || acceptance.accepted !== true ||
      acceptance.documentId !== current.documentId ||
      acceptance.versionId !== current.versionId;
}
function validateInput(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw fail(400, "REQUETE_INVALIDE");
  }
  const fields = input.action === "status" ? ["action"] :
    input.action === "accept" ? ["action", "versionId", "accepted"] : null;
  if (!fields || Object.keys(input).sort().join(",") !==
      fields.sort().join(",") ||
      (input.action === "accept" &&
      (clean(input.versionId) !== input.versionId ||
        !input.versionId || input.accepted !== true))) {
    throw fail(400, "ACTION_OU_CHAMPS_INTERDITS");
  }
  return input;
}

async function action({admin, token, input}) {
  const actor = activeProfile(token);
  const request = validateInput(input);
  const db = admin.firestore();
  const legalRef = db.collection("legalDocuments").doc(actor.documentId);
  const acceptanceRef = db.collection("professionalLegalAcceptances")
      .doc(`${actor.role}_${actor.uid}`);

  if (request.action === "status") {
    const [legal, recorded] = await Promise.all([
      legalRef.get(), acceptanceRef.get(),
    ]);
    const versionId = legalVersion(legal.data(), actor);
    if (!versionId) return {published: false, required: false,
      documentId: actor.documentId};
    const current = {documentId: actor.documentId, versionId};
    return {published: true, required:
      requiresAcceptance(current, recorded.data()),
    documentId: actor.documentId, versionId};
  }

  return db.runTransaction(async (tx) => {
    const [legal, recorded] = await Promise.all([
      tx.get(legalRef), tx.get(acceptanceRef),
    ]);
    const versionId = legalVersion(legal.data(), actor);
    if (!versionId) throw fail(409, "DOCUMENT_JURIDIQUE_NON_PUBLIE");
    if (versionId !== request.versionId) {
      throw fail(409, "DOCUMENT_JURIDIQUE_MODIFIE_RECHARGEZ");
    }
    const current = {documentId: actor.documentId, versionId};
    if (!requiresAcceptance(current, recorded.data())) {
      return {accepted: true, versionId, alreadyAccepted: true};
    }
    const stamp = admin.firestore.FieldValue.serverTimestamp();
    const details = {
      actorUid: actor.uid, actorRole: actor.role,
      documentId: actor.documentId, versionId,
      accepted: true, acceptedAt: stamp,
      source: "sphot_professional_legal_gate",
    };
    const historyRef = acceptanceRef.collection("history").doc();
    tx.create(historyRef, details);
    tx.set(acceptanceRef, details, {merge: true});
    return {accepted: true, versionId, alreadyAccepted: false};
  });
}

function register({admin, onRequest}) {
  return onRequest({region: "us-central1", cors: ORIGINS,
    cpu: 1, memory: "256MiB", maxInstances: 3}, async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    if (req.method !== "POST") return res.status(405).json({success: false});
    try {
      const authorization = clean(req.get("Authorization"));
      if (!authorization.startsWith("Bearer ")) {
        throw fail(401, "SESSION_FIREBASE_REQUISE");
      }
      const token = await admin.auth().verifyIdToken(
          authorization.slice(7), true);
      const result = await action({admin, token, input: req.body});
      return res.status(200).json({success: true, ...result});
    } catch (error) {
      if (!error.httpStatus) {
        console.error("Professional legal gate:", error);
      }
      return res.status(error.httpStatus || 500).json({
        success: false,
        error: error.httpStatus ? error.message : "ERREUR_SERVEUR",
      });
    }
  });
}
module.exports = {PROFILES, activeProfile, legalVersion,
  requiresAcceptance, validateInput, action, register};
