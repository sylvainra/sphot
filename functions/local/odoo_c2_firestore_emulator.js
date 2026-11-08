"use strict";

// BLOC C2 — UNIQUEMENT l'émulateur Firestore local demo-sphot-c2.
// Aucun accès direct à Odoo, Stripe, Firebase en ligne ou aux utilisateurs.
const {previewPaidCampaign} = require("./odoo_paid_campaign_preview");
const {secureReferenceFor} = require("./odoo_secure_checkout_client");
const {projectPublicMapAdvertisement} = require("../public_map_advertising");

const DEMO_PROJECT_ID = "demo-sphot-c2";
const EMULATOR_HOST = "127.0.0.1:8087";
const ID_PATTERN = /^[A-Za-z0-9_-]{8,128}$/;

/**
 * Refuse toute opération si l'exécution peut cibler Firebase en ligne.
 * Le SDK Admin emploie FIRESTORE_EMULATOR_HOST au lieu du réseau Firebase.
 * @return {void}
 */
function assertDemoEmulator() {
  if (process.env.FIRESTORE_EMULATOR_HOST !== EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT !== DEMO_PROJECT_ID ||
      (process.env.GOOGLE_CLOUD_PROJECT &&
        process.env.GOOGLE_CLOUD_PROJECT !== DEMO_PROJECT_ID)) {
    throw new Error("C2 refusé : émulateur Firestore demo-sphot-c2 requis.");
  }
}

/**
 * @param {Object} extra Champs facultatifs.
 * @return {Object} Réponse sans donnée privée.
 */
function blocked(extra = {}) {
  return {simulationOnly: true, phase: "blocked", action: "none", ...extra};
}

/**
 * @param {*} value Date Firestore, JS ou ISO.
 * @return {number} Millisecondes ou NaN.
 */
function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}

/**
 * @param {Object} db Firestore fourni UNIQUEMENT par l'émulateur local.
 * @return {Object} Opérations C2, sans route HTTP ni déploiement.
 */
function createC2EmulatorService(db) {
  assertDemoEmulator();
  if (!db || typeof db.runTransaction !== "function") {
    throw new Error("Client Firestore de simulation manquant.");
  }

  /**
   * @param {Object} input Identifiants et reçus Odoo entièrement fictifs.
   * @return {Promise<Object>} Transition fictive transactionnelle.
   */
  async function activate({requestId, campaignId, order, invoice, payment,
    nowMs} = {}) {
    assertDemoEmulator();
    if (!ID_PATTERN.test(requestId) || !ID_PATTERN.test(campaignId) ||
        !Number.isFinite(nowMs) || !invoice ||
        !Number.isSafeInteger(invoice.odooInvoiceId) ||
        invoice.odooInvoiceId <= 0) {
      return blocked({reason: "input_invalid"});
    }
    if (!order || order.reference !== secureReferenceFor(requestId)) {
      return blocked({reason: "odoo_order_unlinked"});
    }
    const requestRef = db.collection("advertiserRequests").doc(requestId);
    const campaignRef = db.collection("adRequests").doc(campaignId);
    const claimRef = db.collection("c2DemoPaymentClaims")
        .doc(`invoice_${invoice.odooInvoiceId}`);
    return db.runTransaction(async (tx) => {
      // Toutes les lectures avant la première écriture de la transaction.
      const requestDoc = await tx.get(requestRef);
      const campaignDoc = await tx.get(campaignRef);
      const claimDoc = await tx.get(claimRef);
      if (!requestDoc.exists || !campaignDoc.exists) {
        return blocked({reason: "campaign_or_request_missing"});
      }
      const campaign = campaignDoc.data();
      const decision = previewPaidCampaign({requestId, campaignId,
        request: requestDoc.data(), campaign, order, invoice, payment,
        nowMs});
      if (decision.action === "activate") {
        if (claimDoc.exists) {
          return blocked({reason: "invoice_already_claimed"});
        }
        const historyRef = campaignRef.collection("c2DemoHistory")
            .doc(`activated_${decision.activationKey}`);
        tx.update(campaignRef, {status: "active", c2Simulated: true,
          activationProofKey: decision.activationKey,
          c2InvoiceId: invoice.odooInvoiceId,
          activatedAtMs: nowMs});
        tx.create(claimRef, {requestId, campaignId,
          activationProofKey: decision.activationKey, at: nowMs});
        tx.create(historyRef, {event: "activated", requestId,
          activationProofKey: decision.activationKey, at: nowMs});
      } else if (decision.phase === "active") {
        // Un statut déjà actif n'est accepté que s'il est issu de C2.
        if (!campaign.c2Simulated || !claimDoc.exists ||
            claimDoc.data().campaignId !== campaignId ||
            claimDoc.data().activationProofKey !== decision.activationKey) {
          return blocked({reason: "untrusted_existing_activation"});
        }
      }
      return {simulationOnly: true, phase: decision.phase,
        action: decision.action, reason: decision.reason};
    });
  }

  /**
   * L'expiration ne nécessite ni un paiement ni une requête vers Odoo.
   * @param {Object} input Campagne et date simulées.
   * @return {Promise<Object>} Expiration fictive transactionnelle.
   */
  async function expire({campaignId, nowMs} = {}) {
    assertDemoEmulator();
    if (!ID_PATTERN.test(campaignId) || !Number.isFinite(nowMs)) {
      return blocked({reason: "input_invalid"});
    }
    const campaignRef = db.collection("adRequests").doc(campaignId);
    return db.runTransaction(async (tx) => {
      const campaignDoc = await tx.get(campaignRef);
      if (!campaignDoc.exists) return blocked({reason: "campaign_missing"});
      const campaign = campaignDoc.data();
      if (campaign.status !== "active" || !campaign.c2Simulated ||
          !campaign.activationProofKey) {
        return {simulationOnly: true, phase: "inactive", action: "none"};
      }
      const end = millis(campaign.campaignEndDate);
      if (!Number.isFinite(end)) {
        return blocked({reason: "period_invalid"});
      }
      if (nowMs < end) {
        return {simulationOnly: true, phase: "active", action: "wait"};
      }
      const historyRef = campaignRef.collection("c2DemoHistory")
          .doc(`expired_${campaign.activationProofKey}`);
      tx.update(campaignRef, {status: "inactive", expiredAtMs: nowMs});
      tx.create(historyRef, {event: "expired", at: nowMs});
      return {simulationOnly: true, phase: "expired", action: "expire"};
    });
  }

  /**
   * Projection limitée aux documents C2 et dossiers toujours approuvés.
   * @param {number} nowMs Date simulée.
   * @return {Promise<Array<Object>>} Liste publique, sans données privées.
   */
  async function publicAdvertisements(nowMs) {
    assertDemoEmulator();
    if (!Number.isFinite(nowMs)) return [];
    const docs = await db.collection("adRequests")
        .where("status", "==", "active").get();
    const published = [];
    for (const doc of docs.docs) {
      const campaign = doc.data();
      const requestId = campaign.advertiserRequestId;
      if (!campaign.c2Simulated || !campaign.activationProofKey ||
          !ID_PATTERN.test(requestId) ||
          !Number.isSafeInteger(campaign.c2InvoiceId)) continue;
      const requestDoc = await db.collection("advertiserRequests")
          .doc(requestId).get();
      if (!requestDoc.exists || requestDoc.data().status !== "approved") {
        continue;
      }
      const request = requestDoc.data();
      const approved = request.approvedApplication?.visual || {};
      if (request.diffusion?.visibilityType !== campaign.visibilityType ||
          ![approved.url, approved.webBannerUrl]
              .includes(campaign.bannerUrl)) continue;
      const claim = await db.collection("c2DemoPaymentClaims")
          .doc(`invoice_${campaign.c2InvoiceId}`).get();
      if (!claim.exists || claim.data().campaignId !== doc.id ||
          claim.data().activationProofKey !== campaign.activationProofKey) {
        continue;
      }
      const ad = projectPublicMapAdvertisement(doc.id, campaign, nowMs);
      if (ad) published.push(ad);
    }
    return published.sort((a, b) => a.id.localeCompare(b.id));
  }

  return {activate, expire, publicAdvertisements};
}

module.exports = {DEMO_PROJECT_ID, EMULATOR_HOST,
  assertDemoEmulator, createC2EmulatorService};
