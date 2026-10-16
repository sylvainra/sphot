/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const crypto = require("node:crypto");

// Lecture interne, strictement READ-ONLY, du PDF d'un devis déjà émis.
//
// Ce module n'est pas un endpoint HTTP : aucune route, aucun bouton,
// aucune émission officielle ou URL publique n'est créée à cette étape.
// Une future route devra effectuer la même vérification d'identité,
// limiter sa réponse au propriétaire et désactiver la mise en cache.
async function readArchivedAdminQuotePdf({auth, db, bucket, idToken,
  documentId} = {}) {
  const validId = (v) => typeof v === "string" &&
      /^[A-Za-z0-9_-]{1,220}$/.test(v);
  const reject = () => {
    const error = new Error("Accès au PDF du devis refusé.");
    error.code = "QUOTE_DOCUMENT_ACCESS_DENIED";
    return error;
  };
  if (!auth || typeof auth.verifyIdToken !== "function" ||
      !db || typeof db.collection !== "function" ||
      !bucket || typeof bucket.file !== "function" ||
      typeof idToken !== "string" || !idToken.trim() ||
      !validId(documentId)) {
    throw reject();
  }

  let session;
  try {
    session = await auth.verifyIdToken(idToken, true);
  } catch (_) {
    throw reject();
  }
  const uid = session && session.uid;
  const territory = session && session.territoireId;
  if (!validId(uid) || !validId(territory) ||
      session.adminUid !== uid ||
      String(session.role || "").toUpperCase() !== "ADMIN") {
    throw reject();
  }

  // adminAccounts est réservé au serveur : un simple admins/{uid}
  // est insuffisant, car la collection reste modifiable côté clients.
  const accounts = await db.collection("adminAccounts")
      .where("adminUid", "==", uid).limit(10).get();
  if (!accounts || !Array.isArray(accounts.docs) ||
      accounts.docs.length >= 10) {
    throw reject();
  }
  const verifiedAccounts = accounts.docs.filter((doc) => {
    const a = doc.data() || {};
    return a.adminUid === uid &&
        a.accountStatus === "ACTIVE" &&
        String(a.role || "").toUpperCase() === "ADMIN" &&
        a.territoireId === territory;
  });
  if (verifiedAccounts.length !== 1) throw reject();

  // La règle de lecture documents existante autorise uniquement
  // adminUid=request.auth.uid, et le serveur revalide indépendamment.
  const docSnap = await db.collection("documents").doc(documentId).get();
  if (!docSnap || !docSnap.exists) throw reject();
  const registry = docSnap.data() || {};
  const number = registry.documentNumber;
  const sha = registry.sha256;
  if (!/^DV-\d{4}-\d{6}-\d{3,}$/.test(number || "") ||
      !/^[a-f0-9]{64}$/.test(sha || "") ||
      registry.documentType !== "quote" ||
      registry.status !== "issued" ||
      registry.adminUid !== uid ||
      registry.requestId !== uid ||
      registry.documentNumber !== registry.quoteNumber ||
      registry.requestId + "_" + number !== documentId ||
      !validId(registry.quoteId) ||
      !Number.isSafeInteger(registry.pdfSize) ||
      registry.pdfSize < 1024 || registry.pdfSize > 20 * 1024 * 1024) {
    throw reject();
  }
  const expectedPath = "adminRequests/" + uid +
      "/documents/financier/" + number.slice(3, 7) +
      "/devis/" + number + ".pdf";
  if (registry.storagePath !== expectedPath) throw reject();

  // Le PDF doit être lié à son devis et à son empreinte d'origine.
  const quoteSnap = await db.collection("quotes")
      .doc(registry.quoteId).get();
  const quote = quoteSnap && quoteSnap.exists ?
      quoteSnap.data() || {} : {};
  if (quote.adminUid !== uid || quote.requestId !== uid ||
      quote.documentId !== documentId ||
      quote.quoteNumber !== number ||
      quote.pdfSha256 !== sha ||
      quote.storagePath !== expectedPath ||
      quote.status !== "issued" ||
      quote.pdfArchived !== true) {
    throw reject();
  }

  // Pas de signed URL partageable : lecture des octets depuis Storage.
  const download = await bucket.file(expectedPath).download();
  const bytes = Array.isArray(download) ? download[0] : null;
  if (!Buffer.isBuffer(bytes) ||
      bytes.length !== registry.pdfSize ||
      bytes.subarray(0, 5).toString("ascii") !== "%PDF-" ||
      crypto.createHash("sha256").update(bytes).digest("hex") !== sha) {
    throw reject();
  }
  return {
    documentId,
    quoteNumber: number,
    filename: number + ".pdf",
    mimeType: "application/pdf",
    pdfBuffer: bytes,
  };
}

module.exports = {readArchivedAdminQuotePdf};
