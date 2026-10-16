/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const crypto = require("node:crypto");

const safeId = (value) => typeof value === "string" &&
    /^[A-Za-z0-9_-]{1,220}$/.test(value);
const validEmail = (value) => typeof value === "string" &&
    /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value.trim());
const normalizeEmail = (value) => String(value || "").trim().toLowerCase();
const validNumber = (value) => typeof value === "string" &&
    /^DV-\d{4}-\d{6}-\d{3,}$/.test(value);

function refuse(reason) {
  const error = new Error(reason);
  error.code = "ADMIN_QUOTE_EMAIL_NOT_ALLOWED";
  return error;
}

// Livraison INTERNE d'un devis DÉJÀ émis et archivé par le serveur.
// Jamais appelé par Flutter, jamais exporté par functions/index.js.
// Envoi au PLUS UNE FOIS automatiquement : après un état "sending", une
// panne ou une réponse SMTP ambiguë nécessite une revue humaine.
// "Exactly once" est impossible à garantir avec Firestore + SMTP sans
// mécanisme de déduplication pris en charge par le fournisseur d'email.
async function sendIssuedAdminQuoteEmail({db, quoteId, preparedDelivery,
  sendMail, serverTimestamp} = {}) {
  if (!db || typeof db.collection !== "function" ||
      typeof db.runTransaction !== "function" ||
      !safeId(quoteId) || typeof sendMail !== "function" ||
      typeof serverTimestamp !== "function") {
    throw refuse("Services d'envoi serveur manquants.");
  }
  const draft = preparedDelivery || {};
  const number = draft.quoteNumber;
  const documentId = draft.documentId;
  const message = draft.message || {};
  if (draft.status !== "email_prepared_not_sent" ||
      draft.emailSent !== false || !validNumber(number) ||
      !safeId(documentId) || !validEmail(message.to) ||
      !Array.isArray(message.attachments)) {
    throw refuse("Email de devis officiel non préparé.");
  }
  const pdf = message.attachments.filter((attachment) =>
    attachment && attachment.filename === number + ".pdf" &&
    attachment.contentType === "application/pdf" &&
    Buffer.isBuffer(attachment.content));
  if (pdf.length !== 1 || pdf[0].content.length < 1024 ||
      pdf[0].content.subarray(0, 5).toString("ascii") !== "%PDF-") {
    throw refuse("Pièce jointe PDF absente ou invalide.");
  }
  const hash = crypto.createHash("sha256")
      .update(pdf[0].content).digest("hex");
  const quoteRef = db.collection("quotes").doc(quoteId);

  // Le destinataire est issu du compte protégé adminAccounts.
  // Ni le champ client, ni le payeur déclaré dans subscriptions ne sont
  // des sources d'autorité pour choisir l'adresse de livraison.
  const quoteSnap = await quoteRef.get();
  if (!quoteSnap.exists) throw refuse("Devis introuvable.");
  const quote = quoteSnap.data() || {};
  if (!safeId(quote.adminUid) || quote.adminUid !== quote.requestId ||
      !safeId(quote.requestId) || quote.quoteNumber !== number ||
      quote.status !== "issued" || quote.pdfArchived !== true ||
      quote.documentId !== documentId ||
      quote.pdfSha256 !== hash ||
      documentId !== quote.requestId + "_" + number ||
      quote.storagePath !== "adminRequests/" + quote.requestId +
          "/documents/financier/" + number.slice(3, 7) +
          "/devis/" + number + ".pdf" ||
      draft.storagePath !== quote.storagePath ||
      !/^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-\d{6}$/.test(
          quote.administrativeReference || "")) {
    throw refuse("Devis archivé incohérent.");
  }
  const accounts = await db.collection("adminAccounts")
      .where("adminUid", "==", quote.adminUid).limit(10).get();
  if (!accounts || !Array.isArray(accounts.docs) ||
      accounts.docs.length >= 10) {
    throw refuse("Identité Admin ambiguë.");
  }
  const activeAccounts = accounts.docs.filter((doc) => {
    const account = doc.data() || {};
    return account.adminUid === quote.adminUid &&
        account.accountStatus === "ACTIVE" &&
        String(account.role || "").toUpperCase() === "ADMIN" &&
        safeId(account.territoireId);
  });
  if (activeAccounts.length !== 1) throw refuse("Compte Admin non autorisé.");
  const account = activeAccounts[0].data() || {};
  const email = normalizeEmail(account.email);
  if (!validEmail(email) || normalizeEmail(message.to) !== email) {
    throw refuse("Destinataire différent du compte Admin protégé.");
  }

  // Deux registres serveur doivent correspondre au PDF préparé :
  // autorisation officielle consommée ET archive immuable du document.
  const registryRef = db.collection("documents").doc(documentId);
  const authorizationRef = db.collection("quoteIssueAuthorizations")
      .doc(quoteId);
  const claimed = await db.runTransaction(async (tx) => {
    const quoteInTx = await tx.get(quoteRef);
    const registrySnap = await tx.get(registryRef);
    const authorizedSnap = await tx.get(authorizationRef);
    const live = quoteInTx.data() || {};
    const registry = registrySnap.data() || {};
    const authorization = authorizedSnap.data() || {};
    if (!quoteInTx.exists || !registrySnap.exists ||
        !authorizedSnap.exists ||
        live.status !== "issued" || live.pdfArchived !== true ||
        live.adminUid !== quote.adminUid ||
        live.requestId !== quote.requestId ||
        live.quoteNumber !== number ||
        live.documentId !== documentId || live.pdfSha256 !== hash ||
        registry.adminUid !== quote.adminUid ||
        registry.requestId !== quote.requestId ||
        registry.quoteId !== quoteId ||
        registry.documentNumber !== number ||
        registry.documentType !== "quote" ||
        registry.status !== "issued" ||
        registry.sha256 !== hash ||
        registry.storagePath !== live.storagePath ||
        registry.pdfSize !== pdf[0].content.length ||
        registry.issuedOn !== live.issuedOn ||
        registry.validUntil !== live.validUntil ||
        authorization.type !== "official_admin_quote" ||
        authorization.status !== "numbered" ||
        authorization.quoteId !== quoteId ||
        authorization.adminUid !== quote.adminUid ||
        authorization.requestId !== quote.requestId ||
        authorization.quoteNumber !== number ||
        authorization.administrativeReference !==
            live.administrativeReference ||
        authorization.issuedOn !== live.issuedOn ||
        authorization.subscriptionYear !== live.subscriptionYear ||
        authorization.validUntil !== live.validUntil ||
        authorization.issuerLegallyVerified !== true ||
        authorization.fiscalityVerified !== true ||
        authorization.publishedPricingVerified !== true ||
        authorization.buyerVerified !== true ||
        authorization.stationsVerified !== true ||
        authorization.adminRightsVerified !== true ||
        authorization.thirdPartyBillingVerified !== true) {
      throw refuse("Devis sans autorisation et archive vérifiées.");
    }
    const state = live.emailDelivery;
    if (state) {
      if (state.recipient !== email || state.quoteNumber !== number ||
          state.documentId !== documentId || state.pdfSha256 !== hash ||
          state.attemptCount !== 1) {
        throw refuse("Registre de livraison incohérent.");
      }
      if (state.status === "sent") return "already_sent";
      if (["sending", "needs_review"].includes(state.status)) {
        return "requires_review";
      }
      throw refuse("Statut de livraison inconnu.");
    }
    tx.update(quoteRef, {
      emailDelivery: {
        status: "sending", recipient: email,
        quoteNumber: number, documentId, pdfSha256: hash,
        attemptCount: 1, claimedAt: serverTimestamp(),
      },
    });
    return "claimed";
  });
  if (claimed !== "claimed") return {status: claimed, emailSent: false};

  // L'envoi SMTP est volontairement situé APRÈS le verrou Firestore.
  // Ne jamais relancer automatiquement un essai incertain.
  let accepted = false;
  let messageId = "";
  try {
    const result = await sendMail(message);
    accepted = Array.isArray(result && result.accepted) &&
        result.accepted.some((a) => normalizeEmail(a) === email) &&
        !(Array.isArray(result.rejected) && result.rejected.some((a) =>
          normalizeEmail(a) === email));
    messageId = result && typeof result.messageId === "string" ?
      result.messageId : "";
  } catch (_) {
    // Un timeout ne prouve PAS que le SMTP a échoué : arrêt des relances.
  }

  let stored = false;
  try {
    await db.runTransaction(async (tx) => {
      const current = await tx.get(quoteRef);
      const state = current.data()?.emailDelivery || {};
      if (!current.exists || state.status !== "sending" ||
          state.recipient !== email || state.pdfSha256 !== hash ||
          state.attemptCount !== 1 || state.documentId !== documentId) {
        throw refuse("État d'envoi modifié.");
      }
      tx.update(quoteRef, {
        emailDelivery: {
          ...state,
          status: accepted ? "sent" : "needs_review",
          ...(accepted ? {messageId} : {}),
          completedAt: serverTimestamp(),
        },
      });
    });
    stored = true;
  } catch (_) {
    // Le statut peut être resté "sending" APRÈS un SMTP réussi.
    // C'est un cas de revue manuelle, jamais de renvoi automatique.
  }
  return {
    status: accepted && stored ? "sent" : "requires_review",
    // Le fournisseur SMTP peut avoir accepté un message même si la
    // confirmation Firestore n'a pas pu être enregistrée.
    emailSent: accepted && stored,
  };
}

module.exports = {sendIssuedAdminQuoteEmail};
