"use strict";

const {localClock} = require("./sauveteur_surveillance_schedule");

const PARIS = "Europe/Paris";
const PAGE_SIZE = 350;

/**
 * Day of an instant in Paris, independent of the server's UTC offset.
 * @param {Date} date Absolute instant.
 * @return {number} YYYYMMDD.
 */
function parisDayKey(date) {
  const value = localClock(date, PARIS);
  return value.year * 10000 + value.month * 100 + value.day;
}

/**
 * Convert a Firestore timestamp, Date or ISO string to a valid Date.
 * @param {*} value Input.
 * @return {?Date} Date or null.
 */
function asDate(value) {
  const date = value && typeof value.toDate === "function" ?
    value.toDate() : value instanceof Date ? value : new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

/**
 * The main courante is always partitioned by the Paris civil year.
 * On January 1st, 00:00 Paris is December 31st, 23:00 UTC (CET).
 * @param {Date} now Absolute current time.
 * @return {Object} Start/end instants and year.
 */
function parisCivilYear(now = new Date()) {
  const year = localClock(now, PARIS).year;
  return {
    year,
    start: new Date(Date.UTC(year - 1, 11, 31, 23)),
    end: new Date(Date.UTC(year, 11, 31, 23)),
  };
}

/**
 * Only the assigned periods for this particular rescue station are used.
 * Spot-level references are a legacy fallback when no assignments remain.
 * @param {Object} spot Rescue station.
 * @param {Array<Object>} assigned Station's assigned rescuers.
 * @return {Set<string>} Period IDs and labels.
 */
function assignedPeriodReferences(spot, assigned) {
  const references = new Set();
  for (const person of assigned) {
    const values = Array.isArray(person.periodesSurveillance) ?
      person.periodesSurveillance : [];
    for (const value of values) {
      const normalized = (value || "").toString().trim();
      if (normalized) references.add(normalized);
    }
  }
  if (references.size === 0) {
    for (const field of ["periodesSurveillanceIds",
      "periodesSurveillance"]) {
      const values = Array.isArray(spot[field]) ? spot[field] : [];
      for (const value of values) {
        const normalized = (value || "").toString().trim();
        if (normalized) references.add(normalized);
      }
    }
  }
  return references;
}

/**
 * The Admin's endDate is INCLUSIVE: the journal closes at 00:00 on the
 * following day, never at 00:00 on the last surveillance day itself.
 * The daily opening hours do not shorten the journal's season.
 *
 * @param {Object} spot Station.
 * @param {Array<Object>} assigned Assigned rescuers.
 * @param {Array<Object>} periods Territory's Admin periods.
 * @param {Date} now Absolute time.
 * @return {Object} Whether a journal can still be changed.
 */
function mainCouranteLifecycle(
    spot, assigned, periods, now = new Date()) {
  const todayKey = parisDayKey(now);
  const civilYear = Math.floor(todayKey / 10000);
  const references = assignedPeriodReferences(spot || {}, assigned || []);
  let firstDay = null;
  let lastDay = null;

  for (const period of periods || []) {
    const id = (period.id || "").toString().trim();
    const label = (period.label || period.name || "").toString().trim();
    if (!references.has(id) && !references.has(label)) continue;
    const start = asDate(period.startDate);
    const end = asDate(period.endDate);
    if (!start || !end) continue;
    const startKey = parisDayKey(start);
    const endKey = parisDayKey(end);
    if (startKey > endKey) continue;
    // No future-year period may prolong an earlier year's journal.
    if (Math.floor(startKey / 10000) > civilYear ||
        Math.floor(endKey / 10000) < civilYear) continue;
    firstDay = firstDay === null ? startKey : Math.min(firstDay, startKey);
    lastDay = lastDay === null ? endKey : Math.max(lastDay, endKey);
  }

  const writable = firstDay !== null &&
    todayKey >= firstDay && todayKey <= lastDay;
  return {
    writable,
    closed: lastDay !== null && todayKey > lastDay,
    lastSurveillanceDay: lastDay,
  };
}

/**
 * Server-side lifecycle for one territorial station (no client-supplied
 * closing date is trusted).
 * @param {Object} db Firestore.
 * @param {string} territoireId Authenticated territory.
 * @param {string} spotId Authenticated assigned station.
 * @param {Date} now Clock.
 * @return {Promise<Object>} Lifecycle.
 */
async function loadMainCouranteLifecycle(
    db, territoireId, spotId, now = new Date()) {
  const territory = db.collection("territoires").doc(territoireId);
  const station = territory.collection("spots").doc(spotId);
  const [spot, assigned, periods] = await Promise.all([
    station.get(),
    station.collection("sauveteursAffectes").get(),
    territory.collection("periodesSurveillance").get(),
  ]);
  if (!spot.exists) {
    return {writable: false, closed: true, lastSurveillanceDay: null};
  }
  return mainCouranteLifecycle(
      spot.data() || {},
      assigned.docs.map((doc) => doc.data() || {}),
      periods.docs.map((doc) => ({...doc.data(), id: doc.id})),
      now,
  );
}

/**
 * Clamp every read to the CURRENT Paris calendar year. This guarantees
 * expired journals are unreadable on January 1 even before physical purge
 * finishes, and prevents queries from reaching a future year's entries.
 * @param {Object} requestBody Read request.
 * @param {Date} now Absolute time.
 * @return {Object} Millisecond bounds (end exclusive), or empty.
 */
function mainCouranteReadBounds(requestBody = {}, now = new Date()) {
  const year = parisCivilYear(now);
  let from = year.start.getTime();
  let until = year.end.getTime();
  const requestedStart = Number(requestBody.dayStartMillis);
  const requestedEnd = Number(requestBody.dayEndMillis);
  if (Number.isFinite(requestedStart) &&
      Number.isFinite(requestedEnd) &&
      requestedEnd > requestedStart) {
    from = Math.max(from, requestedStart);
    until = Math.min(until, requestedEnd);
  }
  return {from, until, empty: from >= until};
}

/**
 * Delete matching old documents in bounded batches until none remain.
 * The query uses a single, already indexed timestamp field.
 * @param {Object} db Firestore.
 * @param {Object} collection Firestore collection reference.
 * @param {string} timestampField Timestamp field name.
 * @param {Object} cutoff Firestore Timestamp.
 * @return {Promise<number>} Number of deleted documents.
 */
async function purgeCollectionBefore(db, collection, timestampField, cutoff) {
  let deleted = 0;
  for (;;) {
    const page = await collection
        .where(timestampField, "<", cutoff)
        .limit(PAGE_SIZE)
        .get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
    deleted += page.docs.length;
    if (page.docs.length < PAGE_SIZE) break;
  }
  return deleted;
}

/**
 * Trigger on January 1st, Paris midnight, and retry on subsequent first
 * days of month. Never delete entries from the current calendar year.
 * Audit and view histories are deleted along with journal entries.
 * @param {Object} db Firestore.
 * @param {Object} admin Firebase Admin SDK.
 * @param {Date} now Clock.
 * @return {Promise<Object>} Deleted counts.
 */
async function purgeExpiredMainCourante(db, admin, now = new Date()) {
  const currentYear = parisCivilYear(now);
  const cutoff = admin.firestore.Timestamp.fromDate(currentYear.start);
  const counts = {year: currentYear.year, entries: 0, edits: 0, views: 0};

  const territories = await db.collection("territoires").listDocuments();
  for (const territory of territories) {
    const stations = await territory.collection("spots").listDocuments();
    for (const station of stations) {
      counts.entries += await purgeCollectionBefore(
          db, station.collection("mainCourante"), "occurredAt", cutoff);
    }
  }
  counts.edits += await purgeCollectionBefore(
      db, db.collection("mainCouranteAuditLogs"), "createdAt", cutoff);
  counts.views += await purgeCollectionBefore(
      db, db.collection("mainCouranteAccessLogs"), "viewedAt", cutoff);

  return counts;
}

module.exports = {
  parisDayKey,
  parisCivilYear,
  assignedPeriodReferences,
  mainCouranteLifecycle,
  loadMainCouranteLifecycle,
  mainCouranteReadBounds,
  purgeExpiredMainCourante,
};
