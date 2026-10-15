/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const crypto = require("node:crypto");
const {assessAdminQuoteIssueReadiness} =
    require("./admin_quote_issue_readiness");

// ARCHIVAGE DES DEVIS OFFICIELS : service interne, JAMAIS un endpoint public.
// Ne crée ni devis, ni numéro DV, ni commande. Le futur orchestrateur serveur
// authentifié sera seul autorisé à préparer le contexte juridique/fiscal vérifié
// et un document quotes/{quoteId} déjà numéroté et "numbered_pending_archive".
//
// Écriture à deux phases :
// 1. Objet PDF en Storage avec précondition de NON-REMPLACEMENT (génération 0).
// 2. Transaction Firestore atomique : documents/{requestId_quoteNumber}
//    puis statut "issued" dans quotes/{quoteId}.
// Si la transaction échoue après l'upload, une nouvelle tentative reprend
// le MÊME fichier grâce à l'empreinte SHA-256, sans l'écraser.
function archiveOfficialAdminQuote(args) {
  const options = args && typeof args === "object" ? args : {};
  const {db, bucket, quoteId, pdfBuffer, verifiedContext, serverTimestamp} =
      options;

  if (!db || typeof db.collection !== "function" ||
      typeof db.runTransaction !== "function" ||
      !bucket || typeof bucket.file !== "function" ||
      typeof serverTimestamp !== "function") {
    throw new TypeError("Services Firestore et Storage serveur requis.");
  }
  const safeId = (value) => typeof value === "string" &&
      /^[A-Za-z0-9_-]{1,220}$/.test(value);
  if (!safeId(quoteId) ||
      !Buffer.isBuffer(pdfBuffer) ||
      pdfBuffer.length < 1024 ||
      pdfBuffer.subarray(0, 5).toString("ascii") !== "%PDF-") {
    throw new TypeError("Identifiant ou PDF officiel invalide.");
  }
  // Aucune confiance accordée à un numéro de devis fourni par Flutter.
  // Le numéro provient du document quotes préexistant et numéroté au serveur.
  const hash = crypto.createHash("sha256").update(pdfBuffer).digest("hex");
  const context = verifiedContext || {};

  return (async () => {
    const quoteRef = db.collection("quotes").doc(quoteId);
    const quoteSnapshot = await quoteRef.get();
    if (!quoteSnapshot.exists) {
      throw new Error("Devis numéroté introuvable.");
    }
    const quote = quoteSnapshot.data() || {};
    const number = quote.quoteNumber;
    const adminUid = quote.adminUid;
    const requestId = quote.requestId;
    const administrativeReference = quote.administrativeReference;
    const issuedOn = quote.issuedOn;
    const subscriptionYear = quote.subscriptionYear;
    const member = typeof administrativeReference === "string" ?
      administrativeReference.match(
          /^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-(\d{6})$/i,
      ) : null;
    if (!safeId(adminUid) || !safeId(requestId) ||
        !member || typeof number !== "string" ||
        !/^DV-\d{4}-\d{6}-\d{3,}$/.test(number) ||
        number.slice(8, 14) !== member[1] ||
        number.slice(3, 7) !== issuedOn?.slice(0, 4)) {
      throw new Error("Références officielles incohérentes.");
    }
    if (context.adminUid !== adminUid ||
        context.requestId !== requestId ||
        context.administrativeReference !== administrativeReference ||
        context.subscriptionYear !== subscriptionYear ||
        context.issuedOn !== issuedOn ||
        context.quoteNumber !== number) {
      throw new Error("Contexte serveur différent du devis numéroté.");
    }
    const docId = requestId + "_" + number;
    const archivePath = "adminRequests/" + requestId +
        "/documents/financier/" + issuedOn.slice(0, 4) +
        "/devis/" + number + ".pdf";
    const registryRef = db.collection("documents").doc(docId);

    const existing = await registryRef.get();
    const previous = existing.exists ? existing.data() || {} : {};
    if (existing.exists) {
      if (previous.status !== "issued" ||
          previous.documentType !== "quote" ||
          previous.quoteId !== quoteId ||
          previous.sha256 !== hash ||
          previous.storagePath !== archivePath ||
          quote.status !== "issued") {
        throw new Error("Conflit d'archivage : document existant différent.");
      }
      return {documentId: docId, storagePath: archivePath, sha256: hash,
        alreadyArchived: true};
    }

    if (quote.status !== "numbered_pending_archive") {
      throw new Error("Le devis n'est pas autorisé à être archivé.");
    }
    const readiness = assessAdminQuoteIssueReadiness(context);
    if (!readiness.ready) {
      const e = new Error("Devis non prêt : " + readiness.issues.join(", "));
      e.code = "QUOTE_NOT_READY";
      throw e;
    }
    if (quote.validUntil !== readiness.validity.validUntil) {
      throw new Error("Date limite de validité différente du devis.");
    }

    const file = bucket.file(archivePath);
    try {
      await file.save(pdfBuffer, {
        resumable: false,
        contentType: "application/pdf",
        preconditionOpts: {ifGenerationMatch: 0},
        metadata: {
          contentDisposition: 'attachment; filename="' + number + '.pdf"',
          metadata: {
            adminUid, requestId, quoteId, quoteNumber: number, sha256: hash,
          },
        },
      });
    } catch (error) {
      // La génération 0 empêche une modification du PDF déjà archivé.
      // Une reprise après incident n'est permise que si les octets sont
      // STRICTEMENT identiques à la première tentative.
      if (Number(error && error.code) !== 412) throw error;
      const downloaded = await file.download();
      const archivedBytes = Array.isArray(downloaded) ? downloaded[0] : null;
      if (!Buffer.isBuffer(archivedBytes) ||
          crypto.createHash("sha256").update(archivedBytes)
              .digest("hex") !== hash) {
        throw new Error("Conflit Storage : le PDF existant est différent.");
      }
    }

    const finalResult = await db.runTransaction(async (tx) => {
      // Les lectures doivent précéder toutes les écritures Firestore.
      const liveQuoteSnapshot = await tx.get(quoteRef);
      const liveRegistrySnapshot = await tx.get(registryRef);
      const liveQuote = liveQuoteSnapshot.data() || {};
      if (!liveQuoteSnapshot.exists ||
          liveQuote.quoteNumber !== number ||
          liveQuote.adminUid !== adminUid ||
          liveQuote.requestId !== requestId ||
          liveQuote.administrativeReference !== administrativeReference ||
          liveQuote.issuedOn !== issuedOn ||
          liveQuote.subscriptionYear !== subscriptionYear ||
          liveQuote.validUntil !== quote.validUntil) {
        throw new Error("Le devis a changé durant l'archivage.");
      }
      if (liveRegistrySnapshot.exists) {
        const stored = liveRegistrySnapshot.data() || {};
        if (stored.sha256 !== hash ||
            stored.documentType !== "quote" ||
            stored.quoteId !== quoteId ||
            stored.status !== "issued" ||
            stored.storagePath !== archivePath ||
            liveQuote.status !== "issued") {
          throw new Error("Un autre document est déjà archivé sous ce numéro.");
        }
        return true;
      }
      if (liveQuote.status !== "numbered_pending_archive") {
        throw new Error("La phase d'archivage a changé.");
      }
      const timestamp = serverTimestamp();
      tx.create(registryRef, {
        requestId, adminUid,
        dossierNumber: administrativeReference,
        administrativeReference,
        quoteId, quoteNumber: number,
        documentNumber: number, documentType: "quote",
        category: "financial", subcategory: "devis",
        year: Number(issuedOn.slice(0, 4)),
        title: "DEVIS SPHOT ADMIN",
        status: "issued", version: 1,
        issuedOn, validUntil: quote.validUntil,
        pricingReference: context.publishedQuote.pricingReference,
        pricingVersion: context.publishedQuote.version,
        numberOfRescueStations: context.publishedQuote.numberOfRescueStations,
        amountExclTax: context.publishedQuote.amountExclTax,
        taxAmount: context.taxDecision.taxAmount,
        amountInclTax: context.taxDecision.amountInclTax,
        taxTreatment: context.taxDecision.taxTreatment,
        currency: context.publishedQuote.currency,
        sha256: hash, pdfSize: pdfBuffer.length,
        storagePath: archivePath,
        issuedAt: timestamp, createdAt: timestamp,
        createdByRole: "system",
      });
      tx.update(quoteRef, {
        status: "issued",
        pdfArchived: true,
        documentId: docId,
        storagePath: archivePath,
        pdfSha256: hash,
        issuedAt: timestamp,
        updatedAt: timestamp,
      });
      return false;
    });

    return {documentId: docId, storagePath: archivePath, sha256: hash,
      alreadyArchived: finalResult};
  })();
}

module.exports = {archiveOfficialAdminQuote};
