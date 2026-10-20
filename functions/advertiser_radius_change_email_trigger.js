"use strict";

/**
 * Choisit la notification unique pour les changements d'actifs et de zone.
 * Une soumission mixte génère un seul message (actifs + rayon différé).
 *
 * @param {Object} before Ancien dossier.
 * @param {Object} after Nouveau dossier.
 * @param {boolean} assetEvent Transition déjà retenue par le circuit visuel.
 * @return {string|null} État à notifier, ou null.
 */
function advertiserChangeEmailStatus(before, after, assetEvent) {
  const oldRadius = (before || {}).radiusChangeRequest || {};
  const newRadius = (after || {}).radiusChangeRequest || {};
  if (assetEvent) {
    return ((after || {}).assetChangeRequest || {}).status || null;
  }
  if (oldRadius.status !== newRadius.status &&
      newRadius.status === "waiting_period_end") {
    return "radius_waiting";
  }
  if (oldRadius.status !== newRadius.status &&
      newRadius.status === "approved_pending_payment") {
    return "radius_approved_pending_payment";
  }
  return null;
}

module.exports = {advertiserChangeEmailStatus};
