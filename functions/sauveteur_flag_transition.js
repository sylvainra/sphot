"use strict";

/**
 * Normalise la couleur du drapeau principal.
 * @param {*} value Valeur Firestore.
 * @return {?string} Couleur ou null.
 */
function flagColor(value) {
  const normalized = (value || "").toString().trim().toLowerCase();
  if (normalized === "green" || normalized === "vert") return "Vert";
  if (normalized === "yellow" || normalized === "jaune") return "Jaune";
  if (normalized === "red" || normalized === "rouge") return "Rouge";
  return null;
}

/**
 * Normalise la position physique du drapeau.
 * @param {*} value Valeur Firestore.
 * @return {?string} Position ou null.
 */
function flagPosition(value) {
  const normalized = (value || "").toString().trim().toLowerCase();
  if (normalized === "hisse" || normalized === "hissé") return "Hissé";
  if (normalized === "affale" || normalized === "affalé") return "Affalé";
  return null;
}

/**
 * Évalue une transition depuis l'état déjà enregistré en base.
 * Une nouvelle couleur exige un drapeau déjà affalé, puis toujours affalé.
 * L'initialisation sans état antérieur est autorisée seulement en affalant.
 *
 * @param {Object} previous Dernier liveFlag confirmé en base.
 * @param {Object} next liveFlag demandé.
 * @return {Object} Erreur éventuelle et événements à journaliser.
 */
function evaluateFlagTransition(previous, next) {
  if (!next || typeof next !== "object" || Array.isArray(next)) {
    return {error: "invalid_flag_state"};
  }
  const oldColor = flagColor(previous && previous.flagColor);
  const newColor = flagColor(next.flagColor);
  const oldPosition = flagPosition(previous && previous.flagPosition);
  const newPosition = flagPosition(next.flagPosition);

  if (!newColor || !newPosition) {
    return {error: "invalid_flag_state"};
  }

  const colorChanged = oldColor !== newColor;
  if (colorChanged &&
      (newPosition !== "Affalé" ||
       (oldPosition !== "Affalé" && oldPosition !== null))) {
    return {error: "flag_color_requires_lowered"};
  }

  const journalLines = [];
  if (colorChanged) {
    journalLines.push(
        `Couleur du drapeau : ${oldColor || "Non renseigné"} → ${newColor}`,
    );
  }
  if (oldPosition !== newPosition) {
    journalLines.push(
        `Position du drapeau : ${oldPosition || "Non renseignée"} → ${newPosition}`,
    );
  }

  const flagWasLowered = oldPosition !== "Affalé" &&
      newPosition === "Affalé";
  const flagWasRaised = oldPosition === "Affalé" &&
      newPosition === "Hissé";

  return {
    journalLines,
    flagWasLowered,
    flagWasRaised,
    loweredFlagColor: flagWasLowered ? newColor : "",
  };
}

module.exports = {evaluateFlagTransition};
