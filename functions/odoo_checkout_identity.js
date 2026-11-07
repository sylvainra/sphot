"use strict";

// Autorisation serveur pour les futurs points d'entrée de facturation Odoo.
// L'identité, le dossier et les droits sont lus depuis Firebase, jamais depuis
// les champs de tarif, de rôle ou de territoire fournis par le navigateur.
const ID = /^[A-Za-z0-9_-]{8,128}$/;

function rejected(status, message) {
  const error = new Error(message);
  error.httpStatus = status;
  return error;
}

function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

async function resolveOdooCheckoutIdentity({admin, authorization,
  market, requestId} = {}) {
  if (!admin || !admin.auth || !admin.firestore ||
      !["ADMIN", "ADVERTISER"].includes(market) ||
      !ID.test(clean(requestId))) {
    throw rejected(400, "Dossier de facturation invalide.");
  }
  if (typeof authorization !== "string" ||
      !authorization.startsWith("Bearer ")) {
    throw rejected(401, "Connexion professionnelle requise.");
  }

  let claims;
  try {
    claims = await admin.auth().verifyIdToken(
        authorization.slice(7).trim(), true);
  } catch (_) {
    throw rejected(401, "Session professionnelle expirée.");
  }

  const uid = clean(claims?.uid);
  if (!uid) throw rejected(401, "Identité professionnelle absente.");
  const db = admin.firestore();

  if (market === "ADVERTISER") {
    if (clean(claims.role).toUpperCase() !== "ANNONCEUR" ||
        claims.advertiserRequestId !== requestId) {
      throw rejected(403, "Dossier annonceur non autorisé.");
    }
    const doc = await db.collection("advertiserRequests").doc(requestId).get();
    const data = doc.data() || {};
    if (!doc.exists || data.status !== "approved" ||
        (data.firebaseUid && data.firebaseUid !== uid)) {
      throw rejected(403, "Dossier annonceur non approuvé.");
    }
    return Object.freeze({uid, requestId, market, claims, dossier: data});
  }

  if (clean(claims.role).toUpperCase() !== "ADMIN" ||
      claims.uid !== claims.adminUid ||
      claims.adminUid !== requestId || !clean(claims.territoireId)) {
    throw rejected(403, "Administrateur SPHOT non autorisé.");
  }
  const doc = await db.collection("admins").doc(requestId).get();
  const data = doc.data() || {};
  if (!doc.exists || data.accessStatus !== "approved" ||
      data.territoireId !== claims.territoireId ||
      (data.uid && data.uid !== uid)) {
    throw rejected(403, "Droits administrateur non approuvés.");
  }
  return Object.freeze({uid, requestId, market, claims, dossier: data});
}

module.exports = {resolveOdooCheckoutIdentity};
