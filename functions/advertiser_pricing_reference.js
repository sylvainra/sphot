"use strict";

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

/**
 * Retourne SEULEMENT la reference du tarif actuellement publie.
 * Les anciens 90 prix (5 categories) ne sont pas attribues aux 6 rayons.
 * @param {Object} request Requete HTTP.
 * @param {Object} response Reponse HTTP.
 * @return {Promise<void>} Envoi de la reponse JSON.
 */
async function handler(request, response) {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  response.set("Cache-Control", "no-store");
  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }
  if (request.method !== "GET") {
    response.status(405).json({success: false});
    return;
  }

  try {
    const doc = await admin.firestore()
        .collection("commercialPricingMarkets")
        .doc("FR_ADVERTISER").get();
    const data = doc.exists ? doc.data() : null;
    const version = data && data.publishedVersion;
    const prices = data && data.publishedPrices;
    const valid = data &&
        data.type === "ADVERTISER" &&
        data.country === "FR" &&
        data.currency === "EUR" &&
        Number.isSafeInteger(version) && version > 0 &&
        prices && !Array.isArray(prices) &&
        typeof prices === "object" &&
        Object.keys(prices).length === 90;

    if (!valid) {
      response.status(503).json({
        success: false,
        error: "Aucune grille annonceur publiee et verifiee.",
      });
      return;
    }

    response.status(200).json({
      success: true,
      pricingReference: "FR_ADVERTISER-V" + version,
      currency: "EUR",
      publishedCells: 90,
      publishedModel: "legacy_five_categories",
      applicableToSixRadii: false,
      newRadiusCellCount: 108,
    });
  } catch (error) {
    console.error("Published advertising reference unavailable", error);
    response.status(503).json({
      success: false,
      error: "Reference de tarification temporairement indisponible.",
    });
  }
}

exports.getPublishedAdvertiserPricingReference = onRequest({
  region: "us-central1",
  cpu: 1,
  memory: "256MiB",
}, handler);
exports.handler = handler;
