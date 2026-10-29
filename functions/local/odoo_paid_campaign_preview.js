"use strict";

// BLOC B - Simulation pure et locale uniquement.
// Ne jamais importer ce module dans une fonction publique d'activation :
// il ne constitue ni une autorisation de publication ni une preuve Odoo.
const crypto = require("node:crypto");
const {projectPublicMapAdvertisement} = require("../public_map_advertising");

/**
 * @param {*} value Date Firestore, Date JavaScript ou ISO.
 * @return {number} Horodatage ou NaN.
 */
function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}

/**
 * @param {string} reason Motif du refus.
 * @return {Object} Résultat strictement non activant.
 */
function blocked(reason) {
  return {simulationOnly: true, phase: "blocked", action: "none",
    reason, activationKey: null, publicPreview: null};
}

/**
 * Prévisualise une transition hypothétique d'une campagne déjà approuvée.
 * Le reçu de paiement doit provenir de la passerelle Odoo sécurisée :
 * un navigateur ne doit jamais utiliser cette fonction pour autoriser
 * une publication. Aucune entrée n'est modifiée, aucun appel réseau.
 *
 * @param {Object} args Dossier, reçus Odoo et campagne simulée.
 * @return {Object} Phase et action souhaitée, sans aucune écriture.
 */
function previewPaidCampaign({
  requestId, campaignId, request, order, invoice, payment, campaign,
  nowMs = Date.now(),
} = {}) {
  if (typeof requestId !== "string" ||
      !/^[a-zA-Z0-9_-]{8,128}$/.test(requestId) ||
      typeof campaignId !== "string" ||
      !/^[a-zA-Z0-9_-]{3,128}$/.test(campaignId)) {
    return blocked("identifiers_invalid");
  }
  if (!request || request.status !== "approved" ||
      request.advertisingSpotCompleted !== true ||
      request.diffusionCompleted !== true ||
      request.planningCompleted !== true ||
      !campaign || campaign.advertiserRequestId !== requestId ||
      request.diffusion?.visibilityType !== campaign.visibilityType ||
      !["draft", "inactive", "active"].includes(campaign.status)) {
    return blocked("campaign_not_approved_or_linked");
  }

  const start = millis(request.planning?.campaignStartDate);
  const end = millis(request.planning?.campaignEndDate);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start ||
      millis(campaign.campaignStartDate) !== start ||
      millis(campaign.campaignEndDate) !== end ||
      !Number.isFinite(nowMs)) {
    return blocked("planning_inconsistent");
  }

  const approvedVisual = request.approvedApplication?.visual || {};
  const approvedUrls = [approvedVisual.url, approvedVisual.webBannerUrl];
  if (!approvedUrls.includes(campaign.bannerUrl) ||
      (campaign.broadcastType === "local" &&
        (request.advertisingTerritory?.radiusKm !== campaign.radiusKm ||
        request.advertisingTerritory?.level !==
          `radius_${campaign.radiusKm}km`)) ||
      (campaign.broadcastType === "national" &&
        request.advertisingTerritory?.level !== "country")) {
    return blocked("campaign_details_inconsistent");
  }

  // Projeter la campagne hypothétiquement active à son début : la même
  // validation publique exige dates, visuel HTTPS, zone et coordonnées.
  const publicAtStart = projectPublicMapAdvertisement(campaignId,
      {...campaign, status: "active"}, start);
  if (!publicAtStart) return blocked("public_projection_invalid");

  if (!order || order.testOnly !== true || order.odooState !== "sale" ||
      !Number.isSafeInteger(order.odooOrderId) || order.odooOrderId <= 0 ||
      typeof order.reference !== "string" ||
      !order.reference.startsWith("SPHOT-PUB-") ||
      !Number.isSafeInteger(order.odooTotalCents) ||
      order.odooTotalCents <= 0 ||
      !invoice || invoice.testOnly !== true ||
      !Number.isSafeInteger(invoice.odooInvoiceId) ||
      invoice.odooInvoiceId <= 0 ||
      typeof invoice.odooInvoiceName !== "string" ||
      !invoice.odooInvoiceName.trim() ||
      invoice.state !== "posted" || invoice.paymentState !== "paid" ||
      invoice.amountTotalCents !== order.odooTotalCents ||
      invoice.amountResidualCents !== 0 ||
      invoice.odooPaymentRecorded !== true ||
      !payment || payment.paymentConfirmed !== true ||
      !Array.isArray(payment.transactions) ||
      payment.transactions.length !== 1) {
    return blocked("odoo_payment_not_verified");
  }
  const transaction = payment.transactions[0];
  if (!transaction || !Number.isSafeInteger(transaction.id) ||
      transaction.id <= 0 || !transaction.reference ||
      transaction.provider !== "stripe" || transaction.state !== "done" ||
      transaction.currency !== "EUR" || transaction.testOnly !== true ||
      transaction.amountCents !== invoice.amountTotalCents) {
    return blocked("stripe_transaction_invalid");
  }

  const fingerprint = [requestId, campaignId, order.reference,
    invoice.odooInvoiceId, transaction.id].join("|");
  const activationKey = "SPHOT-TEST-ACT-" + crypto.createHash("sha256")
      .update(fingerprint).digest("hex").slice(0, 20).toUpperCase();
  const alreadyActive = campaign.status === "active";
  if (alreadyActive && campaign.activationProofKey !== activationKey) {
    return blocked("existing_activation_unrelated");
  }
  if (nowMs >= end) {
    return {simulationOnly: true, phase: "expired",
      action: alreadyActive ? "expire" : "none", reason: "period_ended",
      activationKey, publicPreview: null};
  }
  if (nowMs < start) {
    if (alreadyActive) return blocked("active_before_start");
    return {simulationOnly: true, phase: "scheduled", action: "wait",
      reason: "start_in_future", activationKey, publicPreview: null};
  }
  const publicPreview = projectPublicMapAdvertisement(campaignId,
      {...campaign, status: "active"}, nowMs);
  if (!publicPreview) return blocked("public_projection_invalid");
  return {simulationOnly: true, phase: "active",
    action: alreadyActive ? "none" : "activate", reason: "eligible",
    activationKey, publicPreview};
}

module.exports = {previewPaidCampaign};
