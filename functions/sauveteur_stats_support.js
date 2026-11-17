"use strict";

const {assignedPeriodReferences, parisDayKey} =
    require("./sauveteur_main_courante_lifecycle");

/**
 * Return the identifier of the active search, or create one for a new search.
 * Never deduplicate searches by a person's name or other private details.
 * @param {?Object} previousNotification Previously published live notification.
 * @param {Function} createId Random identifier factory.
 * @return {string} The stable case identifier.
 */
function searchCaseIdForNotification(previousNotification, createId) {
  const notification = previousNotification || {};
  const priorId = notification.active === true &&
      notification.source === "recherche_personne" &&
      typeof notification.searchCaseId === "string" ?
        notification.searchCaseId.trim() : "";
  return priorId || createId();
}

/**
 * Select the union of surveillance periods assigned to a station in one year.
 * Discontinuous and overlapping periods are retained as ranges; callers
 * must use membership rather than summing each range separately.
 * @param {Object} options Station, assigned people, territory periods, year.
 * @return {Array<Object>} Inclusive Paris civil day ranges.
 */
function seasonPeriodsForStation({station, assigned, periods, year}) {
  if (!Number.isInteger(year)) return [];
  const references = assignedPeriodReferences(station || {}, assigned || []);
  const firstDay = year * 10000 + 101;
  const lastDay = year * 10000 + 1231;

  const asDate = (value) => {
    if (value && typeof value.toDate === "function") return value.toDate();
    if (value instanceof Date) return value;
    return null;
  };

  return (periods || [])
      .filter((period) => {
        const id = (period.id || "").toString().trim();
        const label = (period.label || "").toString().trim();
        const name = (period.name || "").toString().trim();
        return references.has(id) || references.has(label) ||
            references.has(name);
      })
      .map((period) => {
        const start = asDate(period.startDate);
        const end = asDate(period.endDate);
        return {
          startDay: start ? parisDayKey(start) : 0,
          endDay: end ? parisDayKey(end) : 0,
        };
      })
      .filter((period) => period.startDay > 0 &&
          period.endDay >= period.startDay &&
          period.startDay <= lastDay &&
          period.endDay >= firstDay);
}

module.exports = {
  searchCaseIdForNotification,
  seasonPeriodsForStation,
};
