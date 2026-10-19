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
 * @param {string} id Identifiant Firestore.
 * @param {Object} raw Dossier publicitaire privé.
 * @param {number} now Horodatage courant.
 * @return {Object|null} Champs strictement publics ou aucune campagne.
 */
function projectPublicMapAdvertisement(id, raw, now = Date.now()) {
  const ad = raw || {};
  if (text(ad.status).toLowerCase() !== "active") return null;

  const visibility = text(ad.visibilityType).toLowerCase();
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
          const snapshot = await admin.firestore()
              .collection("adRequests")
              .where("status", "==", "active")
              .limit(500)
              .get();

          const now = Date.now();
          const advertisements = snapshot.docs
              .map((doc) => projectPublicMapAdvertisement(
                  doc.id, doc.data(), now))
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
  registerPublicMapAdvertisingEndpoint,
};
