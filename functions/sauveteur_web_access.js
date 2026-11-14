"use strict";

/**
 * Contrôle de séparation des parcours Web / application à la connexion.
 * SAUVETEUR : navigateur interdit. SUPER_ADMIN : client natif interdit.
 * Ne remplace pas une attestation Android (App Check) côté serveur.
 *
 * @param {string|undefined} origin En-tête Origin de la requête HTTP.
 * @param {boolean} isSuperAdmin Compte Super Admin vérifié par Firestore.
 * @return {boolean} True si la plateforme ne correspond pas au profil.
 */
function shouldRejectSauveteurBrowserLogin(origin, isSuperAdmin) {
  const fromBrowser = typeof origin === "string" &&
      origin.trim().length > 0;
  return isSuperAdmin === true ? !fromBrowser : fromBrowser;
}

module.exports = {shouldRejectSauveteurBrowserLogin};
