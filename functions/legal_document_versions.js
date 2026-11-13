"use strict";

// Identifiants conformes à ceux présentés et enregistrés dans Flutter.
/**
 * Identifiant stable d'une version juridique publiée.
 * @param {Object} document Document juridique Firestore.
 * @param {string} fallback Version générale historique.
 * @return {string} Identifiant version/révision.
 */
function versionId(document, fallback) {
  const version = String(document?.version || "").trim() ||
      String(fallback || "").trim();
  const revision = document?.revision;
  return Number.isSafeInteger(revision) && revision >= 0 ?
    `${version}:r${revision}` : `${version}:historique`;
}

/**
 * Versions publiées de chaque texte commun.
 * @param {Object} documents Documents juridiques récupérés.
 * @param {string} fallback Version générale historique.
 * @return {Object} Versions associées aux identifiants de documents.
 * @param {Object} options Identifiants propres au profil.
 */
function snapshot(documents, fallback, options = {}) {
  const cguId = options.cguId || "cgu";
  const result = {
    [cguId]: versionId(documents.cgu, fallback),
    privacyPolicy: versionId(documents.privacyPolicy, fallback),
    rgpdNotice: versionId(documents.rgpdNotice, fallback),
  };
  if (options.charterId) {
    result[options.charterId] = versionId(documents.charter, fallback);
  }
  return result;
}

// Les anciennes versions mobiles ne transmettent pas encore ce détail :
// le serveur peut enregistrer la version réellement lue sans les bloquer.
/**
 * Vérifie les versions fournies par le client lorsqu'elles sont présentes.
 * @param {Object|undefined|null} requested Versions transmises.
 * @param {Object} current Versions actuellement publiées.
 * @return {boolean} Vrai si les versions correspondent.
 * @param {Object} options Options du controle strict.
 */
function matchesRequested(requested, current, options = {}) {
  if (requested == null) return options.required !== true;
  if (typeof requested !== "object" || Array.isArray(requested)) return false;
  return Object.keys(current).every((id) => requested[id] === current[id]);
}

module.exports = {versionId, snapshot, matchesRequested};
