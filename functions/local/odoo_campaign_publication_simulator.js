"use strict";

// BLOC C1 — Simulation en mémoire, sans réseau, Firebase ni écriture Odoo.
// Ne jamais brancher ce module sur une route de publication réelle.
const {previewPaidCampaign} = require("./odoo_paid_campaign_preview");
const {secureReferenceFor} = require("./odoo_secure_checkout_client");
const {projectPublicMapAdvertisement} = require("../public_map_advertising");

/**
 * @param {*} value Date JS, ISO ou horodatage Firestore simulé.
 * @return {number} Millisecondes, ou NaN.
 */
function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}

/**
 * Mémoire privée d'un test local. Aucune donnée n'est persistée.
 * Les reçus sont fournis par des tests : cette API n'authentifie pas Odoo.
 * @return {Object} API de simulation exclusivement.
 */
function createLocalPublicationSimulator() {
  const records = new Map();
  const claimedPayments = new Map();

  /**
   * @param {Object} input Campagne fictive non encore publiée.
   * @return {void}
   */
  function register(input) {
    const {requestId, campaignId, request, campaign} = input || {};
    if (typeof campaignId !== "string" || !campaignId ||
        records.has(campaignId) || !request || !campaign ||
        !["draft", "inactive"].includes(campaign.status)) {
      throw new Error("Campagne simulée absente, déjà inscrite ou active.");
    }
    records.set(campaignId, {
      requestId, request: structuredClone(request),
      campaign: structuredClone(campaign), proofKey: null,
      finished: false, history: [],
    });
  }

  /**
   * @param {number} nowMs Date fictive de lecture de la carte.
   * @return {Array<Object>} Données publiques filtrées.
   */
  function publicAdvertisements(nowMs) {
    if (!Number.isFinite(nowMs)) return [];
    return [...records.entries()].flatMap(([id, record]) => {
      if (!record.proofKey || record.finished ||
          record.campaign.status !== "active" ||
          record.campaign.activationProofKey !== record.proofKey) return [];
      const ad = projectPublicMapAdvertisement(
          id, record.campaign, nowMs);
      return ad ? [ad] : [];
    }).sort((a, b) => a.id.localeCompare(b.id));
  }

  /**
   * Avance l'horloge : l'expiration est indépendante d'un nouveau paiement.
   * @param {number} nowMs Date fictive.
   * @return {Object} Résultat sans effet externe.
   */
  function advanceTime(nowMs) {
    if (!Number.isFinite(nowMs)) {
      throw new Error("Horodatage de simulation invalide.");
    }
    const expiredCampaignIds = [];
    for (const [id, record] of records) {
      const end = millis(record.campaign.campaignEndDate);
      if (record.finished || !Number.isFinite(end) || nowMs < end) continue;
      record.finished = true;
      if (record.proofKey) {
        record.campaign.status = "inactive";
        record.history.push({event: "expired", at: nowMs});
        expiredCampaignIds.push(id);
      }
    }
    return {simulationOnly: true, expiredCampaignIds,
      publicAdvertisements: publicAdvertisements(nowMs)};
  }

  /**
   * Relie fictivement une preuve Odoo à une campagne de la mémoire locale.
   * Aucune preuve reçue du navigateur ne peut autoriser une vraie activation.
   * @param {Object} input Reçus fictifs et date de simulation.
   * @return {Object} Transition et liste publique simulées.
   */
  function reconcile({campaignId, order, invoice, payment, nowMs} = {}) {
    const record = records.get(campaignId);
    if (!record || !Number.isFinite(nowMs)) {
      return {simulationOnly: true, phase: "blocked", action: "none",
        reason: "simulation_input_invalid", publicAdvertisements: []};
    }
    const time = advanceTime(nowMs);
    if (record.finished) {
      return {simulationOnly: true, phase: "expired",
        action: time.expiredCampaignIds.includes(campaignId) ?
          "expire" : "none", reason: "period_ended",
        publicAdvertisements: time.publicAdvertisements};
    }
    let expectedReference;
    try {
      expectedReference = secureReferenceFor(record.requestId);
    } catch (_) {
      expectedReference = null;
    }
    if (!expectedReference || order?.reference !== expectedReference) {
      return {simulationOnly: true, phase: "blocked", action: "none",
        reason: "odoo_order_unlinked", publicAdvertisements:
          publicAdvertisements(nowMs)};
    }
    const decision = previewPaidCampaign({
      requestId: record.requestId, campaignId,
      request: record.request, campaign: record.campaign,
      order, invoice, payment, nowMs,
    });
    if (decision.action === "activate") {
      // Une même facture ne peut financer deux campagnes distinctes,
      // même si une autre transaction Stripe lui était présentée.
      const paymentKey = `invoice:${invoice.odooInvoiceId}`;
      const owner = claimedPayments.get(paymentKey);
      if (owner && owner !== campaignId) {
        return {simulationOnly: true, phase: "blocked", action: "none",
          reason: "payment_already_used", publicAdvertisements:
            publicAdvertisements(nowMs)};
      }
      claimedPayments.set(paymentKey, campaignId);
      record.campaign.status = "active";
      record.campaign.activationProofKey = decision.activationKey;
      record.proofKey = decision.activationKey;
      record.history.push({event: "activated", at: nowMs});
    }
    return {simulationOnly: true, phase: decision.phase,
      action: decision.action, reason: decision.reason,
      publicAdvertisements: publicAdvertisements(nowMs)};
  }

  /**
   * @param {string} campaignId Identifiant de campagne.
   * @return {Object|null} Copie pour vérification, jamais la mémoire interne.
   */
  function inspect(campaignId) {
    const record = records.get(campaignId);
    return record ? structuredClone({campaign: record.campaign,
      history: record.history, finished: record.finished}) : null;
  }

  return {register, reconcile, advanceTime, publicAdvertisements, inspect};
}

module.exports = {createLocalPublicationSimulator};
