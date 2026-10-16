/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {adminQuote, publishedState} = require("./commercial_quote_pricing");
const {assessAdminQuoteIssueReadiness} =
    require("./admin_quote_issue_readiness");

// Orchestrateur INTERNE, phase 1 : contrôle préalable STRICTEMENT EN LECTURE.
// Aucun endpoint public, aucune création de devis, aucun DV, PDF, email,
// commande, paiement ou activation d'abonnement.
// Le futur service serveur devra fournir les adaptateurs ci-dessous.
// ATTENTION : Firestore contient encore des collections modifiables depuis
// le navigateur. Une valeur "verified" stockée dans ces collections n'est
// PAS une preuve fiable. Les adaptateurs doivent vérifier les données depuis
// des sources protégées avant toute activation du circuit d'émission.
function blocked(reasonCodes) {
  return Object.freeze({
    status: "blocked",
    reasonCodes: Object.freeze([...reasonCodes]),
  });
}

function safeId(value) {
  return typeof value === "string" &&
      /^[A-Za-z0-9_-]{1,220}$/.test(value);
}

async function inspectOfficialAdminQuote({idToken, quoteId, services} = {}) {
  // Seuls l'identifiant du devis et le jeton Firebase peuvent provenir
  // de l'appelant. Aucun tarif, booléen de validation ou identité payeur
  // fourni par le navigateur n'est accepté par cette interface.
  if (!safeId(quoteId) ||
      typeof idToken !== "string" || !idToken.trim()) {
    return blocked(["INVALID_REQUEST"]);
  }

  const required = [
    "verifyIdToken",
    "getAdminAccess",
    "getAdminRequest",
    "getVerifiedQuoteContext",
    "getPublishedPricing",
  ];
  if (!services || required.some((key) =>
    typeof services[key] !== "function")) {
    return blocked(["TRUSTED_SERVER_SERVICES_UNAVAILABLE"]);
  }

  // Firebase Authentication ; NE PAS se contenter d'un adminUid transmis
  // par l'interface Flutter.
  const session = await services.verifyIdToken(idToken);
  if (!session || !safeId(session.uid) ||
      session.adminUid !== session.uid ||
      String(session.role || "").toUpperCase() !== "ADMIN") {
    return blocked(["ADMIN_AUTHENTICATION_INVALID"]);
  }
  const uid = session.uid;

  // getAdminAccess doit combiner en serveur la validité d'adminAccounts,
  // les droits d'admins/{uid} et le territoire autorisé.
  const access = await services.getAdminAccess(uid);
  if (!access || access.uid !== uid ||
      String(access.role || "").toUpperCase() !== "ADMIN" ||
      access.accountStatus !== "ACTIVE" ||
      access.accessStatus !== "approved" ||
      !safeId(access.territoireId) ||
      session.territoireId !== access.territoireId) {
    return blocked(["ADMIN_ACCESS_DENIED"]);
  }

  // Dossier administratif identifié par l'UID attendu par le mécanisme DV.
  const request = await services.getAdminRequest(uid);
  if (!request || request.uid !== uid ||
      typeof request.requestNumber !== "string" ||
      !/^SPHOT-ADM-(?:[A-Z]{3}-)?\d{4}-\d{6}$/.test(
          request.requestNumber)) {
    return blocked(["ADMIN_REQUEST_NOT_VERIFIED"]);
  }

  // Données obtenues exclusivement par un adaptateur serveur de confiance :
  // émetteur légal, payeur et pouvoir de facturation, postes du territoire,
  // année, date d'émission serveur et décision fiscale vérifiée.
  const context = await services.getVerifiedQuoteContext({
    quoteId, adminUid: uid, requestId: uid,
    territoireId: access.territoireId,
  });
  if (!context || context.quoteId !== quoteId ||
      context.adminUid !== uid || context.requestId !== uid ||
      context.territoireId !== access.territoireId ||
      context.administrativeReference !== request.requestNumber ||
      context.quoteNumber != null) {
    return blocked(["QUOTE_CONTEXT_MISMATCH"]);
  }

  const stations = context.stations;
  if (!Array.isArray(stations) || stations.length === 0) {
    return blocked(["RESCUE_STATIONS_NOT_VERIFIED"]);
  }

  // Le prix est TOUJOURS recalculé depuis la grille publiée.
  // Ne jamais reprendre un prix déclaré par le navigateur ou le brouillon.
  let pricing;
  try {
    const snapshot = await services.getPublishedPricing("FR_ADMIN");
    const publication = publishedState(snapshot, "ADMIN");
    pricing = adminQuote(publication, stations.length);
  } catch (_) {
    return blocked(["PUBLISHED_PRICING_UNAVAILABLE"]);
  }

  const checkedContext = {
    ...context,
    publishedQuote: {
      ...pricing,
      fromServerPublishedCatalog: true,
    },
  };
  const readiness = assessAdminQuoteIssueReadiness(checkedContext);
  if (!readiness.ready) {
    return blocked(readiness.issues);
  }

  return Object.freeze({
    status: "preflight_passed",
    // Ce résultat ne constitue PAS une autorisation d'émission.
    // Un prochain service devra refaire les vérifications au moment
    // d'écrire quoteIssueAuthorizations et quotes en transaction.
    quoteId,
    adminUid: uid,
    territoireId: access.territoireId,
    administrativeReference: request.requestNumber,
    subscriptionYear: context.subscriptionYear,
    issuedOn: context.issuedOn,
    validUntil: readiness.validity.validUntil,
    pricingReference: pricing.pricingReference,
    numberOfRescueStations: stations.length,
    amountExclTax: pricing.amountExclTax,
    emissionAuthorized: false,
  });
}

module.exports = {inspectOfficialAdminQuote};
