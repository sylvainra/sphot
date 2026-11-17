/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Contrat de préparation SPHOT ADMIN -> Odoo (sans E/S).
// Ce module ne crée ni commande, ni facture, ni droit Firebase.
// Ses données doivent être construites par un orchestrateur serveur qui a
// relu les dossiers, les postes, la grille, la fiscalité et les CGV.

const crypto = require("node:crypto");
const {buildOdooDraft} = require("../odoo_commercial_bridge");

const ID = /^[A-Za-z0-9_-]{8,128}$/;
const SIRET = /^\d{14}$/;
const REFERENCE = /^SPHOT-ADM-TEST-[A-F0-9]{16}$/;

function refused(message) {
  const error = new Error(message);
  error.code = "ADMIN_CHECKOUT_NOT_READY";
  return error;
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function validId(value) {
  return ID.test(text(value));
}

function cents(value) {
  if (!Number.isFinite(value) || value < 0) return null;
  const scaled = value * 100;
  const rounded = Math.round(scaled);
  return Number.isSafeInteger(rounded) &&
      Math.abs(scaled - rounded) < 0.000001 ? rounded : null;
}

function referenceFor(adminUid, cycleId, year) {
  if (!validId(adminUid) || !validId(cycleId) ||
      !Number.isSafeInteger(year) || year < 2026 || year > 2100) {
    throw refused("Identifiant de cycle ADMIN invalide.");
  }
  const hash = crypto.createHash("sha256")
      .update("SPHOT_ADMIN_ODOO_TEST_V1|")
      .update(adminUid).update("|").update(cycleId)
      .update("|").update(String(year))
      .digest("hex").slice(0, 16).toUpperCase();
  return `SPHOT-ADM-TEST-${hash}`;
}

function prepareAdminCheckout({adminUid, requestId, cycleId, year,
  approval, buyer, stations, quote, fiscality, legalAcceptance,
  paymentMethod, partnerId, adminTierProductIds} = {}) {
  if (!validId(adminUid) || requestId !== adminUid ||
      !validId(cycleId) ||
      !approval || approval.status !== "approved" ||
      approval.adminUid !== adminUid ||
      !validId(approval.territoireId) ||
      !SIRET.test(text(approval.siret)) ||
      !/^\d{9}$/.test(text(approval.siren)) ||
      approval.siret.slice(0, 9) !== approval.siren) {
    throw refused("Identité administrative préalablement approuvée incohérente.");
  }
  if (!buyer || buyer.verified !== true ||
      !SIRET.test(text(buyer.siret)) ||
      !text(buyer.legalName) ||
      !text(buyer.billingEmail) ||
      !["manager", "other"].includes(buyer.relation) ||
      (buyer.relation === "manager" &&
        buyer.siret !== approval.siret) ||
      (buyer.relation === "other" &&
        buyer.thirdPartyBillingAuthorized !== true)) {
    throw refused("Organisme payeur non vérifié ou sans habilitation.");
  }
  if (!Array.isArray(stations) || stations.length === 0 ||
      stations.some((station) => !station ||
        !validId(station.spotDocumentId) ||
        station.belongsToAdminTerritory !== true ||
        station.isRescueStation !== true) ||
      new Set(stations.map((station) => station.spotDocumentId)).size !==
        stations.length) {
    throw refused("Sélection de postes non vérifiée.");
  }
  if (!quote || quote.market !== "ADMIN" ||
      quote.fromServerPublishedCatalog !== true ||
      quote.country !== "FR" || quote.currency !== "EUR" ||
      quote.numberOfRescueStations !== stations.length ||
      !Array.isArray(quote.lines) || quote.lines.length !== 4 ||
      !Number.isSafeInteger(quote.amountExclTax) ||
      !Number.isInteger(quote.discountPercent) ||
      !Number.isSafeInteger(quote.payableExclTaxCents)) {
    throw refused("Grille publiée et remise non recalculées au serveur.");
  }
  if (!fiscality || fiscality.status !== "validated" ||
      fiscality.calculationVerified !== true ||
      cents(fiscality.amountExclTax) !== quote.payableExclTaxCents ||
      cents(fiscality.taxAmount) === null ||
      cents(fiscality.amountInclTax) !==
        quote.payableExclTaxCents + cents(fiscality.taxAmount) ||
      !text(fiscality.legalBasis)) {
    throw refused("Fiscalité et montant définitif non vérifiés.");
  }
  if (!legalAcceptance || legalAcceptance.verified !== true ||
      legalAcceptance.adminUid !== adminUid ||
      !text(legalAcceptance.version) ||
      !text(legalAcceptance.acceptedAt)) {
    throw refused("Acceptation des CGV non vérifiée.");
  }
  if (!["card", "public_invoice"].includes(paymentMethod) ||
      !Number.isSafeInteger(partnerId) || partnerId < 1 ||
      !Array.isArray(adminTierProductIds) ||
      adminTierProductIds.length !== 4 ||
      new Set(adminTierProductIds).size !== 4 ||
      adminTierProductIds.some((id) => !Number.isSafeInteger(id) || id < 1)) {
    throw refused("Configuration Odoo ADMIN incomplète.");
  }

  const reference = referenceFor(adminUid, cycleId, year);
  const prepared = buildOdooDraft({quote, partnerId,
    productIds: {adminTiers: adminTierProductIds},
    sphotReference: reference});
  if (prepared.expectedUntaxedCents !== quote.payableExclTaxCents) {
    throw refused("Total du brouillon Odoo incohérent.");
  }
  const stationIds = stations.map((station) => station.spotDocumentId).sort();
  const orderLines = prepared.values.order_line.map((line) => line[2]);
  const locked = {
    adminUid, requestId, cycleId, year, reference,
    territoireId: approval.territoireId,
    managerSiret: approval.siret,
    buyerSiret: buyer.siret,
    buyerRelation: buyer.relation,
    stationIds,
    pricingReference: quote.pricingReference,
    pricingVersion: quote.version,
    baseExclTaxCents: quote.amountExclTax * 100,
    discountPercent: quote.discountPercent,
    payableExclTaxCents: quote.payableExclTaxCents,
    taxCents: cents(fiscality.taxAmount),
    totalInclTaxCents: cents(fiscality.amountInclTax),
    taxLegalBasis: fiscality.legalBasis,
    cgvVersion: legalAcceptance.version,
    cgvAcceptedAt: legalAcceptance.acceptedAt,
    paymentMethod, partnerId,
    orderLines: orderLines.map((line) => ({
      productId: line.product_id,
      quantity: line.product_uom_qty,
      priceUnit: line.price_unit,
      discount: line.discount,
    })),
  };
  const fingerprint = crypto.createHash("sha256")
      .update(JSON.stringify(locked)).digest("hex");
  return Object.freeze({
    reference, fingerprint, cycleId, year, paymentMethod,
    expectedUntaxedCents: quote.payableExclTaxCents,
    expectedTotalCents: locked.totalInclTaxCents,
    orderValues: prepared.values,
    locked: Object.freeze(locked),
    testOnly: true,
  });
}

// Le changement de statut opérationnel reste une opération serveur distincte.
// La facture n'est PAS une condition d'activation sur engagement public.
function assessActivation({prepared, order, payment, commitment} = {}) {
  if (!prepared || !REFERENCE.test(prepared.reference) ||
      !order || order.reference !== prepared.reference ||
      order.fingerprint !== prepared.fingerprint ||
      order.state !== "sale") {
    return {allowed: false, reason: "odoo_order_unverified"};
  }
  if (prepared.paymentMethod === "card") {
    if (!payment || payment.provider !== "stripe" ||
        payment.transactionState !== "done" ||
        payment.invoiceState !== "posted" ||
        payment.invoicePaymentState !== "paid" ||
        payment.amountResidualCents !== 0 ||
        payment.invoiceTotalCents !== prepared.expectedTotalCents ||
        payment.orderReference !== prepared.reference) {
      return {allowed: false, reason: "stripe_payment_unverified"};
    }
    return {allowed: true, basis: "stripe_verified", paymentStatus: "paid"};
  }
  if (prepared.paymentMethod !== "public_invoice" || !commitment ||
      commitment.status !== "verified" ||
      commitment.orderReference !== prepared.reference ||
      commitment.orderFingerprint !== prepared.fingerprint ||
      !text(commitment.documentHash) ||
      !text(commitment.verifiedAt) ||
      !text(commitment.verificationSource)) {
    return {allowed: false, reason: "public_commitment_unverified"};
  }
  return {allowed: true, basis: "verified_public_commitment",
    paymentStatus: "not_paid"};
}

module.exports = {referenceFor, prepareAdminCheckout, assessActivation};
