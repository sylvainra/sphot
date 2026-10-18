"use strict";

/**
 * Ciblage publicitaire national INDÉPENDANT du contour GeoJSON.
 *
 * Les contours Nature Earth sont dessinés uniquement dans la carte :
 * leurs approximations côtières ne doivent jamais exclure une plage.
 * Pour la diffusion, le pays est une donnée métier du SPHOT public,
 * normalisée et contrôlée lors de son enregistrement.
 *
 * Une donnée pays absente ou ambiguë doit être complétée, jamais
 * devinée par un polygone simplifié.
 */

/**
 * @param {*} value Code ISO 3166-1 alpha-3 explicite.
 * @return {string} Code normalisé, ou chaîne vide.
 */
function iso3(value) {
  const s = String(value || "").trim().toUpperCase();
  return /^[A-Z]{3}$/.test(s) && s !== "XXX" ? s : "";
}

/**
 * @param {Object} spot Spot publié avec pays métier (non cartographique).
 * @return {string} ISO3, ou chaîne vide si données insuffisantes.
 */
// Rattachement souverain pour les audiences commerciales françaises.
// Les régimes fiscaux locaux, distincts selon le territoire, NE SONT
// PAS inférés de ces codes ; ils restent du ressort d'Odoo.
const FRENCH_OVERSEAS_ISO3 = new Set([
  "GLP", "MTQ", "GUF", "REU", "MYT", "SPM",
  "PYF", "NCL", "WLF", "BLM", "MAF", "ATF",
]);
const FRENCH_OVERSEAS_NAMES = new Set([
  "GUADELOUPE", "MARTINIQUE", "GUYANE", "GUYANE FRANCAISE",
  "LA REUNION", "REUNION", "MAYOTTE", "POLYNESIE FRANCAISE",
  "NOUVELLE CALEDONIE", "WALLIS ET FUTUNA",
  "SAINT PIERRE ET MIQUELON", "SAINT BARTHELEMY",
  "TERRES AUSTRALES ET ANTARCTIQUES FRANCAISES",
]);

function spotCountry(spot) {
  if (!spot || typeof spot !== "object") return "";
  const explicit = iso3(spot.countryIso3 || spot.paysIso3);
  if (FRENCH_OVERSEAS_ISO3.has(explicit)) return "FRA";
  if (explicit) return explicit;

  // Compatibilité avec les données historiques françaises :
  // uniquement les libellés non ambigus, jamais les coordonnées.
  const label = String(spot.pays || "")
      .trim()
      .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .toUpperCase().replace(/[-']/g, " ").replace(/\s+/g, " ");
  if (["FRANCE", "FRA", "FR"].includes(label) ||
      FRENCH_OVERSEAS_NAMES.has(label)) return "FRA";
  return "";
}

/**
 * @param {Object} campaign Zone sélectionnée par l'annonceur.
 * @param {Object} spot Spot affiché/consulté par le grand public.
 * @return {boolean} Vrai pour un SPHOT du pays, même hors polygone affiché.
 */
function countryCampaignCoversSpot(campaign, spot) {
  const territory = campaign && campaign.advertisingTerritory;
  if (!territory || territory.level !== "country" ||
      territory.coverageModel !== "country_whole_v1") return false;
  const targetCountry = iso3(territory.countryIso3 || territory.code);
  const actualCountry = spotCountry(spot);
  return Boolean(targetCountry && actualCountry &&
      targetCountry === actualCountry);
}

module.exports = {iso3, spotCountry, countryCampaignCoversSpot};
