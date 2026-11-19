"use strict";

// Raccordement INTERNE des briques serveur SPHOT vers la creation d'un
// brouillon Odoo atomique. Aucun export Firebase HTTP, aucun deploiement.
// Les tarifs viennent exclusivement des grilles publiees dans Firestore :
// commercialPricingMarkets/FR_ADMIN et /FR_ADVERTISER_RADIUS.
// Le navigateur NE fournit ni devis, ni prepared, ni client Odoo, ni tarif.
// Les controles d'identite, CGV et fiscalite restent dans les services
// existants. Aucun paiement, facture, email ni droit commercial ici.

const {prepareCheckoutFromFirestore} =
    require("./odoo_checkout_verified_preparation");
const {createOrResumeVerifiedCheckout} =
    require("./odoo_checkout_orchestrator");

function refuser(message) {
  const error = new Error(message);
  error.httpStatus = 503;
  error.code = "SPHOT_ODOO_CHECKOUT_WIRING_UNAVAILABLE";
  return error;
}

/**
 * Cree ou reprend un brouillon apres verification du dossier et du tarif
 * PUBLIE depuis Firestore. Le client Odoo est fourni par le serveur,
 * jamais par l'appelant Flutter/Web. Ne pas exposer directement en HTTP.
 *
 * @param {Object} opts Dependances exclusivement serveur.
 * @return {Promise<Object>} Recu de commande non payee, sans droits actifs.
 */
async function createVerifiedOdooDraftFromServer({
  admin, authorization, market, requestId, odooClient,
} = {}) {
  if (!admin || typeof admin.auth !== "function" ||
      typeof admin.firestore !== "function" ||
      !odooClient || typeof odooClient.call !== "function") {
    throw refuser("Dependances de facturation serveur indisponibles.");
  }

  return createOrResumeVerifiedCheckout({
    admin, authorization, market, requestId, odooClient,
    prepareFromServer: ({identity, db, admin: firebaseAdmin}) =>
      prepareCheckoutFromFirestore({
        identity, db, admin: firebaseAdmin,
      }),
  });
}

module.exports = {createVerifiedOdooDraftFromServer};
