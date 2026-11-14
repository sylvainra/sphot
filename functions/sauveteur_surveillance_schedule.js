"use strict";

const DEFAULT_LEGACY_TIME_ZONE = "Europe/Paris";

/**
 * Horloge locale d'un instant pour un fuseau IANA.
 * @param {Date} instant Horodatage absolu.
 * @param {string} timeZone Fuseau légal de la période.
 * @return {Object} Champs du jour et heure locale.
 */
function localClock(instant, timeZone) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(instant);
  const result = {};
  for (const part of parts) {
    if (part.type !== "literal") result[part.type] = Number(part.value);
  }
  return {
    year: result.year,
    month: result.month,
    day: result.day,
    hour: result.hour,
    minute: result.minute,
  };
}

/**
 * Reconstitue un UTC depuis l'heure locale du fuseau (été/hiver).
 * @param {Object} clock Jour et heure locale.
 * @param {string} timeZone Fuseau IANA.
 * @return {?Date} Instant, ou null si l'heure n'existe pas.
 */
function localToInstant(clock, timeZone) {
  const target = Date.UTC(
      clock.year, clock.month - 1, clock.day, clock.hour, clock.minute,
  );
  let candidate = target;
  for (let attempt = 0; attempt < 5; attempt++) {
    const observed = localClock(new Date(candidate), timeZone);
    const observedMillis = Date.UTC(
        observed.year, observed.month - 1, observed.day,
        observed.hour, observed.minute,
    );
    const difference = target - observedMillis;
    if (difference === 0) return new Date(candidate);
    candidate += difference;
  }
  return null;
}

/**
 * Heure Admin : format HH:mm ou ancien HHhmm, même journée.
 * @param {*} input Chaîne Firestore.
 * @return {?number} Minute depuis minuit.
 */
function minutes(input) {
  const match = /^(\d{1,2})[:hH](\d{2})$/.exec(
      (input || "").toString().trim(),
  );
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour < 24 && minute < 60 ? hour * 60 + minute : null;
}

/**
 * Évalue uniquement les périodes Admin affectées au poste, pas celles de
 * la commune entière. À la fin de la plage, l'état devient fermé.
 * Les anciens documents sans fuseau utilisent Europe/Paris (migration).
 *
 * @param {Object} spot Poste territorial et listes d'affectation.
 * @param {Array<Object>} periods Périodes administratives de la commune.
 * @param {Date} now Instant courant.
 * @return {Object} Ouverture et échéance UTC.
 */
function surveillanceWindow(spot, periods, now = new Date()) {
  const assignedLabels = new Set(
      Array.isArray(spot.periodesSurveillance) ?
        spot.periodesSurveillance.map((value) => value.toString().trim()) : [],
  );
  const assignedIds = new Set(
      Array.isArray(spot.periodesSurveillanceIds) ?
        spot.periodesSurveillanceIds.map((value) => value.toString().trim()) :
        [],
  );
  let configured = false;
  let open = false;
  let closesAt = null;

  for (const period of periods) {
    const label = (period.label || period.name || "").toString().trim();
    const id = (period.id || "").toString().trim();
    if (!assignedLabels.has(label) && !assignedIds.has(id)) continue;
    configured = true;

    const timeZone = (period.timeZone || spot.timeZone ||
      DEFAULT_LEGACY_TIME_ZONE).toString();
    const start = minutes(period.startHour);
    const end = minutes(period.endHour);
    if (start === null || end === null || end <= start) continue;

    const startDate = period.startDate &&
      typeof period.startDate.toDate === "function" ?
      period.startDate.toDate() : new Date(period.startDate);
    const endDate = period.endDate &&
      typeof period.endDate.toDate === "function" ?
      period.endDate.toDate() : new Date(period.endDate);
    if (!Number.isFinite(startDate.getTime()) ||
        !Number.isFinite(endDate.getTime())) continue;

    try {
      const today = localClock(now, timeZone);
      const startDay = localClock(startDate, timeZone);
      const endDay = localClock(endDate, timeZone);
      const dateCode = (value) =>
        value.year * 10000 + value.month * 100 + value.day;
      if (dateCode(today) < dateCode(startDay) ||
          dateCode(today) > dateCode(endDay)) continue;

      const minuteOfDay = today.hour * 60 + today.minute;
      if (minuteOfDay < start || minuteOfDay >= end) continue;

      const closingTime = localToInstant({
        year: today.year,
        month: today.month,
        day: today.day,
        hour: Math.floor(end / 60),
        minute: end % 60,
      }, timeZone);
      if (!closingTime) continue;

      open = true;
      if (!closesAt || closingTime.getTime() > closesAt.getTime()) {
        closesAt = closingTime;
      }
    } catch (_) {
      // Fuseau invalide : ne pas autoriser une ouverture implicite.
    }
  }

  return {configured, open, closesAt};
}

module.exports = {
  DEFAULT_LEGACY_TIME_ZONE,
  localClock,
  surveillanceWindow,
};
