/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {quoteValidityForCalendarYear} = require("./admin_quote_validity");

// Préparation du DEVIS OFFICIEL SPHOT ADMIN.
// Cette fonction ne crée AUCUN devis, ne numérote rien et n'écrit pas en base.
// Les objets d'entrée doivent provenir de lectures SERVEUR authentifiées :
// jamais d'une déclaration « vérifié » transmise par le navigateur.
function assessAdminQuoteIssueReadiness(context) {
  const c = context && typeof context === "object" ? context : {};
  const issuer = c.issuer || {};
  const buyer = c.buyer || {};
  const quote = c.publishedQuote || {};
  const stations = Array.isArray(c.stations) ? c.stations : [];
  const tax = c.taxDecision || {};
  const issues = [];

  function requireCondition(condition, code) {
    if (!condition) issues.push(code);
  }
  function filled(value) {
    return typeof value === "string" && value.trim().length > 0;
  }
  function validEmail(value) {
    return filled(value) && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value.trim());
  }
  function validFrenchSiret(value) {
    return filled(value) && /^\d{14}$/.test(value.trim());
  }
  function legalIdentifier(entity) {
    return entity.country === "FR" ?
      validFrenchSiret(entity.siret) : filled(entity.officialId);
  }
  function validAddress(entity) {
    return filled(entity.address) && filled(entity.postalCode) &&
      filled(entity.city) && filled(entity.country);
  }

  // Les trois vérifications suivantes seront déterminées par le système
  // juridique/fiscal serveur et NON par les champs modifiables du client.
  requireCondition(filled(issuer.legalName) && legalIdentifier(issuer) &&
      validAddress(issuer) && issuer.legalRegistrationVerified === true,
  "ISSUER_NOT_LEGALLY_VERIFIED");
  requireCondition(issuer.commercialIssuanceEnabled === true,
      "OFFICIAL_ISSUANCE_NOT_AUTHORIZED");

  requireCondition(filled(buyer.legalName) && legalIdentifier(buyer) &&
      validAddress(buyer) && validEmail(buyer.billingEmail) &&
      buyer.legalIdentityVerified === true,
  "BUYER_NOT_LEGALLY_VERIFIED");
  if (buyer.isDifferentFromManager === true) {
    requireCondition(buyer.thirdPartyBillingAuthorized === true,
        "THIRD_PARTY_PAYER_NOT_AUTHORIZED");
  }

  requireCondition(stations.length > 0 &&
      stations.every((spot) => filled(spot.spotDocumentId) &&
          filled(spot.name) && spot.isRescueStation === true &&
          spot.belongsToAdminTerritory === true) &&
      new Set(stations.map((spot) => spot.spotDocumentId)).size ===
          stations.length,
  "RESCUE_STATIONS_NOT_VERIFIED");

  const lines = Array.isArray(quote.lines) ? quote.lines : [];
  const totalFromLines = lines.reduce((sum, item) => {
    if (!item || !Number.isSafeInteger(item.count) ||
        item.count < 0 || !Number.isSafeInteger(item.unitExclTax) ||
        item.unitExclTax <= 0 || !Number.isSafeInteger(item.amountExclTax) ||
        item.count * item.unitExclTax !== item.amountExclTax) return NaN;
    return sum + item.amountExclTax;
  }, 0);
  requireCondition(
      quote.market === "ADMIN" &&
      quote.country === "FR" && quote.currency === "EUR" &&
      Number.isSafeInteger(quote.version) && quote.version > 0 &&
      quote.pricingReference === "FR_ADMIN-V" + quote.version &&
      quote.fromServerPublishedCatalog === true &&
      quote.numberOfRescueStations === stations.length &&
      lines.length === 4 &&
      Number.isSafeInteger(quote.amountExclTax) &&
      quote.amountExclTax > 0 &&
      totalFromLines === quote.amountExclTax,
      "PUBLISHED_PRICE_NOT_REVALIDATED",
  );

  // Pas de taux TVA implicite, même lorsque le taux final est de 0 %.
  // Chaque montant doit provenir d'une décision fiscale vérifiée au serveur.
  requireCondition(tax.status === "validated" &&
      filled(tax.jurisdiction) &&
      filled(tax.taxTreatment) &&
      filled(tax.legalBasis) &&
      tax.currency === quote.currency &&
      Number.isSafeInteger(tax.amountExclTax) &&
      tax.amountExclTax === quote.amountExclTax &&
      Number.isSafeInteger(tax.taxAmount) && tax.taxAmount >= 0 &&
      Number.isSafeInteger(tax.amountInclTax) &&
      tax.amountInclTax === tax.amountExclTax + tax.taxAmount &&
      tax.calculationVerified === true,
  "TAX_TREATMENT_NOT_VERIFIED");

  let validity = null;
  try {
    validity = quoteValidityForCalendarYear(
        c.issuedOn,
        c.subscriptionYear,
    );
  } catch (_) {
    issues.push("QUOTE_PERIOD_OR_DATE_INVALID");
  }

  return Object.freeze({
    ready: issues.length === 0,
    issues: Object.freeze(issues),
    // Aucune date de validité contractuelle en l'absence de devis autorisé.
    validity: issues.length === 0 ? validity : null,
  });
}

module.exports = {assessAdminQuoteIssueReadiness};
