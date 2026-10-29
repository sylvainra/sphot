"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

// C4 : Odoo Stripe TEST -> projet Firebase de TEST séparé, jamais SPHOT prod.
// Ce module n'effectue aucune écriture avant l'activation explicite du mode C4.
const {preparePaidCampaignSeed} = require("./odoo_paid_emulator_sync");
const {previewPaidCampaign} = require("./odoo_paid_campaign_preview");
const {secureReferenceFor} = require("./odoo_secure_checkout_client");
const {projectPublicMapAdvertisement} =
  require("../public_map_advertising");

const TEST_PROJECT_ID = "sphot-c4-test-20261029";
const PRODUCTION_PROJECT_ID = "sphot-ab80b";

/** Refuse toute destination autre que le projet de test fixé. */
function assertC4TestCloud(db) {
  if (process.env.SPHOT_C4_TEST_CLOUD_WRITES !== "true" ||
      process.env.SPHOT_C4_PROJECT_ID !== TEST_PROJECT_ID ||
      process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.GCLOUD_PROJECT !== TEST_PROJECT_ID ||
      process.env.GOOGLE_CLOUD_PROJECT !== TEST_PROJECT_ID ||
      !db || db.projectId !== TEST_PROJECT_ID ||
      db.projectId === PRODUCTION_PROJECT_ID) {
    throw new Error(
        "C4 refusé : seul le projet Firebase de test est autorisé.");
  }
}

function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}

function blocked(reason) {
  return {testOnly: true, phase: "blocked", action: "none", reason};
}

function isApprovedProjection(request, campaign) {
  if (!request || request.status !== "approved" ||
      !request.advertisingSpotCompleted || !request.diffusionCompleted ||
      !request.planningCompleted ||
      request.diffusion?.visibilityType !== campaign.visibilityType ||
      request.advertisingTerritory?.radiusKm !== campaign.radiusKm ||
      request.advertisingTerritory?.level !==
        `radius_${campaign.radiusKm}km`) return false;
  const visual = request.approvedApplication?.visual || {};
  return [visual.url, visual.webBannerUrl].includes(campaign.bannerUrl);
}

/** Service distant C4, strictement borné au projet de test explicite. */
function createC4TestCloudSync(db) {
  assertC4TestCloud(db);

  /** Réutilise exclusivement le reçu Odoo déjà vérifié par la passerelle. */
  async function sync({requestId, source, order, invoice, payment,
    nowMs = Date.now()} = {}) {
    assertC4TestCloud(db);
    const seed = preparePaidCampaignSeed(requestId, source);
    if (!order || order.reference !== secureReferenceFor(requestId)) {
      return blocked("odoo_order_unlinked");
    }
    const proof = previewPaidCampaign({requestId, campaignId: requestId,
      request: seed.request, campaign: seed.campaign,
      order, invoice, payment, nowMs});
    if (!proof.activationKey ||
        !["active", "scheduled"].includes(proof.phase)) {
      return blocked(proof.reason || "odoo_or_campaign_not_eligible");
    }
    const requestRef = db.collection("advertiserRequests").doc(requestId);
    const campaignRef = db.collection("adRequests").doc(requestId);
    const claimRef = db.collection("c4TestPaymentClaims")
        .doc(`invoice_${invoice.odooInvoiceId}`);
    const historyRef = campaignRef.collection("c4TestHistory")
        .doc(`paid_${proof.activationKey}`);
    return db.runTransaction(async (tx) => {
      const requestDoc = await tx.get(requestRef);
      const campaignDoc = await tx.get(campaignRef);
      const claimDoc = await tx.get(claimRef);
      const historyDoc = await tx.get(historyRef);

      if (claimDoc.exists &&
          (claimDoc.data().requestId !== requestId ||
            claimDoc.data().activationProofKey !== proof.activationKey)) {
        return blocked("invoice_already_claimed");
      }
      if (campaignDoc.exists) {
        const old = campaignDoc.data();
        if (old.c4TestOnly !== true ||
            old.advertiserRequestId !== requestId ||
            old.activationProofKey !== proof.activationKey ||
            old.bannerUrl !== seed.campaign.bannerUrl ||
            millis(old.campaignStartDate) !==
              millis(seed.campaign.campaignStartDate) ||
            millis(old.campaignEndDate) !==
              millis(seed.campaign.campaignEndDate)) {
          return blocked("existing_campaign_unrelated");
        }
        if (!claimDoc.exists || !historyDoc.exists) {
          return blocked("existing_campaign_without_proof");
        }
        return {testOnly: true, phase: old.status === "active" ?
          "active" : old.c4Phase, action: "none", reason: "already_recorded"};
      }
      if (requestDoc.exists && !isApprovedProjection(
          requestDoc.data(), seed.campaign)) {
        return blocked("existing_request_divergent");
      }
      if (!requestDoc.exists) {
        tx.create(requestRef, seed.request);
      }
      tx.create(campaignRef, {...seed.campaign,
        status: proof.phase === "active" ? "active" : "draft",
        c4Phase: proof.phase, c4TestOnly: true,
        c4InvoiceId: invoice.odooInvoiceId,
        activationProofKey: proof.activationKey,
        paidAtMs: nowMs});
      if (!claimDoc.exists) {
        tx.create(claimRef, {requestId,
          campaignId: requestId, activationProofKey: proof.activationKey,
          odooTransactionId: payment.transactions[0].id, at: nowMs});
      }
      if (!historyDoc.exists) {
        tx.create(historyRef, {event: "paid",
          phase: proof.phase, invoiceId: invoice.odooInvoiceId, at: nowMs});
      }
      return {testOnly: true, phase: proof.phase,
        action: proof.phase === "active" ? "activate" : "schedule"};
    });
  }

  /** Passe à active à la date prévue, puis retire la campagne à expiration. */
  async function reconcile(nowMs = Date.now()) {
    assertC4TestCloud(db);
    if (!Number.isFinite(nowMs)) throw new Error("Horodatage C4 invalide.");
    const snapshot = await db.collection("adRequests")
        .where("c4TestOnly", "==", true).get();
    const results = [];
    for (const doc of snapshot.docs) {
      const result = await db.runTransaction(async (tx) => {
        const campaignDoc = await tx.get(doc.ref);
        if (!campaignDoc.exists) return "missing";
        const campaign = campaignDoc.data();
        if (campaign.c4TestOnly !== true || !campaign.activationProofKey ||
            !Number.isSafeInteger(campaign.c4InvoiceId)) return "untrusted";
        const requestRef = db.collection("advertiserRequests")
            .doc(campaign.advertiserRequestId);
        const claimRef = db.collection("c4TestPaymentClaims")
            .doc(`invoice_${campaign.c4InvoiceId}`);
        const requestDoc = await tx.get(requestRef);
        const claimDoc = await tx.get(claimRef);
        const authorized = requestDoc.exists &&
            isApprovedProjection(requestDoc.data(), campaign) &&
            claimDoc.exists && claimDoc.data().campaignId === doc.id &&
            claimDoc.data().activationProofKey === campaign.activationProofKey;
        const start = millis(campaign.campaignStartDate);
        const end = millis(campaign.campaignEndDate);
        const phase = !authorized || !Number.isFinite(start) ||
          !Number.isFinite(end) || end <= start ? "blocked" :
          nowMs >= end ? "expired" :
          nowMs < start ? "scheduled" : "active";
        const status = phase === "active" ? "active" :
          phase === "scheduled" ? "draft" : "inactive";
        if (campaign.status === status && campaign.c4Phase === phase) {
          return "unchanged";
        }
        const historyRef = doc.ref.collection("c4TestHistory")
            .doc(`${phase}_${campaign.activationProofKey}`);
        const previousHistory = await tx.get(historyRef);
        tx.update(doc.ref, {status, c4Phase: phase,
          lastTransitionAtMs: nowMs});
        if (!previousHistory.exists) {
          tx.create(historyRef, {event: phase, at: nowMs});
        }
        return phase;
      });
      results.push({id: doc.id, result});
    }
    return results;
  }

  /** La carte ne reçoit que les données publiques validées. */
  async function publicAdvertisements(nowMs = Date.now()) {
    assertC4TestCloud(db);
    const snapshot = await db.collection("adRequests")
        .where("status", "==", "active").get();
    const projected = [];
    for (const doc of snapshot.docs) {
      const campaign = doc.data();
      if (campaign.c4TestOnly !== true || !campaign.activationProofKey ||
          !Number.isSafeInteger(campaign.c4InvoiceId)) continue;
      const request = await db.collection("advertiserRequests")
          .doc(campaign.advertiserRequestId).get();
      const claim = await db.collection("c4TestPaymentClaims")
          .doc(`invoice_${campaign.c4InvoiceId}`).get();
      if (!request.exists || !isApprovedProjection(request.data(), campaign) ||
          !claim.exists || claim.data().campaignId !== doc.id ||
          claim.data().activationProofKey !== campaign.activationProofKey) {
        continue;
      }
      const ad = projectPublicMapAdvertisement(doc.id, campaign, nowMs);
      if (ad) projected.push(ad);
    }
    return projected.sort((a, b) => a.id.localeCompare(b.id));
  }

  return {sync, reconcile, publicAdvertisements};
}

module.exports = {TEST_PROJECT_ID, assertC4TestCloud,
  createC4TestCloudSync};
