/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, operator-linebreak */
"use strict";

// Règle commerciale SPHOT ADMIN validée le 14/10/2026 :
// 30 jours CALENDAIRES à compter du jour d'émission, jour d'émission inclus.
// Une offre portant sur une année civile donnée expire au plus tard le
// 31 décembre de cette année. Aucune proratisation ne résulte de ces dates.
//
// Le module ne crée AUCUN devis : son résultat sera figé par le futur
// processus serveur de génération de devis authentifié et fiscalement validé.

const VALIDITY_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;

function parseCivilDate(value) {
  if (typeof value !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new TypeError("Date d'émission invalide (AAAA-MM-JJ).");
  }
  const [year, month, day] = value.split("-").map(Number);
  const timestamp = Date.UTC(year, month - 1, day);
  if (!Number.isFinite(timestamp) ||
      new Date(timestamp).toISOString().slice(0, 10) !== value) {
    throw new RangeError("Date d'émission impossible.");
  }
  return timestamp;
}

function quoteValidityForCalendarYear(issuedOn, subscriptionYear) {
  const issuedAtUtc = parseCivilDate(issuedOn);
  if (!Number.isSafeInteger(subscriptionYear) ||
      subscriptionYear < 2000 || subscriptionYear > 9999) {
    throw new RangeError("Année d'abonnement invalide.");
  }
  const yearEnd = Date.UTC(subscriptionYear, 11, 31);
  if (issuedAtUtc > yearEnd) {
    throw new RangeError(
        "Impossible d'émettre un devis après l'année d'abonnement concernée.",
    );
  }

  const thirtyDayLimit = issuedAtUtc + (VALIDITY_DAYS - 1) * DAY_MS;
  const expirationDay = Math.min(thirtyDayLimit, yearEnd);
  return Object.freeze({
    issuedOn,
    validUntil: new Date(expirationDay).toISOString().slice(0, 10),
    validityDaysMaximum: VALIDITY_DAYS,
    subscriptionYear,
    expiresAtYearEnd: expirationDay === yearEnd,
  });
}

module.exports = {VALIDITY_DAYS, quoteValidityForCalendarYear};
