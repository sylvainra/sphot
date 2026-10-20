"use strict";

/**
 * Règle autonome du renouvellement publicitaire.
 * Aucune donnée de campagne active n'est modifiée dans ce module.
 */
const INACTIVE = new Set(["deleted", "cancelled", "canceled", "rejected"]);

/**
 * Convertit les timestamps Firestore et dates en millisecondes.
 * @param {unknown} value Date, timestamp ou texte ISO.
 * @return {number} Instant ou NaN si absent.
 */
function timestampMs(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value && typeof value.seconds === "number") {
    return value.seconds * 1000;
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}

/**
 * @param {Array<Object>} campaigns Campagnes liées au dossier authentifié.
 * @param {number} now Instant serveur.
 * @return {{eligible:boolean, reason:string, endAt:number|null}}
 */
function evaluateRenewal(campaigns, now = Date.now()) {
  const relevant = campaigns.filter((item) =>
    !INACTIVE.has(String(item.status || "").toLowerCase()));
  if (relevant.length === 0) {
    return {eligible: false, reason: "no_linked_campaign", endAt: null};
  }
  let lastEnd = -Infinity;
  for (const item of relevant) {
    const start = timestampMs(item.campaignStartDate);
    const end = timestampMs(item.campaignEndDate);
    if (!Number.isFinite(start) || !Number.isFinite(end) ||
        end <= start) {
      return {eligible: false, reason: "invalid_campaign_period", endAt: null};
    }
    lastEnd = Math.max(lastEnd, end);
  }
  return {
    eligible: now >= lastEnd,
    reason: now >= lastEnd ? "period_finished" : "period_in_progress",
    endAt: lastEnd,
  };
}

const RADIUS = Object.freeze({
  radius_5km: 5,
  radius_15km: 15,
  radius_50km: 50,
  radius_150km: 150,
  radius_300km: 300,
});

/**
 * Canonise un rayon demandé : ne jamais accepter un rayon libre du client.
 * @param {Object} value Proposition reçue.
 * @return {Object} Zone canonique.
 */
function validateRenewalTerritory(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("TERRITORY_INVALID");
  }
  const level = String(value.level || "");
  if (Object.prototype.hasOwnProperty.call(RADIUS, level)) {
    return {
      level,
      code: "WORLD_" + level,
      name: RADIUS[level] + " km",
      radiusKm: RADIUS[level],
      coverageModel: "worldwide_radius_v2",
    };
  }
  // Une couverture nationale requiert un territoire déjà établi pour
  // éviter d'accepter un code de pays arbitraire depuis le navigateur.
  throw new Error("TERRITORY_NOT_SUPPORTED");
}

module.exports = {evaluateRenewal, validateRenewalTerritory, timestampMs};
