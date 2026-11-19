"use strict";

// Transport INTERNE, uniquement pour les futures repetitions SPHOT/Odoo en
// environnement de test. Ne PAS l'importer dans functions/index.js.
// Aucune route HTTP, aucun deploiement, aucune connexion Stripe ou Firebase.
// Odoo Windows actuel (http://127.0.0.1:8069) n'est PAS joignable depuis
// Cloud Functions ; aucun contournement par ouverture publique n'est admis.

const {createOdooHttpsClient} = require("./odoo_https_client");
const {createVerifiedOdooDraftFromServer} =
    require("./odoo_verified_checkout_wiring");

const CLONE = "sphot_checkout_clone_neutral_20261118";

function refus(message) {
  const error = new Error(message);
  error.code = "SPHOT_ODOO_SANDBOX_CONNECTION_REFUSED";
  error.httpStatus = 503;
  return error;
}

/**
 * Fabrique un client interne TEST. Jamais de base originale ou de production.
 * Les parametres sont TOUJOURS des variables serveur, pas un body HTTP.
 * L'injection env/fetchImpl est reservee aux tests locaux de ce module.
 * @param {Object} options Dependances serveur de test.
 * @return {Object} Client Odoo et operation interne.
 */
function createOdooSandboxGateway({environment = process.env,
  fetchImpl} = {}) {
  if (!environment ||
      environment.SPHOT_ENABLE_ODOO_CHECKOUT_SANDBOX !== "true") {
    throw refus("Passerelle d'ecriture Odoo desactivee par defaut.");
  }
  if (environment.SPHOT_ODOO_DATABASE !== CLONE) {
    throw refus("Seule la copie Odoo neutralisee est autorisee.");
  }
  if (typeof environment.SPHOT_ODOO_API_KEY !== "string" ||
      !environment.SPHOT_ODOO_API_KEY.trim()) {
    throw refus("Secret Odoo serveur TEST indisponible.");
  }
  // Le client existant rejette HTTP, localhost, les adresses IP, les
  // identifiants inclus dans l'URL et les redirections.
  const client = createOdooHttpsClient({
    baseUrl: environment.SPHOT_ODOO_BASE_URL,
    database: CLONE,
    apiKey: environment.SPHOT_ODOO_API_KEY,
    ...(fetchImpl ? {fetchImpl} : {}),
  });

  return Object.freeze({
    // Expose uniquement une operation metier deja protegee par :
    // Firebase Auth, CGV versionnees, tarifs publies, verification Odoo,
    // reference de dossier/cycle et creation atomique d'un brouillon.
    createDraft: ({admin, authorization, market, requestId} = {}) =>
      createVerifiedOdooDraftFromServer({
        admin, authorization, market, requestId, odooClient: client,
      }),
  });
}

module.exports = {createOdooSandboxGateway, CLONE};
