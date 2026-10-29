"use strict";

// C3 — Raccordement du paiement Odoo RÉEL (Stripe TEST, base neutralisée)
// à un Firestore ÉMULÉ. Jamais de publication Firebase en ligne.
const {previewPaidCampaign} = require("./odoo_paid_campaign_preview");
const {assertDemoEmulator, createC2EmulatorService} =
  require("./odoo_c2_firestore_emulator");

const IDS = /^[A-Za-z0-9_-]{8,128}$/;

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
 * Retient uniquement les éléments publiables d'un dossier déjà approuvé.
 * La zone nationale reste bloquée jusqu'au support du pays par la carte.
 * @param {string} requestId Identifiant exact du dossier Odoo/SPHOT.
 * @param {Object} source Dossier lu côté serveur Firebase, jamais le client.
 * @return {Object} Deux documents publics minimaux de test.
 */
function preparePaidCampaignSeed(requestId, source) {
  if (!IDS.test(requestId) || !source || source.status !== "approved" ||
      source.advertisingSpotCompleted !== true ||
      source.diffusionCompleted !== true ||
      source.planningCompleted !== true) {
    throw new Error("Dossier annonceur réel incomplet ou non approuvé.");
  }
  const territory = source.advertisingTerritory || {};
  const spot = source.advertisingSpot || {};
  const approved = source.approvedApplication || {};
  const visual = approved.visual || {};
  const planning = source.planning || {};
  const visibilityType = source.diffusion?.visibilityType;
  const radiusKm = territory.radiusKm;
  const latitude = spot.latitude;
  const longitude = spot.longitude;
  const bannerUrl = spot.bannerUrl || visual.url;
  const startsAt = millis(planning.campaignStartDate);
  const endsAt = millis(planning.campaignEndDate);
  if (territory.level !== `radius_${radiusKm}km` ||
      !["map", "premium", "pack"].includes(visibilityType) ||
      ![5, 15, 50, 150, 300].includes(radiusKm) ||
      !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
      !Number.isFinite(startsAt) || !Number.isFinite(endsAt) ||
      endsAt <= startsAt || typeof bannerUrl !== "string" ||
      !bannerUrl.startsWith("https://")) {
    throw new Error("Zone, période ou visuel du dossier non publiable.");
  }
  const request = {
    status: "approved", advertisingSpotCompleted: true,
    diffusionCompleted: true, planningCompleted: true,
    diffusion: {visibilityType},
    advertisingTerritory: {level: territory.level, radiusKm},
    advertisingSpot: {bannerUrl},
    // saveSpot a contrôlé côté serveur l'URL du visuel réellement choisi.
    // Dans la base démo, ce visuel confirmé devient l'unique visuel admis.
    approvedApplication: {visual: {
      url: bannerUrl,
      webBannerUrl: typeof visual.webBannerUrl === "string" ?
        visual.webBannerUrl : "",
    }},
    planning: {campaignStartDate: planning.campaignStartDate,
      campaignEndDate: planning.campaignEndDate},
  };
  const establishment = source.establishment || {};
  const application = source.application || {};
  const campaign = {
    status: "draft", advertiserRequestId: requestId,
    visibilityType, broadcastType: "local",
    centerLat: latitude, centerLng: longitude, radiusKm,
    campaignStartDate: planning.campaignStartDate,
    campaignEndDate: planning.campaignEndDate,
    bannerUrl, advertiserName: String(
        establishment.businessName || source.advertiserName || "").trim(),
    destinationUrl: String(application.destinationUrl ||
        approved.destinationUrl || source.destinationUrl || "").trim(),
  };
  return {request, campaign};
}

/**
 * @param {Object} db Firestore émulateur, déjà verrouillé sur demo-sphot-c2.
 * @return {Object} Raccordement sans contact Odoo ni données fictives.
 */
function createPaidEmulatorSync(db) {
  const emulator = createC2EmulatorService(db);

  /**
   * @param {Object} input Dossier serveur + réponse réellement lue d'Odoo.
   * @return {Promise<Object>} Publication seulement dans l'émulateur.
   */
  async function sync({requestId, source, order, invoice, payment,
    nowMs = Date.now()} = {}) {
    assertDemoEmulator();
    // Rien n'est écrit avant une preuve Odoo et un dossier valides.
    const seed = preparePaidCampaignSeed(requestId, source);
    const campaignId = requestId;
    const decision = previewPaidCampaign({requestId, campaignId,
      ...seed, order, invoice, payment, nowMs});
    if (decision.action !== "activate") {
      return {simulationOnly: true, phase: decision.phase,
        action: "none", reason: decision.reason};
    }
    const requestRef = db.collection("advertiserRequests").doc(requestId);
    const campaignRef = db.collection("adRequests").doc(campaignId);
    await db.runTransaction(async (tx) => {
      const storedRequest = await tx.get(requestRef);
      const storedCampaign = await tx.get(campaignRef);
      if (!storedRequest.exists) tx.create(requestRef, seed.request);
      if (!storedCampaign.exists) tx.create(campaignRef, seed.campaign);
      if (storedCampaign.exists) {
        const current = storedCampaign.data();
        if (current.advertiserRequestId !== requestId ||
            !["draft", "inactive", "active"].includes(current.status) ||
            current.bannerUrl !== seed.campaign.bannerUrl ||
            millis(current.campaignStartDate) !==
              millis(seed.campaign.campaignStartDate) ||
            millis(current.campaignEndDate) !==
              millis(seed.campaign.campaignEndDate)) {
          throw new Error("Campagne locale divergente : aucune écriture.");
        }
      }
    });
    return emulator.activate({requestId, campaignId,
      order, invoice, payment, nowMs});
  }

  return {sync, publicAdvertisements: emulator.publicAdvertisements,
    expire: emulator.expire};
}

module.exports = {preparePaidCampaignSeed, createPaidEmulatorSync};
