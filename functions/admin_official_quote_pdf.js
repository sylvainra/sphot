/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {simplePdfBuffer} = require("./admin_document_pdf_template");
const {assessAdminQuoteIssueReadiness} =
    require("./admin_quote_issue_readiness");

const money = (value) => Number(value).toFixed(2).replace(".", ",") + " EUR";
const clean = (value) => typeof value === "string" ? value.trim() : "";
const filled = (value) => clean(value) || "À compléter";
const address = (entity = {}) => {
  const place = [clean(entity.postalCode), clean(entity.city)]
      .filter(Boolean).join(" ");
  return [clean(entity.address), place, clean(entity.country)]
      .filter(Boolean).join(", ") || "À compléter";
};
const identity = (entity = {}) =>
  clean(entity.country) === "FR" ?
    filled(entity.siret) : filled(entity.officialId);

/**
 * Définit une seule structure documentaire pour le devis consultable
 * et le devis officiel. Les données manquantes deviennent "À compléter".
 * La fonction ne numérote, n'écrit, n'envoie et ne certifie rien.
 * Le mode officiel n'est atteignable qu'après assessAdminQuoteIssueReadiness.
 */
function adminQuoteDocumentDefinition(context = {}, {
  official = false,
  quoteNumber = "",
  administrativeReference = "",
  validity = null,
} = {}) {
  const issuer = context.issuer || {};
  const buyer = context.buyer || {};
  const stations = Array.isArray(context.stations) ? context.stations : [];
  const quote = context.publishedQuote || {};
  const tax = context.taxDecision || {};
  const rawLines = Array.isArray(quote.lines) ? quote.lines : [];
  const pricedCount = rawLines.reduce((sum, item) =>
    sum + (Number.isSafeInteger(item?.count) ? item.count : 0), 0);
  const pricedSum = rawLines.reduce((sum, item) =>
    sum + (Number.isFinite(item?.amountExclTax) ?
      item.amountExclTax : 0), 0);
  const usablePrice = quote.market === "ADMIN" &&
      quote.country === "FR" && quote.currency === "EUR" &&
      quote.fromServerPublishedCatalog === true &&
      /^FR_ADMIN-V\d+$/.test(clean(quote.pricingReference)) &&
      stations.length > 0 && pricedCount === stations.length &&
      Number.isFinite(quote.amountExclTax) &&
      pricedSum === quote.amountExclTax &&
      rawLines.length === 4 && rawLines.every((line, index) =>
        line && line.tier === index + 1 &&
        Number.isSafeInteger(line.count) && line.count >= 0 &&
        Number.isFinite(line.unitExclTax) &&
        Number.isFinite(line.amountExclTax) &&
        line.count * line.unitExclTax === line.amountExclTax);

  const lines = [
    {heading: "ÉMETTEUR"},
    {label: "Organisation", value:
      clean(issuer.legalName) || "SPHOT - raison sociale à compléter"},
    {label: "SIRET / identifiant", value: identity(issuer)},
    {label: "Adresse", value: address(issuer)},
    {label: "Email", value: filled(issuer.email)},
    {label: "TVA intracommunautaire", value:
      filled(issuer.vatNumber)},
    {heading: "ORGANISME PAYEUR"},
    {label: "Organisation", value: filled(buyer.legalName)},
    {label: "SIRET / identifiant", value: identity(buyer)},
    {label: "Adresse", value: address(buyer)},
    {label: "Contact", value: filled(buyer.billingContactName)},
    {label: "Email", value: filled(buyer.billingEmail)},
    {heading: "POSTES DE SECOURS CONCERNÉS"},
    ...(stations.length ? stations.map((station, index) => ({
      label: "Poste " + (index + 1),
      value: [clean(station.idSphot), clean(station.name)]
          .filter(Boolean).join(" - ") || "À compléter",
    })) : [{label: "Postes", value: "À renseigner"}]),
    {heading: "OFFRE ET TARIFICATION ANNUELLE"},
  ];
  if (usablePrice) {
    lines.push({label: "Grille publiée",
      value: quote.pricingReference});
    const tiers = ["Premier poste", "Du 2e au 4e poste",
      "Du 5e au 9e poste", "À partir du 10e poste"];
    rawLines.forEach((line, index) => {
      if (line.count > 0) {
        lines.push({
          label: tiers[index],
          value: line.count + " x " + money(line.unitExclTax) +
              " = " + money(line.amountExclTax),
        });
      }
    });
    lines.push({label: "TOTAL ANNUEL HT",
      value: money(quote.amountExclTax)});
  } else {
    lines.push({label: "TOTAL ANNUEL HT",
      value: "À compléter - tarif ou postes indisponibles"});
  }
  lines.push(
      {label: "TVA", value: tax.status === "validated" ?
        money(tax.taxAmount) : "À déterminer selon le régime applicable"},
      {label: "TOTAL TTC", value: tax.status === "validated" ?
        money(tax.amountInclTax) : "Non déterminé"},
      {label: "Traitement fiscal", value: filled(tax.taxTreatment)},
      {label: "Fondement fiscal", value: filled(tax.legalBasis)},
      {heading: "PÉRIODE ET CONDITIONS"},
      {label: "Abonnement", value: "Annuel par poste de secours"},
      {label: "Période", value: "Activation réelle au 31 décembre ; " +
        "renouvellement au 1er janvier, sans prorata"},
      {label: "Émission", value: official ?
        validity.issuedOn : "Non émis"},
      {label: "Validité", value: official ?
        validity.validUntil + " inclus" :
        "30 jours après émission, au plus tard le 31 décembre"},
  );

  return {
    title: "DEVIS SPHOT ADMIN",
    quoteBranding: true,
    documentNumber: official ? quoteNumber : "NON ATTRIBUÉ - SPÉCIMEN",
    requestNumber: filled(administrativeReference ||
        context.administrativeReference),
    rubric: "DEVIS ADMIN",
    statusLabel: official ? "ÉMIS" : "NON ÉMIS",
    introduction: "Devis facultatif d'abonnement annuel SPHOT ADMIN " +
        "pour les postes de secours désignés.",
    lines,
    notice: (official ? "" : "SPÉCIMEN NON CONTRACTUEL. ") +
        "Ce document ne constitue ni une commande, ni une facture, " +
        "ni un règlement ni une activation. Les informations fiscales " +
        "et contractuelles applicables sont précisées à l'engagement.",
  };
}

// Un seul moteur PDFKit et une seule charte pour les deux états.
// Ce mode est UNIQUEMENT une consultation sans DV, archive ni email.
function renderConsultableAdminQuotePdf(context = {}) {
  return simplePdfBuffer(adminQuoteDocumentDefinition(context));
}

// La validation officielle et la numérotation ne sont jamais contournées.
function renderOfficialAdminQuotePdf(context, quoteNumber,
    administrativeReference) {
  const readiness = assessAdminQuoteIssueReadiness(context);
  if (!readiness.ready) {
    const error = new Error("Devis officiel impossible : " +
        readiness.issues.join(", "));
    error.code = "QUOTE_NOT_READY";
    throw error;
  }
  if (typeof quoteNumber !== "string" ||
      !/^DV-\d{4}-\d{6}-\d{3,}$/.test(quoteNumber)) {
    throw new Error("Numéro DV officiel attribué au serveur requis.");
  }
  if (Number(quoteNumber.slice(3, 7)) !==
      Number(context.issuedOn.slice(0, 4))) {
    throw new Error("L'année du devis ne correspond pas à son émission.");
  }
  if (typeof administrativeReference !== "string" ||
      !administrativeReference.startsWith("SPHOT-ADM-")) {
    throw new Error("Référence du dossier administratif manquante.");
  }
  return simplePdfBuffer(adminQuoteDocumentDefinition(context, {
    official: true,
    quoteNumber,
    administrativeReference,
    validity: readiness.validity,
  }));
}

module.exports = {
  renderOfficialAdminQuotePdf,
  renderConsultableAdminQuotePdf,
  adminQuoteDocumentDefinition,
};
