/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {quoteValidityForCalendarYear} = require("./admin_quote_validity");

// Numérotation DV, à usage EXCLUSIF du trigger Firestore serveur.
// Ne fait confiance ni au statut du devis seul, ni aux indicateurs envoyés
// par Flutter. L'autorisation distincte quoteIssueAuthorizations/{quoteId}
// doit être créée exclusivement par le FUTUR service d'émission authentifié,
// après vérifications juridiques, fiscales, tarifaires et administratives.
// Les règles Firestore doivent interdire tout accès client à cette collection.
async function assignAuthorizedAdminQuoteNumber({db, event, serverTimestamp}) {
  if (!event || !event.data || !event.data.after ||
      !event.data.after.exists) return false;
  if (!db || typeof db.collection !== "function" ||
      typeof db.runTransaction !== "function" ||
      typeof serverTimestamp !== "function") {
    throw new TypeError("Services de numérotation serveur requis.");
  }

  const quoteRef = event.data.after.ref;
  const safeId = (value) => typeof value === "string" &&
      /^[A-Za-z0-9_-]{1,220}$/.test(value);
  if (!quoteRef || !safeId(quoteRef.id)) return false;

  return db.runTransaction(async (tx) => {
    const quoteSnapshot = await tx.get(quoteRef);
    if (!quoteSnapshot.exists) return false;
    const quote = quoteSnapshot.data() || {};
    if (quote.quoteNumber || quote.status !== "authorized_pending_number") {
      return false;
    }

    const {adminUid, requestId, quoteId, administrativeReference,
      issuedOn, subscriptionYear, validUntil} = quote;
    if (!safeId(adminUid) || !safeId(requestId) ||
        !safeId(quoteId) || quoteId !== quoteRef.id ||
        adminUid !== requestId ||
        typeof administrativeReference !== "string" ||
        !/^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-\d{6}$/.test(administrativeReference)) {
      return false;
    }
    const member = administrativeReference.slice(-6);
    let validity;
    try {
      validity = quoteValidityForCalendarYear(issuedOn, subscriptionYear);
    } catch (_) {
      return false;
    }
    if (validUntil !== validity.validUntil) return false;

    // Toutes ces lectures précèdent la moindre écriture transactionnelle.
    const authRef = db.collection("quoteIssueAuthorizations").doc(quoteId);
    const requestRef = db.collection("adminRequests").doc(requestId);
    const approvalSnapshot = await tx.get(authRef);
    const requestSnapshot = await tx.get(requestRef);
    if (!approvalSnapshot.exists || !requestSnapshot.exists) return false;
    const approval = approvalSnapshot.data() || {};
    const request = requestSnapshot.data() || {};
    if (request.requestNumber !== administrativeReference ||
        (request.uid && request.uid !== adminUid)) return false;

    // Une preuve isolée ou un simple booléen dans quotes ne suffit pas.
    // Les états ci-dessous ne sont honorés QUE dans ce registre protégé.
    if (approval.type !== "official_admin_quote" ||
        approval.status !== "approved_for_numbering" ||
        approval.quoteId !== quoteId ||
        approval.adminUid !== adminUid ||
        approval.requestId !== requestId ||
        approval.administrativeReference !== administrativeReference ||
        approval.issuedOn !== issuedOn ||
        approval.subscriptionYear !== subscriptionYear ||
        approval.validUntil !== validUntil ||
        approval.issuerLegallyVerified !== true ||
        approval.fiscalityVerified !== true ||
        approval.publishedPricingVerified !== true ||
        approval.buyerVerified !== true ||
        approval.stationsVerified !== true ||
        approval.adminRightsVerified !== true ||
        approval.thirdPartyBillingVerified !== true) {
      return false;
    }

    const year = Number(issuedOn.slice(0, 4));
    const counterRef = db.collection("counters")
        .doc("quotes_" + year + "_" + member);
    const counterSnapshot = await tx.get(counterRef);
    const counterData = counterSnapshot.data() || {};
    const lastNumber = counterSnapshot.exists ? counterData.lastNumber : 0;
    if (!Number.isSafeInteger(lastNumber) || lastNumber < 0 ||
        lastNumber >= Number.MAX_SAFE_INTEGER) {
      throw new Error("Compteur de devis invalide.");
    }
    const sequence = lastNumber + 1;
    const number = "DV-" + year + "-" + member + "-" +
        String(sequence).padStart(3, "0");
    const timestamp = serverTimestamp();
    tx.set(counterRef, {
      documentType: "quote", year, perMember: true,
      memberNumber: member, lastNumber: sequence, updatedAt: timestamp,
    }, {merge: true});
    tx.update(quoteRef, {
      quoteNumber: number,
      status: "numbered_pending_archive",
      year, sequence,
      numberedAt: timestamp, updatedAt: timestamp,
    });
    // Consommation dans la MÊME transaction : autorisation à usage unique.
    tx.update(authRef, {
      status: "numbered", quoteNumber: number, consumedAt: timestamp,
    });
    return true;
  });
}

module.exports = {assignAuthorizedAdminQuoteNumber};
