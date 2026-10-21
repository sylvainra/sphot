/* eslint-disable max-len, indent, comma-dangle, brace-style, operator-linebreak, object-curly-spacing, quote-props */
"use strict";

// No price, billing status, approval decision or radius update is accepted.
const VALID_DURATIONS = new Map([
  ["1 semaine", ["days", 7]], ["2 semaines", ["days", 14]],
  ["1 mois", ["months", 1]], ["2 mois", ["months", 2]],
  ["6 mois", ["months", 6]], ["1 an", ["months", 12]],
]);
const VALID_VISIBILITY = new Map([
  ["map", "CARTE SPHOT · 1 emplacement"],
  ["premium", "FICHES SPHOT - 1 à 6 emplacements"],
  ["pack", "PACK VISIBILITÉ TOTALE - 7 emplacements maxi"],
]);

/**
 * Rejects a request without returning private data.
 * @param {number} code HTTP status.
 * @param {string} message Public error message.
 * @return {Error} Tagged error.
 */
function fail(code, message) {
  const e = new Error(message);
  e.httpStatus = code;
  return e;
}

/**
 * A scalar Firestore field expressed as a finite coordinate.
 * @param {*} value Incoming value.
 * @param {number} limit Absolute coordinate maximum.
 * @return {number} Validated coordinate.
 */
function coordinate(value, limit) {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      Math.abs(value) > limit) {
    throw fail(400, "Coordonnées invalides.");
  }
  return value;
}

/**
 * The UI only lets advertisers save unpublished commercial preparation.
 * @param {Object} data Current database data.
 * @return {boolean} Whether an agreement locks the commercial choices.
 */
function commercialLocked(data) {
  const subscription = data.subscription || {};
  const payment = data.payment || {};
  const order = data.order || {};
  return data.orderCompleted === true ||
    data.quoteOrderCompleted === true ||
    data.campaignActivated === true ||
    ["active", "paid", "trial", "overdue"].includes(
        String(subscription.status || "").toLowerCase()) ||
    ["paid", "succeeded"].includes(
        String(payment.status || "").toLowerCase()) ||
    ["accepted", "signed", "paid", "confirmed"].includes(
        String(order.status || "").toLowerCase());
}

/**
 * Validates an image URL without trusting the provided filename.
 * @param {*} raw URL from advertiser.
 * @param {string} requestId Owner of banner.
 * @param {string} approvedUrl Previously approved visual.
 * @return {string} Validated URL.
 */
function validVisualUrl(raw, requestId, approvedUrl) {
  if (typeof raw !== "string" || raw.length > 2048) {
    throw fail(400, "Visuel invalide.");
  }
  let url;
  try {
    url = new URL(raw);
  } catch (_) {
    throw fail(400, "Adresse du visuel invalide.");
  }
  if (url.protocol !== "https:") {
    throw fail(400, "Visuel HTTPS requis.");
  }
  if (raw === approvedUrl) return raw;
  const path = decodeURIComponent(url.pathname);
  const prefix = `/v0/b/sphot-ab80b.firebasestorage.app/o/` +
      `advertising_banners/${requestId}/`;
  if (url.hostname !== "firebasestorage.googleapis.com" ||
      !path.startsWith(prefix) ||
      !/^banner_[0-9]+\.(jpg|jpeg|png|webp)$/.test(
          path.split("/").at(-1))) {
    throw fail(400, "Le visuel ne provient pas du dossier annonceur.");
  }
  return raw;
}

/**
 * Only the documented territory choices may be written.
 * @param {*} value Territory supplied by Flutter.
 * @return {Object} Territory with server-controlled fields.
 */
function validTerritory(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw fail(400, "Zone publicitaire absente.");
  }
  const level = String(value.level || "");
  const supported = new Map([
    ["radius_5km", 5], ["radius_15km", 15],
    ["radius_50km", 50], ["radius_150km", 150],
    ["radius_300km", 300],
  ]);
  if (supported.has(level)) {
    const radius = supported.get(level);
    return {
      level, code: `WORLD_${level}`, name: `${radius} km`,
      radiusKm: radius, coverageModel: "worldwide_radius_v2",
    };
  }
  const country = String(value.countryIso3 || value.code || "");
  const name = String(value.name || "").trim();
  if (level !== "country" || !/^[A-Z]{3}$/.test(country) ||
      name.length < 2 || name.length > 100) {
    throw fail(400, "Zone publicitaire invalide.");
  }
  return {
    level: "country", code: country, countryIso3: country, name,
    coverageModel: "country_whole_v1",
    boundarySource: "Natural Earth (indicative 1:110m)",
  };
}

/**
 * Returns the end of the reserved period using a UTC calendar day.
 * @param {string} day YYYY-MM-DD start date.
 * @param {string} label UI duration label.
 * @param {Date} current Server clock.
 * @return {{start: Date, end: Date}} Dates.
 */
function calculatePlanning(day, label, current) {
  const duration = VALID_DURATIONS.get(label);
  if (!duration || typeof day !== "string" ||
      !/^\d{4}-\d\d-\d\d$/.test(day)) {
    throw fail(400, "Durée ou date invalide.");
  }
  const start = new Date(`${day}T12:00:00.000Z`);
  if (!Number.isFinite(start.getTime()) ||
      start.toISOString().slice(0, 10) !== day) {
    throw fail(400, "Date de début invalide.");
  }
  const today = new Date(Date.UTC(current.getUTCFullYear(),
      current.getUTCMonth(), current.getUTCDate(), 0, 0, 0));
  if (start.getTime() < today.getTime()) {
    throw fail(400, "La campagne doit débuter aujourd'hui ou plus tard.");
  }
  const end = new Date(start);
  if (duration[0] === "days") {
    end.setUTCDate(end.getUTCDate() + duration[1]);
  } else {
    const targetYear = start.getUTCFullYear();
    const targetMonth = start.getUTCMonth() + duration[1];
    const first = new Date(Date.UTC(targetYear, targetMonth, 1, 12));
    const last = new Date(Date.UTC(targetYear, targetMonth + 1, 0, 12));
    first.setUTCDate(Math.min(start.getUTCDate(), last.getUTCDate()));
    end.setTime(first.getTime());
  }
  return {start, end};
}

/**
 * Builds an advertiser-only patch for a particular Phase 2 operation.
 * @param {Object} data Current Firestore application.
 * @param {string} action Command identifier.
 * @param {Object} payload User payload.
 * @param {Object} firebase ServerTimestamp and Timestamp factory.
 * @param {Date} current Server time.
 * @param {string} requestId Application id.
 * @return {Object} Safe Firestore update.
 */
function buildPatch(data, action, payload, firebase, current, requestId) {
  if (data.status !== "approved") {
    throw fail(409, "Cette demande n'est pas approuvée.");
  }
  const fv = firebase.FieldValue;
  const stamp = () => fv.serverTimestamp();
  const base = {updatedAt: stamp()};
  const isSpot = action === "saveSpot";
  const isAsset = action === "submitAssetChange";
  const isDiffusion = action === "saveDiffusion";
  if (!["saveSpot", "submitAssetChange", "saveDiffusion",
    "savePlanning"].includes(action)) {
    throw fail(400, "Opération inconnue.");
  }
  if (!payload || typeof payload !== "object" ||
      Array.isArray(payload)) throw fail(400, "Données invalides.");
  if (isSpot || isAsset) {
    const p = payload.position || {};
    const latitude = coordinate(p.latitude, 90);
    const longitude = coordinate(p.longitude, 180);
    const visual = payload.visual || {};
    const approved = data.approvedApplication || {};
    const approvedVisual = approved.visual || {};
    const existingSpot = data.advertisingSpot || {};
    const bannerUrl = validVisualUrl(visual.url, requestId,
        String(approvedVisual.url || existingSpot.bannerUrl || ""));
    const safeVisual = {
      url: bannerUrl,
      fileName: String(visual.fileName || "").slice(0, 160),
      extension: String(visual.extension || "").slice(0, 8),
      mimeType: String(visual.mimeType || "").slice(0, 40),
      fileSizeBytes: Number(visual.fileSizeBytes) || null,
      width: Number(visual.width) || null,
      height: Number(visual.height) || null,
    };
    if (isAsset) {
      if (data.advertisingSpotCompleted !== true) {
        throw fail(409, "Emplacement commercial absent.");
      }
      const previousChange = data.assetChangeRequest || {};
      if (previousChange.status === "submitted") {
        throw fail(409, "Une modification est déjà en instruction.");
      }
      const oldLat = Number(existingSpot.latitude);
      const oldLon = Number(existingSpot.longitude);
      const moved = Math.abs(latitude - oldLat) > 0.000001 ||
        Math.abs(longitude - oldLon) > 0.000001;
      if (!moved && bannerUrl === existingSpot.bannerUrl) {
        throw fail(400, "Aucune modification proposée.");
      }
      return {...base, assetChangeRequest: {
        status: "submitted", proposedLocation: {latitude, longitude},
        proposedVisual: safeVisual, submittedAt: stamp(), updatedAt: stamp(),
      }};
    }
    if (data.advertisingSpotCompleted === true) {
      throw fail(409, "Emplacement déjà enregistré : demandez une modification.");
    }
    const oldPosition = approved.location || data.applicantLocation || {};
    if (typeof oldPosition.latitude === "number" &&
        typeof oldPosition.longitude === "number" &&
        (Math.abs(latitude - oldPosition.latitude) > 0.00001 ||
        Math.abs(longitude - oldPosition.longitude) > 0.00001)) {
      throw fail(409, "Le déplacement exige une demande de modification.");
    }
    const territory = validTerritory(payload.territory);
    const previousTerritory = data.advertisingTerritory;
    if (previousTerritory && previousTerritory.level &&
        previousTerritory.level !== territory.level) {
      throw fail(409, "Le rayon contractuel ne peut pas changer.");
    }
    return {...base, advertisingTerritory: territory,
      advertisingSpotCompleted: true, advertisingSpot: {
        latitude, longitude, bannerUrl,
        bannerFileName: safeVisual.fileName,
        bannerExtension: safeVisual.extension,
        bannerMimeType: safeVisual.mimeType,
        bannerFileSizeBytes: safeVisual.fileSizeBytes,
        bannerWidth: safeVisual.width,
        bannerHeight: safeVisual.height,
        confirmedAt: stamp(),
      }, "diffusion.radiusKm": fv.delete()};
  }
  if (commercialLocked(data)) {
    throw fail(409, "La configuration contractuelle est verrouillée.");
  }
  if (data.advertisingSpotCompleted !== true) {
    throw fail(409, "Configurez d'abord le SPHOT publicitaire.");
  }
  if (isDiffusion) {
    const value = String(payload.visibilityType || "");
    if (!VALID_VISIBILITY.has(value)) {
      throw fail(400, "Zone de diffusion inconnue.");
    }
    return {...base, diffusionCompleted: true, diffusion: {
      ...(data.diffusion || {}), visibilityType: value,
      visibilityLabel: VALID_VISIBILITY.get(value), confirmedAt: stamp(),
    }};
  }
  if (data.diffusionCompleted !== true) {
    throw fail(409, "Enregistrez d'abord la diffusion.");
  }
  const dates = calculatePlanning(payload.startDate,
      payload.durationLabel, current);
  return {...base, planningCompleted: true, planning: {
    durationLabel: payload.durationLabel,
    campaignStartDate: firebase.Timestamp.fromDate(dates.start),
    campaignEndDate: firebase.Timestamp.fromDate(dates.end),
    confirmedAt: stamp(),
  }};
}

/**
 * Registers a protected write endpoint for advertisers' Phase 2 forms.
 * @param {Object} deps Firebase Admin and Firebase Functions dependencies.
 * @return {Function} HTTPS function.
 */
function registerAdvertiserPhaseTwoWrite({admin, onRequest}) {
  return onRequest({region: "us-central1", cors: true,
    cpu: 1, memory: "256MiB"}, async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({success: false, error: "Méthode interdite."});
      return;
    }
    const body = req.body || {};
    const requestId = body.requestId;
    if (typeof requestId !== "string" ||
        !/^[a-zA-Z0-9_-]{8,128}$/.test(requestId) ||
        Object.keys(body).some((key) =>
          !["requestId", "action", "payload"].includes(key))) {
      res.status(400).json({success: false, error: "Demande invalide."});
      return;
    }
    const header = req.headers.authorization || "";
    if (!header.startsWith("Bearer ")) {
      res.status(401).json({success: false, error: "Session absente."});
      return;
    }
    let claims;
    try {
      claims = await admin.auth().verifyIdToken(header.slice(7), true);
    } catch (_) {
      res.status(401).json({success: false, error: "Session expirée."});
      return;
    }
    const ordinaryAdvertiser = claims.role === "ANNONCEUR" &&
        claims.advertiserRequestId === requestId;
    const correctionLink = claims.role === "advertiser_candidate" &&
        claims.uid === requestId &&
        claims.advertiserRequestId === requestId &&
        body.action === "submitAssetChange";
    if (!ordinaryAdvertiser && !correctionLink) {
      res.status(403).json({success: false, error: "Accès refusé."});
      return;
    }
    const db = admin.firestore();
    const doc = db.collection("advertiserRequests").doc(requestId);
    try {
      await db.runTransaction(async (tx) => {
        const snapshot = await tx.get(doc);
        if (!snapshot.exists) throw fail(404, "Dossier introuvable.");
        const data = snapshot.data() || {};
        if (ordinaryAdvertiser && data.firebaseUid &&
            data.firebaseUid !== claims.uid) {
          throw fail(403, "Dossier non autorisé.");
        }
        if (correctionLink) {
          const change = data.assetChangeRequest || {};
          if (data.status !== "approved" ||
              !["authorized", "changes_requested"].includes(change.status)) {
            throw fail(403, "Aucune correction PHASE 2 autorisée.");
          }
        }
        const patch = buildPatch(data, body.action, body.payload,
            admin.firestore, new Date(), requestId);
        tx.update(doc, patch);
      });
      res.status(200).json({success: true});
    } catch (e) {
      if (!e.httpStatus) console.error("PHASE 2 refusée:", e);
      res.status(e.httpStatus || 500).json({
        success: false,
        error: e.httpStatus ? e.message : "Enregistrement indisponible.",
      });
    }
  });
}

module.exports = {registerAdvertiserPhaseTwoWrite,
  buildPatch, calculatePlanning, validTerritory};
