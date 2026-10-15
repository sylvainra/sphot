/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const crypto = require("node:crypto");

// Archivage de DEVIS DÉJÀ ÉMIS par un service serveur de confiance.
// NE NUMÉROTE PAS de devis, NE CRÉE PAS de document dans 'quotes',
// N'ENVOIE PAS d'email et n'est PAS exposé comme endpoint.
// La route d'émission devra vérifier Firebase Auth, droits, grille et taxes
// avant de fournir la référence et les données vérifiées à cette fonction.
function makeOfficialQuoteArchivePlan({
  adminUid, requestId, administrativeReference,
  quoteId, quoteNumber, issuedOn, pdfBuffer,
}) {
  const nonEmpty = (s) => typeof s === "string" &&
      s.trim().length > 0 && !s.includes("/");
  if (![adminUid, requestId, quoteId].every(nonEmpty)) {
    throw new Error("Identifiants d'archivage invalides.");
  }
  if (typeof administrativeReference !== "string" ||
      !/^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-\d{6}$/.test(administrativeReference)) {
    throw new Error("Référence du dossier administratif invalide.");
  }
  const member = administrativeReference.match(/(\d{6})$/)[1];
  if (typeof quoteNumber !== "string" ||
      !/^DV-\d{4}-\d{6}-\d{3,}$/.test(quoteNumber) ||
      quoteNumber.split("-")[2] !== member) {
    throw new Error("Numéro de devis officiel incohérent.");
  }
  const year = Number(quoteNumber.split("-")[1]);
  if (typeof issuedOn !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(issuedOn) ||
      Number(issuedOn.slice(0, 4)) !== year) {
    throw new Error("Date d'émission incohérente.");
  }
  if (!Buffer.isBuffer(pdfBuffer) ||
      pdfBuffer.length < 1024 ||
      pdfBuffer.subarray(0, 5).toString("ascii") !== "%PDF-") {
    throw new Error("PDF officiel manquant ou invalide.");
  }

  // Nom stable et unique ; pas d'écrasement d'une ancienne version.
  const storagePath = `adminRequests/${requestId}/documents/financier/` +
      `${year}/devis/${quoteNumber}.pdf`;
  const registryId = `${requestId}_${quoteNumber}`;
  return Object.freeze({
    adminUid, requestId, quoteId, administrativeReference,
    quoteNumber, issuedOn, year, storagePath, registryId,
    sha256: crypto.createHash("sha256").update(pdfBuffer).digest("hex"),
    byteLength: pdfBuffer.length,
  });
}

// Dépendances injectées pour tester l'archivage sans Firebase réel.
// gate est une preuve calculée exclusivement par le serveur d'émission
// APRÈS vérifications ; aucun booléen issu d'un appel client n'est accepté.
// La route publique ne doit pas exposer cette fonction aux utilisateurs.
async function archiveOfficialAdminQuote({
  db, bucket, quoteSnapshot, pdfBuffer, trustedServerGate,
}) {
  if (!trustedServerGate || trustedServerGate.isServerAuthorized !== true ||
      trustedServerGate.issuerLegallyVerified !== true ||
      trustedServerGate.fiscalityVerified !== true) {
    throw new Error("ARCHIVE_BLOCKED_UNVERIFIED_ISSUER");
  }
  if (!quoteSnapshot || quoteSnapshot.exists !== true ||
      typeof quoteSnapshot.data !== "function") {
    throw new Error("Devis officiel existant requis.");
  }
  const quote = quoteSnapshot.data();
  if (quote.status !== "issued" || !quote.quoteNumber ||
      !quote.pdfReadyToArchive) {
    throw new Error("Devis non émis ou PDF non autorisé.");
  }
  if (quoteSnapshot.id !== quote.quoteId) {
    throw new Error("Identifiant du devis incohérent.");
  }
  const plan = makeOfficialQuoteArchivePlan({
    adminUid: quote.adminUid,
    requestId: quote.requestId,
    quoteId: quote.quoteId,
    administrativeReference: quote.administrativeReference,
    quoteNumber: quote.quoteNumber,
    issuedOn: quote.issuedOn,
    pdfBuffer,
  });
  if (!db || typeof db.collection !== "function" ||
      !bucket || typeof bucket.file !== "function") {
    throw new Error("Registre ou stockage indisponible.");
  }

  const registryRef = db.collection("documents").doc(plan.registryId);
  const existing = await registryRef.get();
  const previous = existing.exists ? existing.data() : null;
  if (previous) {
    // Les échecs partiels ne permettent jamais de substituer le PDF.
    if (previous.quoteId !== plan.quoteId ||
        previous.sha256 !== plan.sha256 ||
        previous.storagePath !== plan.storagePath ||
        previous.documentNumber !== plan.quoteNumber) {
      throw new Error("ARCHIVE_CONFLICT_IMMUTABLE");
    }
    if (previous.status === "issued") return previous;
  }

  const file = bucket.file(plan.storagePath);
  const [exists] = await file.exists();
  if (exists) {
    // Reprise idempotente seulement si les octets présents sont identiques.
    const [stored] = await file.download();
    const hash = crypto.createHash("sha256").update(stored).digest("hex");
    if (hash !== plan.sha256) {
      throw new Error("ARCHIVE_STORAGE_CONFLICT");
    }
  } else {
    // La précondition generation=0 empêche tout overwrite concurrent.
    try {
      await file.save(pdfBuffer, {
        resumable: false,
        contentType: "application/pdf",
        preconditionOpts: {ifGenerationMatch: 0},
        metadata: {
          contentDisposition: `attachment; filename="${plan.quoteNumber}.pdf"`,
          metadata: {
            documentType: "quote",
            adminUid: plan.adminUid,
            quoteId: plan.quoteId,
            sha256: plan.sha256,
          },
        },
      });
    } catch (e) {
      // Si un concurrent vient d'écrire, accepter uniquement le même hash.
      const [nowExists] = await file.exists();
      if (!nowExists) throw e;
      const [stored] = await file.download();
      const hash = crypto.createHash("sha256").update(stored).digest("hex");
      if (hash !== plan.sha256) throw new Error("ARCHIVE_STORAGE_CONFLICT");
    }
  }

  const payload = {
    requestId: plan.requestId,
    adminUid: plan.adminUid,
    quoteId: plan.quoteId,
    dossierNumber: plan.administrativeReference,
    documentNumber: plan.quoteNumber,
    documentType: "quote",
    category: "financial",
    subcategory: "devis",
    year: plan.year,
    version: 1,
    title: "DEVIS SPHOT ADMIN",
    status: "issued",
    issuedOn: plan.issuedOn,
    storagePath: plan.storagePath,
    sha256: plan.sha256,
    byteLength: plan.byteLength,
    createdByRole: "system",
  };

  // La création exclusive interdit de modifier un document déjà archivé.
  // Si le PDF a été enregistré mais pas le registre, une reprise le complète.
  try {
    await registryRef.create(payload);
  } catch (e) {
    const current = await registryRef.get();
    if (!current.exists) throw e;
    const saved = current.data();
    if (saved.sha256 !== plan.sha256 ||
        saved.quoteId !== plan.quoteId ||
        saved.storagePath !== plan.storagePath ||
        saved.documentNumber !== plan.quoteNumber ||
        saved.status !== "issued") {
      throw new Error("ARCHIVE_CONFLICT_IMMUTABLE");
    }
    return saved;
  }
  return payload;
}

module.exports = {makeOfficialQuoteArchivePlan, archiveOfficialAdminQuote};
