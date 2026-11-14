"use strict";

/**
 * Rejette la connexion SAUVETEUR depuis un navigateur qui transmet Origin.
 * Un vrai compte Super Admin conserve son circuit Web historique.
 *
 * Ce filtre HTTP bloque le navigateur habituel, mais Origin n'est pas une
 * attestation cryptographique d'un appareil Android.
 *
 * @param {string|undefined} origin En-tête Origin de la requête.
 * @param {boolean} isSuperAdmin Compte Super Admin vérifié par Firestore.
 * @return {boolean} True si la connexion doit être refusée.
 */
function shouldRejectSauveteurBrowserLogin(origin, isSuperAdmin) {
  if (isSuperAdmin === true) return false;
  return typeof origin === "string" && origin.trim().length > 0;
}

module.exports = {shouldRejectSauveteurBrowserLogin};
