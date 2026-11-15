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

  const oldPurple = previous && previous.purpleFlagActive === true;
  const oldWindsock = previous && previous.windsockActive === true;
  const newPurple = typeof next.purpleFlagActive === "boolean" ?
    next.purpleFlagActive : oldPurple;
  const newWindsock = typeof next.windsockActive === "boolean" ?
    next.windsockActive : oldWindsock;
  // Un signal complémentaire ne peut changer (activer ou retirer)
  // que si le drapeau principal était et reste affalé.
  if ((oldPurple !== newPurple || oldWindsock !== newWindsock) &&
      (oldPosition !== "Affalé" || newPosition !== "Affalé")) {
    return {error: "supplementary_requires_lowered"};
  }
  // L'horaire de surveillance est vérifié par le serveur avant écriture.
  // Aucun changement de couleur ne sera préparé hors horaires.
  const requiresOpenSurveillance =
    (oldPosition !== "Hissé" && newPosition === "Hissé") ||
    (!oldPurple && newPurple) ||
    (!oldWindsock && newWindsock);

  const journalLines = [];
  if (colorChanged) {
    journalLines.push(
        `Drapeau affalé : ${oldColor ? oldColor.toUpperCase() : "AUCUN"}` +
        ` → ${newColor.toUpperCase()}.`,
    );
  }
  if (oldPosition !== newPosition) {
    journalLines.push(`Drapeau ${newColor.toUpperCase()} ` +
        `${newPosition === "Hissé" ? "hissé" : "affalé"}.`);
  }
  if (oldPurple !== newPurple) {
    journalLines.push(`Drapeau VIOLET ` +
        `${newPurple ? "hissé" : "affalé"}.`);
  }
  if (oldWindsock !== newWindsock) {
    journalLines.push(`Manche à air ` +
        `${newWindsock ? "hissée" : "affalée"}.`);
  }

  const flagWasLowered = oldPosition !== "Affalé" &&
      newPosition === "Affalé";
  const flagWasRaised = oldPosition === "Affalé" &&
      newPosition === "Hissé";

  return {
    journalLines,
    colorChanged,
    requiresOpenSurveillance,
    flagWasLowered,
    flagWasRaised,
    loweredFlagColor: flagWasLowered ? newColor : "",
  };
}

/**
 * État visible du mât en deux groupes, sans historique ni signaux absents.
 * La fermeture programmée classe tous les signaux présents comme affalés.
 * @param {Object} state État du mât avant ou après la manœuvre.
 * @param {boolean} closure True pour la fermeture automatique.
 * @return {string} Groupes HISSÉS / AFFALÉS des signaux présents.
 */
function describeFlagMast(state, closure = false) {
  const flag = state || {};
  const color = flagColor(flag.flagColor);
  const position = flagPosition(flag.flagPosition);
  const raised = [];
  const lowered = [];

  if (color) {
    if (closure || position === "Affalé") {
      lowered.push(color.toUpperCase());
    } else if (position === "Hissé") {
      raised.push(color.toUpperCase());
    }
  }
  if (flag.purpleFlagActive === true) {
    (closure ? lowered : raised).push("VIOLET");
  }
  if (flag.windsockActive === true) {
    (closure ? lowered : raised).push("MANCHE À AIR");
  }

  const parts = [];
  if (raised.length) parts.push(`HISSÉS : ${raised.join(", ")}`);
  if (lowered.length) parts.push(`AFFALÉS : ${lowered.join(", ")}`);
  return parts.join(" • ");
}


/**
 * Une inscription synthétique par manœuvre : HISSÉ(S), AFFALÉ(S),
 * CHANGEMENT, AJOUT, RETRAIT. Le drapeau principal entraînant les autres
 * signaux au pied du mât, son affalage les récapitule ensemble.
 * Les retraits de signaux sont distincts des affalages.
 * @param {Object} previous État confirmé avant la manœuvre.
 * @param {Object} next État confirmé après la manœuvre.
 * @return {string} Description pour la main courante.
 */
function describeFlagManeuver(previous, next) {
  const before = previous || {};
  const after = next || {};
  const oldColor = flagColor(before.flagColor);
  const newColor = flagColor(after.flagColor);
  const oldPosition = flagPosition(before.flagPosition);
  const newPosition = flagPosition(after.flagPosition);
  const oldPurple = before.purpleFlagActive === true;
  const newPurple = after.purpleFlagActive === true;
  const oldWindsock = before.windsockActive === true;
  const newWindsock = after.windsockActive === true;

  const mainRaised = oldPosition !== "Hissé" &&
      newPosition === "Hissé";
  const mainLowered = oldPosition !== "Affalé" &&
      newPosition === "Affalé";
  const added = [];
  if (!oldPurple && newPurple) added.push("VIOLET");
  if (!oldWindsock && newWindsock) added.push("MANCHE À AIR");
  const raised = [];
  const lowered = [];
  const removed = [];

  // Hissage du drapeau principal : recenser les signaux qui montent
  // ensemble. L'activation seule d'un complémentaire est un AJOUT.
  if (mainRaised) {
    if (newPosition === "Hissé" && newColor) {
      raised.push(newColor.toUpperCase());
    }
    if (newPurple) raised.push("VIOLET");
    if (newWindsock) raised.push("MANCHE À AIR");
  }

  // Affaler le principal abaisse physiquement tout le groupe présent.
  // Le violet et la manche à air actifs descendent en même temps.
  if (mainLowered && newColor) {
    lowered.push(newColor.toUpperCase());
    if (newPurple) lowered.push("VIOLET");
    if (newWindsock) lowered.push("MANCHE À AIR");
  }

  // Retrait : un complémentaire enlevé du mât, pas une descente.
  if (oldPurple && !newPurple) removed.push("VIOLET");
  if (oldWindsock && !newWindsock) removed.push("MANCHE À AIR");

  const lines = [];
  if (raised.length) {
    lines.push(`${raised.length > 1 ? "HISSÉS" : "HISSÉ"} : ` +
        raised.join(", "));
  }
  if (lowered.length) {
    lines.push(`${lowered.length > 1 ? "AFFALÉS" : "AFFALÉ"} : ` +
        lowered.join(", "));
  }
  if (oldColor && newColor && oldColor !== newColor) {
    lines.push(`CHANGEMENT : ${oldColor.toUpperCase()}` +
        ` → ${newColor.toUpperCase()}`);
  }
  if (added.length) lines.push(`AJOUT : ${added.join(", ")}`);
  if (removed.length) lines.push(`RETRAIT : ${removed.join(", ")}`);
  return lines.join(" • ");
}

module.exports = {
  evaluateFlagTransition, describeFlagMast, describeFlagManeuver,
};
