/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const {renderOfficialAdminQuotePdf} =
    require("./admin_official_quote_pdf");
const {archiveOfficialAdminQuote, commercialSnapshotForQuote} =
    require("./admin_official_quote_archive");
const {buildAdminOfficialQuoteEmail} =
    require("./admin_quote_email");
const {assessAdminQuoteIssueReadiness} =
    require("./admin_quote_issue_readiness");

// Phase documentaire INTERNE du circuit de devis SPHOT ADMIN.
//
// Entrée : devis DEJA autorisé et numéroté, avec contexte issu de lectures
// serveur de confiance. Ce module NE délivre AUCUNE autorisation d'émission,
// NE crée AUCUN numéro, NE transmet AUCUN email et n'est PAS un endpoint.
// Toute liaison à Flutter ou à une Cloud Function exige d'abord la validation
// des sources protégées, de l'émetteur et du traitement fiscal.
async function prepareOfficialAdminQuoteDelivery(args = {}) {
  const {db, bucket, quoteId, verifiedContext, adminEmail,
    serverTimestamp} = args;
  const safeId = (value) => typeof value === "string" &&
      /^[A-Za-z0-9_-]{1,220}$/.test(value);
  if (typeof adminEmail !== "string" ||
      !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(adminEmail.trim())) {
    throw new TypeError("Email Admin serveur invalide.");
  }
  if (!db || typeof db.collection !== "function" ||
      typeof db.runTransaction !== "function" ||
      !bucket || typeof bucket.file !== "function" ||
      typeof serverTimestamp !== "function" ||
      !safeId(quoteId)) {
    throw new TypeError("Services internes de préparation du devis invalides.");
  }

  const quoteRef = db.collection("quotes").doc(quoteId);
  const quoteSnapshot = await quoteRef.get();
  if (!quoteSnapshot.exists) {
    throw new Error("Devis officiel numéroté introuvable.");
  }
  const quote = quoteSnapshot.data() || {};
  const context = verifiedContext || {};
  const status = quote.status;
  if (status !== "numbered_pending_archive" && status !== "issued") {
    throw new Error("Le devis ne peut pas être préparé pour l'envoi.");
  }
  const number = quote.quoteNumber;
  if (!safeId(quote.adminUid) || !safeId(quote.requestId) ||
      quote.adminUid !== quote.requestId ||
      quote.quoteId && quote.quoteId !== quoteId ||
      typeof number !== "string" ||
      !/^DV-\d{4}-\d{6}-\d{3,}$/.test(number) ||
      typeof quote.administrativeReference !== "string" ||
      !/^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-\d{6}$/.test(
          quote.administrativeReference) ||
      number.slice(8, 14) !== quote.administrativeReference.slice(-6) ||
      number.slice(3, 7) !== quote.issuedOn?.slice(0, 4) ||
      context.adminUid !== quote.adminUid ||
      context.requestId !== quote.requestId ||
      context.quoteNumber !== number ||
      context.administrativeReference !== quote.administrativeReference ||
      context.issuedOn !== quote.issuedOn ||
      context.subscriptionYear !== quote.subscriptionYear) {
    throw new Error("Références du dossier et contexte serveur incohérents.");
  }

  const assessment = assessAdminQuoteIssueReadiness(context);
  if (!assessment.ready ||
      assessment.validity.validUntil !== quote.validUntil) {
    throw new Error("Émission bloquée : validations du devis manquantes.");
  }

  let pdf;
  let archival;
  let alreadyArchived = false;

  if (status === "numbered_pending_archive") {
    // PDF produit par le moteur SPHOT réel et conservé uniquement en mémoire
    // avant l'archivage; jamais par Flutter ni par un faux document client.
    pdf = await renderOfficialAdminQuotePdf(
        context, number, quote.administrativeReference);
    archival = await archiveOfficialAdminQuote({
      db, bucket, quoteId, pdfBuffer: pdf,
      verifiedContext: context, serverTimestamp,
    });
    alreadyArchived = archival.alreadyArchived === true;
  } else {
    // Reprise APRES archivage : utiliser les octets immuables stockés,
    // et NON un PDF régénéré (PDFKit peut produire des octets différents).
    if (quote.pdfArchived !== true || !safeId(quote.documentId) ||
        typeof quote.storagePath !== "string" ||
        typeof quote.pdfSha256 !== "string") {
      throw new Error("Devis émis sans archive intègre.");
    }
    const expectedId = quote.requestId + "_" + number;
    const expectedPath = "adminRequests/" + quote.requestId +
        "/documents/financier/" + quote.issuedOn.slice(0, 4) +
        "/devis/" + number + ".pdf";
    if (quote.documentId !== expectedId ||
        quote.storagePath !== expectedPath) {
      throw new Error("Références d'archive incohérentes.");
    }
    const registered = await db.collection("documents")
        .doc(expectedId).get();
    const registry = registered.data() || {};
    if (!registered.exists || registry.status !== "issued" ||
        registry.documentType !== "quote" ||
        registry.documentNumber !== number ||
        registry.quoteId !== quoteId ||
        registry.adminUid !== quote.adminUid ||
        registry.storagePath !== expectedPath ||
        registry.sha256 !== quote.pdfSha256 ||
        registry.pricingReference !==
            context.publishedQuote.pricingReference ||
        registry.amountExclTax !==
            context.publishedQuote.amountExclTax ||
        registry.taxAmount !== context.taxDecision.taxAmount ||
        registry.amountInclTax !== context.taxDecision.amountInclTax ||
        !isDeepStrictEqual(registry.commercialSnapshot,
            commercialSnapshotForQuote(context))) {
      throw new Error("Registre d'archive incohérent.");
    }
    const downloaded = await bucket.file(expectedPath).download();
    pdf = Array.isArray(downloaded) ? downloaded[0] : null;
    if (!Buffer.isBuffer(pdf) || pdf.length < 1024 ||
        pdf.subarray(0, 5).toString("ascii") !== "%PDF-" ||
        crypto.createHash("sha256").update(pdf).digest("hex") !==
            registry.sha256) {
      throw new Error("PDF archivé absent ou altéré.");
    }
    archival = {documentId: expectedId, storagePath: expectedPath};
    alreadyArchived = true;
  }

  // Le statut et le registre doivent avoir été durablement créés AVANT
  // qu'on puisse seulement PREPARER le message. Aucun SMTP n'est appelé.
  const finalQuote = await quoteRef.get();
  const finalData = finalQuote.data() || {};
  const documentId = quote.requestId + "_" + number;
  if (!finalQuote.exists || finalData.status !== "issued" ||
      finalData.pdfArchived !== true ||
      finalData.documentId !== documentId ||
      finalData.storagePath !== archival.storagePath) {
    throw new Error("Devis non archivé : email interdit.");
  }

  const message = buildAdminOfficialQuoteEmail({
    documentStatus: "issued",
    pdfArchived: true,
    issuerLegallyVerified: context.issuer.legalRegistrationVerified,
    fiscalityVerified: context.taxDecision.calculationVerified,
    adminEmail,
    quoteNumber: number,
    buyerName: context.buyer.legalName,
    amountExclTax: context.publishedQuote.amountExclTax,
    currency: context.publishedQuote.currency,
    issuedOn: context.issuedOn,
    subscriptionYear: context.subscriptionYear,
    validUntil: quote.validUntil,
    pdfBuffer: pdf,
  });

  return {
    status: "email_prepared_not_sent",
    quoteNumber: number,
    documentId,
    storagePath: archival.storagePath,
    alreadyArchived,
    pdfSize: pdf.length,
    message,
    emailSent: false,
  };
}

module.exports = {prepareOfficialAdminQuoteDelivery};
