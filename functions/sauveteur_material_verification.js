"use strict";

// Référentiel indépendant des rôles de rédaction de la main courante.
// Seule une vérification structurée peut passer par l'endpoint dédié.
const CATEGORY_LABELS = Object.freeze({
  medical: "Secours",
  phonie: "Phonie / communications",
  roulant: "Matériel roulant",
  flottant: "Matériel flottant",
});

/**
 * Contrôle la cohérence entre le formulaire matériel et la catégorie.
 * Les rôles, dates, auteurs, type et visibilité ne viennent jamais du client.
 *
 * @param {Object} requestBody Données envoyées par le formulaire.
 * @return {Object|null} Vérification recevable ou null.
 */
function validateMaterialVerification(requestBody) {
  if (!requestBody || typeof requestBody !== "object" ||
      Array.isArray(requestBody)) return null;

  const category = requestBody.verificationCategory;
  if (typeof category !== "string" ||
      !Object.hasOwn(CATEGORY_LABELS, category)) return null;

  if (typeof requestBody.description !== "string") return null;
  const description = requestBody.description.trim();
  const header = `Catégorie : ${CATEGORY_LABELS[category]}\n`;
  if (description.length > 8000 || !description.startsWith(header) ||
      description.length <= header.length) return null;

  return {category, description};
}

module.exports = {validateMaterialVerification};
