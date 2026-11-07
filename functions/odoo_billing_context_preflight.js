"use strict";

// Preflight Odoo en lecture seule, interne aux Cloud Functions.
// Le modele Odoo doit implementer preview_billing_context avant tout usage.
// Aucun prix, partenaire, justificatif ou cycle issu du navigateur n'est admis.
// AUCUNE ecriture Firestore, commande, facture ou transaction Stripe.

const crypto = require("node:crypto");

function rejected(message) {
  const error = new Error(message);
  error.code = "SPHOT_BILLING_CONTEXT_UNVERIFIED";
  error.httpStatus = 409;
  return error;
}
function clean(x) {return typeof x === "string" ? x.trim() : "";}
function positive(x) {return Number.isSafeInteger(x) && x > 0;}
function hash(x) {return crypto.createHash("sha256")
    .update(JSON.stringify(x)).digest("hex");}

function assertPreview(preview, {market, reference, partnerId,
  quote, billingSiret, orderValues} = {}) {
  const rows = orderValues?.order_line;
  const requestedProducts = Array.isArray(rows) ?
    rows.map((row) => row?.[2]?.product_id) : [];
  if (!preview || typeof preview !== "object" ||
      Array.isArray(preview) ||
      preview.contract !== "sphot_odoo_billing_preview_v1" ||
      preview.market !== market ||
      preview.reference !== reference ||
      preview.partnerId !== partnerId ||
      preview.buyerActive !== true ||
      preview.buyerCompany !== true ||
      preview.billingAddressComplete !== true ||
      preview.currency !== "EUR" ||
      !/^[A-Z]{2}$/.test(clean(preview.buyerCountry)) ||
      !clean(preview.buyerLegalId) ||
      !positive(preview.partnerId) ||
      !positive(preview.fiscalPositionId) ||
      !Array.isArray(preview.productIds) ||
      preview.productIds.length !== requestedProducts.length ||
      preview.productIds.some((p, i) => p !== requestedProducts[i]) ||
      !Number.isSafeInteger(preview.amountUntaxedCents) ||
      !Number.isSafeInteger(preview.amountTaxCents) ||
      !Number.isSafeInteger(preview.amountTotalCents) ||
      preview.amountUntaxedCents !== quote.payableExclTaxCents ||
      preview.amountTaxCents < 0 ||
      preview.amountTotalCents !==
        preview.amountUntaxedCents + preview.amountTaxCents ||
      preview.testOnly !== false) {
    throw rejected("Retour Odoo : payeur ou fiscalite non verifies.");
  }
  if (market === "ADMIN" &&
      (preview.buyerCountry !== "FR" ||
       !/^\d{14}$/.test(clean(billingSiret)) ||
       preview.buyerSiret !== billingSiret ||
       preview.buyerLegalId !== billingSiret)) {
    throw rejected("Payeur ADMIN different du dossier de facturation.");
  }
  return Object.freeze({
    buyerCountry: preview.buyerCountry,
    buyerLegalId: preview.buyerLegalId,
    buyerSiret: clean(preview.buyerSiret),
    partnerId, fiscalPositionId: preview.fiscalPositionId,
    expectedUntaxedCents: preview.amountUntaxedCents,
    expectedTotalCents: preview.amountTotalCents,
    productIds: Object.freeze(requestedProducts.slice()),
    buyerEvidenceId: `ODOO_BUYER_${hash([reference, partnerId,
      preview.buyerLegalId, preview.buyerCountry]).slice(0, 20)}`,
    taxEvidenceId: `ODOO_TAX_${hash([reference, partnerId,
      preview.fiscalPositionId, preview.amountUntaxedCents,
      preview.amountTaxCents, preview.amountTotalCents]).slice(0, 20)}`,
  });
}

async function previewBillingFromOdoo({odooClient, identity, cycleKey,
  quote, productIds, partnerId, billingSiret, draftBuilder} = {}) {
  if (!odooClient || typeof odooClient.call !== "function" ||
      !identity || !["ADMIN", "ADVERTISER"].includes(identity.market) ||
      !/^[A-Za-z0-9_-]{8,128}$/.test(clean(identity.requestId)) ||
      !/^[A-Z0-9_-]{3,64}$/.test(clean(cycleKey)) ||
      !positive(partnerId)) {
    throw rejected("Preparation Odoo serveur incomplete.");
  }
  const market = identity.market;
  const reference = `SPHOT-${market === "ADMIN" ? "ADM" : "PUB"}-` +
    hash([market, identity.requestId, cycleKey]).slice(0, 24).toUpperCase();
  const buildOdooDraft = draftBuilder ||
    require("./odoo_commercial_bridge").buildOdooDraft;
  const draft = buildOdooDraft({quote, productIds, partnerId,
    sphotReference: reference});
  if (draft.expectedUntaxedCents !== quote.payableExclTaxCents ||
      draft.values.client_order_ref !== reference) {
    throw rejected("Devis Odoo serveur incoherent.");
  }
  const model = market === "ADMIN" ?
    "sphot.admin.checkout" : "sphot.advertiser.checkout";
  // Le method RPC est reservée au groupe passerelle Odoo.
  // Elle est censée calculer le TTC Odoo SANS creer de sale.order.
  const result = await odooClient.call(model, "preview_billing_context", {
    sphot_reference: reference,
    order_values: draft.values,
  });
  return assertPreview(result, {market, reference, partnerId,
    quote, billingSiret, orderValues: draft.values});
}

module.exports = {assertPreview, previewBillingFromOdoo};
