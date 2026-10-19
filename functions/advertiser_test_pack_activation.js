"use strict";

const TEST_DURATION_MS = 24 * 60 * 60 * 1000;

/**
 * @param {*} value Texte brut.
 * @return {string} Texte nettoyé.
 */
function txt(value) {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * @param {*} value Date Firestore ou JavaScript.
 * @return {number} Millisecondes.
 */
function ms(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return NaN;
}

/**
 * @param {Object} request Dossier annonceur.
 * @param {Object} campaign Campagne publique.
 * @param {string} requestId Identifiant exact.
 * @param {number} now Heure actuelle.
 * @return {Object} Prévisualisation de l'opération.
 */
function previewTestPack(request, campaign, requestId, now = Date.now()) {
  const diffusion = request.diffusion || {};
  const establishment = request.establishment || {};
  const approved = request.approvedApplication || {};
  const spot = request.advertisingSpot || {};
  const proposed = request.proposedVisual || {};
  const name = txt(request.advertiserName || establishment.businessName);
  const campaignName = txt(campaign.advertiserName);
  const banner = txt(campaign.bannerUrl);
  const approvedBanners = [
    txt((approved.visual || {}).url),
    txt(spot.bannerUrl),
    txt(proposed.url),
  ].filter(Boolean);
  if (request.status !== "approved" ||
      request.diffusionCompleted !== true ||
      diffusion.visibilityType !== "pack") {
    throw Object.assign(
        new Error("Dossier Pack non approuvé ou non confirmé."), {
          status: 409,
        });
  }
  if (campaign.status !== "active" || campaign.visibilityType !== "map") {
    throw Object.assign(new Error("La campagne doit être active et Carte."), {
      status: 409,
    });
  }
  if (campaign.advertiserRequestId &&
      campaign.advertiserRequestId !== requestId) {
    throw Object.assign(new Error("Campagne liée à un autre dossier."), {
      status: 409,
    });
  }
  if (!name || name.toLowerCase() !== campaignName.toLowerCase() ||
      !banner || !approvedBanners.includes(banner)) {
    throw Object.assign(new Error(
        "Le nom ou le visuel ne correspondent pas : liaison refusée.",
    ), {status: 409});
  }
  const starts = ms(campaign.campaignStartDate);
  const ends = ms(campaign.campaignEndDate);
  if (!Number.isFinite(starts) || !Number.isFinite(ends) ||
      now < starts || now >= ends) {
    throw Object.assign(new Error("Campagne hors période active."), {
      status: 409,
    });
  }
  return {
    advertiserName: name,
    previousVisibilityType: "map",
    proposedVisibilityType: "pack",
    expiresAt: Math.min(ends, now + TEST_DURATION_MS),
  };
}

/**
 * @param {string} origin Origine HTTP.
 * @return {boolean} Origine admise.
 */
function allowedOrigin(origin) {
  if (!origin) return true;
  if ([
    "https://sphot.app",
    "https://www.sphot.app",
    "https://sphot-ab80b.web.app",
    "https://sphot-ab80b.firebaseapp.com",
  ].includes(origin)) return true;
  try {
    const u = new URL(origin);
    return u.protocol === "http:" &&
      ["localhost", "127.0.0.1"].includes(u.hostname);
  } catch (_) {
    return false;
  }
}

/**
 * @param {Object} dependencies Firebase et session sécurisée.
 * @return {Function} Fonction HTTP Pack de test.
 */
function registerAdvertiserTestPackActivation({
  admin, crypto, onRequest, checkSuperAdminSession,
}) {
  return onRequest(
      {region: "europe-west1", cpu: 1, memory: "256MiB"},
      async (request, response) => {
        const origin = txt(request.headers.origin);
        if (!allowedOrigin(origin)) {
          response.status(403).json({
            success: false, error: "Origine refusée.",
          });
          return;
        }
        if (origin) {
          response.set("Access-Control-Allow-Origin", origin);
          response.set("Vary", "Origin");
        }
        response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        response.set("Access-Control-Allow-Headers",
            "Content-Type, Authorization");
        response.set("Cache-Control", "no-store");
        if (request.method === "OPTIONS") {
          response.status(204).send("");
          return;
        }
        if (request.method !== "POST") {
          response.status(405).json({success: false, error: "POST requis."});
          return;
        }

        try {
          const bearer = txt(request.headers.authorization);
          if (!bearer.startsWith("Bearer ")) {
            throw Object.assign(new Error("Session Super Admin requise."), {
              status: 401,
            });
          }
          const login = await checkSuperAdminSession(
              admin, crypto, bearer.substring(7));
          const body = request.body || {};
          const requestId = txt(body.requestId);
          const campaignId = txt(body.campaignId);
          const action = txt(body.action);
          if (!requestId || !campaignId ||
              requestId.includes("/") || campaignId.includes("/") ||
              !["preview", "confirm"].includes(action)) {
            throw Object.assign(
                new Error("Identifiants ou action invalides."), {
                  status: 400,
                });
          }
          const db = admin.firestore();
          const requestRef = db.collection("advertiserRequests").doc(requestId);
          const campaignRef = db.collection("adRequests").doc(campaignId);

          if (action === "preview") {
            const [a, b] = await Promise.all([
              requestRef.get(), campaignRef.get(),
            ]);
            if (!a.exists || !b.exists) {
              throw Object.assign(new Error("Document introuvable."), {
                status: 404,
              });
            }
            const plan = previewTestPack(a.data(), b.data(), requestId);
            response.status(200).json({success: true, data: plan});
            return;
          }

          if (body.confirmation !== "ACTIVER PACK TEST") {
            throw Object.assign(new Error("Confirmation manquante."), {
              status: 400,
            });
          }
          const plan = await db.runTransaction(async (tx) => {
            const a = await tx.get(requestRef);
            const b = await tx.get(campaignRef);
            if (!a.exists || !b.exists) {
              throw Object.assign(new Error("Document introuvable."), {
                status: 404,
              });
            }
            const result = previewTestPack(
                a.data(), b.data(), requestId, Date.now());
            const expiresAt = admin.firestore.Timestamp.fromMillis(
                result.expiresAt);
            tx.update(campaignRef, {
              advertiserRequestId: requestId,
              visibilityType: "pack",
              testPack: {
                previousVisibilityType: "map",
                expiresAt,
                approvedBy: login,
                activatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            tx.set(campaignRef.collection("testPackHistory").doc(), {
              requestId,
              campaignId,
              previousVisibilityType: "map",
              visibilityType: "pack",
              approvedBy: login,
              expiresAt,
              activatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return result;
          });
          response.status(200).json({success: true, data: plan});
        } catch (error) {
          console.error("Activation Pack test:", error.message);
          response.status(error.status || 500).json({
            success: false,
            error: error.message || "Erreur activation Pack.",
          });
        }
      },
  );
}

module.exports = {previewTestPack, registerAdvertiserTestPackActivation};
