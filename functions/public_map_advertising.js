"use strict";

/**
 * Projection publique minimale des campagnes actives destinées à la carte.
 * Aucun dossier annonceur, coordonnée de contact ni donnée de facturation
 * ne doit être renvoyé au navigateur.
 */
/**
 * @param {*} value Valeur brute.
 * @return {string} Texte nettoyé.
 */
function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * @param {*} value Adresse saisie.
 * @param {boolean} httpsOnly Exiger HTTPS pour les images.
 * @return {string} URL vérifiée ou chaîne vide.
 */
function validUrl(value, httpsOnly = false) {
  try {
    const url = new URL(text(value));
    if (url.protocol === "https:" ||
        (!httpsOnly && url.protocol === "http:")) {
      return url.toString();
    }
  } catch (_) {
    // URL absente ou mal formée : ne rien exposer.
  }
  return "";
}

/**
 * @param {*} value Date Firestore, JS ou chaîne.
 * @return {number} Horodatage ou NaN.
 */
function milliseconds(value) {
  if (value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}

/**
 * @param {*} value Nombre brut.
 * @return {number|null} Nombre fini ou null.
 */
function finiteNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const converted = Number(value);
  return Number.isFinite(converted) ? converted : null;
}

/**
 * Recoupe une campagne liée à un dossier ANNONCEUR APPROUVÉ.
 * Le site vient de la saisie annonceur, pas d'un ancien lien de test.
 * Durant un Pack de test, l'image vient du visuel approuvé du dossier.
 * Aucun changement de donnée privée ni de facturation.
 * @param {Object} campaign Campagne existante.
 * @param {Object} advertiser Dossier annonceur lié.
 * @param {number} now Date actuelle.
 * @return {Object} Campagne enrichie, champs publics seulement ensuite.
 */
function campaignWithApprovedAdvertiser(
    campaign, advertiser, now = Date.now()) {
  if (!advertiser || advertiser.status !== "approved") return campaign;
  const application = advertiser.application || {};
  const approved = advertiser.approvedApplication || {};
  const approvedVisual = approved.visual || {};
  const site = validUrl(application.destinationUrl) ||
      validUrl(advertiser.destinationUrl) ||
      validUrl(approved.destinationUrl);
  const testPack = campaign.testPack || {};
  const expiresAt = milliseconds(testPack.expiresAt);
  const packTestActive = campaign.visibilityType === "pack" &&
      Number.isFinite(expiresAt) && now < expiresAt;

  // Ne jamais utiliser proposedVisual : un visuel NON approuvé ne doit
  // pas pouvoir remplacer une publicité déjà publiée.
  const approvedBanner = packTestActive ?
      validUrl(approvedVisual.url, true) : "";
  const webBanner = validUrl(approvedVisual.webBannerUrl, true) ||
      validUrl(campaign.webBannerUrl, true);

  return {
    ...campaign,
    ...(site ? {destinationUrl: site} : {}),
    ...(approvedBanner ? {bannerUrl: approvedBanner} : {}),
    ...(webBanner ? {webBannerUrl: webBanner} : {}),
  };
}

/**
 * Prépare les campagnes publiques et leurs dossiers liés.
 * Un défaut de lecture d'un dossier ne bloque pas les autres publicités.
 * @param {Object} db Client Admin Firestore.
 * @param {Array<Object>} docs Campagnes actives.
 * @param {number} now Heure actuelle.
 * @return {Promise<Array<Object>>} Campagnes prêtes à projeter.
 */
async function campaignsWithLinkedAdvertisers(db, docs, now) {
  const requests = db.collection("advertiserRequests");
  if (typeof requests.doc !== "function") {
    return docs.map((doc) => ({
      id: doc.id, data: doc.data(),
    }));
  }
  return Promise.all(docs.map(async (doc) => {
    const ad = doc.data();
    const requestId = text(ad.advertiserRequestId);
    if (!requestId || requestId.includes("/")) {
      return {id: doc.id, data: ad};
    }
    try {
      const request = await requests.doc(requestId).get();
      if (!request.exists) return {id: doc.id, data: ad};
      return {
        id: doc.id,
        data: campaignWithApprovedAdvertiser(ad, request.data(), now),
      };
    } catch (error) {
      console.error("Lecture dossier publicitaire lié:", doc.id, error);
      return {id: doc.id, data: ad};
    }
  }));
}

/**
 * @param {string} id Identifiant Firestore.
 * @param {Object} raw Dossier publicitaire privé.
 * @param {number} now Horodatage courant.
 * @return {Object|null} Champs strictement publics ou aucune campagne.
 */
function projectPublicMapAdvertisement(id, raw, now = Date.now()) {
  const ad = raw || {};
  if (text(ad.status).toLowerCase() !== "active") return null;

  // Le Pack accordé seulement pour test revient automatiquement à
  // l'ancienne offre Carte dans l'API publique après son expiration.
  const testPack = ad.testPack || {};
  const testExpires = milliseconds(testPack.expiresAt);
  const testExpired = Number.isFinite(testExpires) && now >= testExpires;
  const visibility = testExpired &&
      text(testPack.previousVisibilityType) === "map" ?
      "map" : text(ad.visibilityType).toLowerCase();
  if (!["map", "premium", "pack"].includes(visibility)) return null;

  const startsAt = milliseconds(ad.campaignStartDate);
  const endsAt = milliseconds(ad.campaignEndDate);
  if (!Number.isFinite(startsAt) || !Number.isFinite(endsAt) ||
      now < startsAt || now >= endsAt || endsAt <= startsAt) {
    return null;
  }

  const bannerUrl = validUrl(ad.bannerUrl, true);
  if (!bannerUrl) return null;

  const scope = text(ad.broadcastType).toLowerCase();
  if (scope !== "national" && scope !== "local") return null;

  const projected = {
    id: text(id),
    advertiserName: text(ad.advertiserName),
    bannerUrl,
    ...(validUrl(ad.webBannerUrl, true) ?
      {webBannerUrl: validUrl(ad.webBannerUrl, true)} : {}),
    visibilityType: visibility,
    // L'URL déclarée par l'annonceur prévaut sur un lien hérité de campagne.
    destinationUrl: validUrl(ad.destinationUrl) || validUrl(ad.websiteUrl),
    broadcastType: scope,
    campaignEndAt: endsAt,
  };

  if (scope === "local") {
    const latitude = finiteNumber(ad.centerLat);
    const longitude = finiteNumber(ad.centerLng);
    const radiusKm = finiteNumber(ad.radiusKm);
    if (latitude === null || longitude === null || radiusKm === null ||
        latitude < -90 || latitude > 90 ||
        longitude < -180 || longitude > 180 ||
        radiusKm <= 0) {
      return null;
    }
    projected.centerLat = latitude;
    projected.centerLng = longitude;
    projected.radiusKm = radiusKm;
  }

  return projected;
}

/**
 * Endpoint GET accessible au public, sans lecture directe d'adRequests
 * depuis les règles Firestore du client.
 * @param {Object} dependencies Firebase Admin et constructeur HTTPS.
 * @return {Function} Fonction HTTPS Firebase.
 */
function registerPublicMapAdvertisingEndpoint({
  admin,
  onRequest,
  includePremium = false,
}) {
  return onRequest(
      {
        region: "europe-west1",
        cpu: 1,
        memory: "256MiB",
      },
      async (request, response) => {
        response.set("Access-Control-Allow-Origin", "*");
        response.set("Access-Control-Allow-Methods", "GET, OPTIONS");
        response.set("Cache-Control", "public, max-age=60");

        if (request.method === "OPTIONS") {
          response.status(204).send("");
          return;
        }
        if (request.method !== "GET") {
          response.status(405).json({success: false, advertisements: []});
          return;
        }

        try {
          const db = admin.firestore();
          const snapshot = await db
              .collection("adRequests")
              .where("status", "==", "active")
              .limit(500)
              .get();

          const now = Date.now();
          const campaigns = await campaignsWithLinkedAdvertisers(
              db, snapshot.docs, now);
          const advertisements = campaigns
              .map((item) => projectPublicMapAdvertisement(
                  item.id, item.data, now))
              .filter((ad) => ad !== null &&
                  (includePremium ||
                      ad.visibilityType === "map" ||
                      ad.visibilityType === "pack"))
              .sort((a, b) => a.id.localeCompare(b.id));

          response.status(200).json({success: true, advertisements});
        } catch (error) {
          console.error("Erreur diffusion publicité carte SPHOT:", error);
          response.status(500).json({success: false, advertisements: []});
        }
      },
  );
}

module.exports = {
  projectPublicMapAdvertisement,
  campaignWithApprovedAdvertiser,
  campaignsWithLinkedAdvertisers,
  registerPublicMapAdvertisingEndpoint,
};
