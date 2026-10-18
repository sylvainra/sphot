/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Preview en lecture seule : aucune ecriture dans les devis ou abonnements.
const MARKET_COLLECTION = "commercialPricingMarkets";
const discounts = require("./commercial_discounts");
const {LEVELS, OFFERS, DURATIONS, PRICE_KEYS} =
  require("./advertiser_radius_tariffs");

function quoteError(status, message) {
  const e = new Error(message);
  e.httpStatus = status;
  return e;
}

function safePrice(n) {
  if (!Number.isSafeInteger(n) || n <= 0 || n > 10000000) {
    throw quoteError(503, "Catalogue tarifaire publie invalide.");
  }
  return n;
}

function publishedState(snapshot, type) {
  if (!["ADMIN", "ADVERTISER_RADIUS"].includes(type)) {
    throw quoteError(400, "Ancien marché tarifaire retiré.");
  }
  if (!snapshot || !snapshot.exists) {
    throw quoteError(503, "Aucune grille publiee disponible.");
  }
  const data = snapshot.data();
  if (!data || data.type !== type || data.country !== "FR" ||
      data.currency !== "EUR" ||
      !Number.isSafeInteger(data.publishedVersion) ||
      data.publishedVersion < 1) {
    throw quoteError(503, "Metadonnees tarifaires publiees invalides.");
  }
  return data;
}

// Tarif MARGINAL: chaque tranche ne concerne que les postes de cette tranche.
// Ex. 10 postes = 499 + 3*399 + 5*299 + 199 = 3390 EUR HT.
function adminQuote(data, stations) {
  if (!Number.isSafeInteger(stations) ||
      stations < 1 || stations > 10000) {
    throw quoteError(400, "Nombre de postes de secours invalide.");
  }
  const rates = data.publishedPrices;
  if (!Array.isArray(rates) || rates.length !== 4) {
    throw quoteError(503, "Quatre tranches tarifaires ADMIN requises.");
  }
  const values = rates.map(safePrice);
  const counts = [
    1,
    Math.min(Math.max(stations - 1, 0), 3),
    Math.min(Math.max(stations - 4, 0), 5),
    Math.max(stations - 9, 0),
  ];
  const lines = counts.map((count, i) => ({
    tier: i + 1,
    count,
    unitExclTax: values[i],
    amountExclTax: count * values[i],
  }));
  return {
    market: "ADMIN",
    version: data.publishedVersion,
    pricingReference: "FR_ADMIN-V" + data.publishedVersion,
    country: "FR",
    currency: "EUR",
    numberOfRescueStations: stations,
    rateSnapshot: [...values],
    lines,
    amountExclTax: lines.reduce((sum, l) => sum + l.amountExclTax, 0),
  };
}

function advertiserQuote(data, territory, offer, duration) {
  if (!data || data.type !== "ADVERTISER_RADIUS") {
    throw quoteError(503, "Ancien catalogue non applicable.");
  }
  const t = LEVELS.indexOf(territory);
  const o = OFFERS.indexOf(offer);
  const d = DURATIONS.indexOf(duration);
  if (t < 0 || o < 0 || d < 0) {
    throw quoteError(400, "Territoire, offre ou duree non pris en charge.");
  }
  const prices = data.publishedPrices;
  const keys = !prices || Array.isArray(prices) ||
      typeof prices !== "object" ? [] : Object.keys(prices).sort();
  if (keys.length !== 108 ||
      keys.join("|") !== PRICE_KEYS.join("|")) {
    throw quoteError(503, "La grille publiee requiert 108 tarifs exacts.");
  }
  const key = t + ":" + o + ":" + d;
  const amount = safePrice(prices[key]);
  return {
    market: data.type,
    version: data.publishedVersion,
    pricingReference: "FR_" + data.type + "-V" + data.publishedVersion,
    country: "FR",
    currency: "EUR",
    territory,
    offer,
    duration,
    tariffKey: key,
    amountExclTax: amount,
  };
}

// Devis indicatif uniquement. La confirmation future devra recalculer et
// figer la meme reference et les memes prix sur un serveur de confiance.
function endpoint({admin, onRequest}) {
  return onRequest({
    region: "us-central1",
    cpu: 1,
    memory: "256MiB",
  }, async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.set("Cache-Control", "no-store");
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({success: false, error: "Utilisez POST."});
      return;
    }
    try {
      const body = req.body || {};
      const market = body.market;
      if (!["ADMIN", "ADVERTISER_RADIUS"].includes(market)) {
        throw quoteError(400, "Marche tarifaire inconnu.");
      }
      const id = "FR_" + market;
      const snapshot = await admin.firestore()
          .collection(MARKET_COLLECTION).doc(id).get();
      const published = publishedState(snapshot, market);
      const quote = market === "ADMIN" ?
        adminQuote(published, body.numberOfRescueStations) :
        advertiserQuote(
            published, body.territory, body.offer, body.duration,
        );

      // Aucun UID client transmis dans le corps n'est accepté :
      // le client est identifié UNIQUEMENT par Firebase Auth.
      const header = String(req.headers.authorization || "");
      let percent = 0;
      if (header) {
        if (!header.startsWith("Bearer ")) {
          throw quoteError(401, "Authentification incorrecte.");
        }
        let decoded;
        try {
          decoded = await admin.auth().verifyIdToken(header.slice(7));
        } catch (_) {
          throw quoteError(401, "Session client invalide.");
        }
        if (market === "ADMIN" || market === "ADVERTISER_RADIUS") {
          percent = await discounts.readDiscount(admin, market, decoded.uid);
        }
      }
      const reduction = discounts.computeDiscountCents(
          quote.amountExclTax, percent);
      res.status(200).json({
        success: true,
        quote: {
          ...quote,
          ...reduction,
          calculatedAt: new Date().toISOString(),
          previewOnly: true,
        },
      });
    } catch (e) {
      const status = e.httpStatus || 500;
      if (status === 500) {
        console.error("Published commercial quote read failed", e);
      }
      res.status(status).json({
        success: false,
        error: status === 500 ?
          "Service tarifaire temporairement indisponible." : e.message,
      });
    }
  });
}

module.exports = {adminQuote, advertiserQuote, publishedState, endpoint};
