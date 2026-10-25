/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Initial advertiser checkout, SPHOT TEST only. Never calls Odoo/Stripe,
// sends invoices, changes adRequests, or grants activation rights.
const crypto = require("node:crypto");
const {advertiserQuote, publishedState} = require("./commercial_quote_pricing");
const {LEVELS, OFFERS, DURATIONS} = require("./advertiser_radius_tariffs");
const {computeDiscountCents, validatePercent, validateCustomer} =
    require("./commercial_discounts");
const {calculatePlanning} = require("./advertiser_phase_two_write");

function reject(httpStatus, message) {
  const error = new Error(message);
  error.httpStatus = httpStatus;
  return error;
}

function toMillis(value) {
  if (value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) return value.getTime();
  return NaN;
}

function referenceFor(requestId) {
  if (typeof requestId !== "string" ||
      !/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) {
    throw reject(400, "Dossier publicitaire invalide.");
  }
  const key = crypto.createHash("sha256").update("SPHOT_ADVERTISER_INITIAL_V1:")
      .update(requestId).digest("hex").slice(0, 16).toUpperCase();
  return `SPHOT-PUB-TEST-${key}`;
}

function preparedOrder(data, published, percent, requestId, uid, now) {
  if (data.status !== "approved" || data.advertisingSpotCompleted !== true ||
      data.diffusionCompleted !== true || data.planningCompleted !== true) {
    throw reject(409, "Enregistrez les étapes SPHOT PUBLICITAIRE, DIFFUSION et PLANIFICATION avant le devis.");
  }
  if (data.campaignActivated === true || data.quoteOrderCompleted === true ||
      data.orderCompleted === true || data.order != null ||
      ["paid", "succeeded"].includes(String(data.payment?.status || "").toLowerCase())) {
    throw reject(409, "Une commande ou un paiement existe déjà pour ce dossier.");
  }
  const accepted = data.acceptedDocuments || {};
  const legal = data.legalAcceptance || {};
  if (accepted.cgu !== true || accepted.privacy !== true ||
      accepted.rgpd !== true || accepted.advertiserCgv !== true ||
      legal.representativeDeclaration !== true) {
    throw reject(409, "Les acceptations juridiques du dossier doivent être enregistrées.");
  }

  const territory = String(data.advertisingTerritory?.level || "");
  const offer = String(data.diffusion?.visibilityType || "");
  const duration = String(data.planning?.durationLabel || "");
  if (!LEVELS.includes(territory) || !OFFERS.includes(offer) ||
      !DURATIONS.includes(duration)) {
    throw reject(409, "Choix commerciaux enregistrés incomplets ou invalides.");
  }
  if (territory === "country" &&
      !/^[A-Z]{3}$/.test(data.advertisingTerritory?.countryIso3 || "")) {
    throw reject(409, "Pays entier non enregistré correctement.");
  }
  const startMillis = toMillis(data.planning.campaignStartDate);
  const endMillis = toMillis(data.planning.campaignEndDate);
  if (!Number.isFinite(startMillis) || !Number.isFinite(endMillis)) {
    throw reject(409, "Dates de campagne enregistrées invalides.");
  }
  const day = new Date(startMillis).toISOString().slice(0, 10);
  let verified;
  try {
    verified = calculatePlanning(day, duration, now);
  } catch (_) {
    throw reject(409, "La date de début est dépassée : replanifiez avant commande.");
  }
  if (verified.start.getTime() !== startMillis ||
      verified.end.getTime() !== endMillis) {
    throw reject(409, "La planification enregistrée n'est plus cohérente.");
  }

  const quote = advertiserQuote(published, territory, offer, duration);
  const discount = computeDiscountCents(quote.amountExclTax,
      validatePercent(percent));
  return {
    origin: "sphot_advertiser_initial_v1",
    reference: referenceFor(requestId),
    status: "awaiting_odoo_test_configuration",
    environment: "test",
    market: "ADVERTISER_RADIUS",
    advertiserUid: uid,
    territory: {
      level: territory,
      code: data.advertisingTerritory.code || null,
      countryIso3: data.advertisingTerritory.countryIso3 || null,
    },
    offer,
    duration,
    campaignStartDate: data.planning.campaignStartDate,
    campaignEndDate: data.planning.campaignEndDate,
    pricingReference: quote.pricingReference,
    publishedVersion: quote.version,
    tariffKey: quote.tariffKey,
    baseAmountExclTaxCents: discount.baseAmountExclTaxCents,
    discountPercent: discount.discountPercent,
    discountAmountCents: discount.discountAmountCents,
    payableExclTaxCents: discount.payableExclTaxCents,
    currency: "EUR",
    legalAcceptanceSnapshot: {
      legalVersion: String(accepted.version || ""),
      cgvVersion: String(accepted.advertiserCgvVersion || ""),
      acceptedAt: accepted.acceptedAt || null,
    },
    taxStatus: "to_be_determined_by_odoo",
    paymentStatus: "not_started",
    odooStatus: "not_connected",
    paymentProofVerified: false,
    campaignActivationAllowed: false,
    automaticRenewal: false,
  };
}

function publicReceipt(order) {
  return {
    reference: order.reference,
    status: order.status,
    territory: order.territory?.level,
    offer: order.offer,
    duration: order.duration,
    pricingReference: order.pricingReference,
    baseAmountExclTaxCents: order.baseAmountExclTaxCents,
    discountPercent: order.discountPercent,
    discountAmountCents: order.discountAmountCents,
    payableExclTaxCents: order.payableExclTaxCents,
    currency: order.currency,
    paymentStatus: "not_started",
    campaignActivationAllowed: false,
    testOnly: true,
  };
}

function assertClientSawQuote(order, expected) {
  if (!expected || typeof expected !== "object" ||
      Array.isArray(expected) ||
      Object.keys(expected).sort().join("|") !== [
        "duration", "offer", "payableExclTaxCents", "pricingReference",
        "startDate", "territory",
      ].sort().join("|")) {
    throw reject(400, "Récapitulatif de devis incomplet.");
  }
  const start = new Date(toMillis(order.campaignStartDate))
      .toISOString().slice(0, 10);
  if (expected.territory !== order.territory.level ||
      expected.offer !== order.offer ||
      expected.duration !== order.duration ||
      expected.startDate !== start ||
      expected.pricingReference !== order.pricingReference ||
      expected.payableExclTaxCents !== order.payableExclTaxCents) {
    throw reject(409, "La sélection ou le tarif a changé. Actualisez le devis avant de confirmer.");
  }
}

function registerAdvertiserInitialOrder({admin, onRequest,
  testOrdersEnabled = process.env.SPHOT_ADVERTISER_TEST_ORDER_ENABLED === "true"}) {
  return onRequest({region: "us-central1", cors: true,
    cpu: 1, memory: "256MiB", maxInstances: 5}, async (req, res) => {
    res.set("Cache-Control", "no-store");
    if (req.method !== "POST") {
      res.status(405).json({success: false, error: "Méthode interdite."});
      return;
    }
    if (!testOrdersEnabled) {
      res.status(503).json({success: false,
        error: "Préparation des commandes de test non activée."});
      return;
    }
    const body = req.body || {};
    if (!body || typeof body !== "object" || Array.isArray(body) ||
        Object.keys(body).some((key) =>
          !["requestId", "expected"].includes(key))) {
      res.status(400).json({success: false, error: "Données de commande invalides."});
      return;
    }
    const requestId = body.requestId;
    try {
      referenceFor(requestId);
      const header = String(req.headers.authorization || "");
      if (!header.startsWith("Bearer ")) {
        throw reject(401, "Connexion annonceur requise.");
      }
      let claims;
      try {
        claims = await admin.auth().verifyIdToken(header.slice(7), true);
      } catch (_) {
        throw reject(401, "Session annonceur expirée.");
      }
      if (claims.role !== "ANNONCEUR" ||
          claims.advertiserRequestId !== requestId) {
        throw reject(403, "Ce dossier ne vous appartient pas.");
      }
      const db = admin.firestore();
      const requestRef = db.collection("advertiserRequests").doc(requestId);
      const pricingRef = db.collection("commercialPricingMarkets")
          .doc("FR_ADVERTISER_RADIUS");
      const discountRef = db.collection("commercialCustomerDiscounts")
          .doc(validateCustomer("ADVERTISER_RADIUS", claims.uid));
      const result = await db.runTransaction(async (tx) => {
        const request = await tx.get(requestRef);
        if (!request.exists) throw reject(404, "Dossier annonceur introuvable.");
        const data = request.data() || {};
        if (data.firebaseUid && data.firebaseUid !== claims.uid) {
          throw reject(403, "Compte annonceur non autorisé.");
        }
        if (data.status !== "approved") {
          throw reject(409, "Dossier annonceur non approuvé.");
        }
        // A second click is read-only and never recalculates past prices.
        if (data.order?.origin === "sphot_advertiser_initial_v1" &&
            data.order?.reference === referenceFor(requestId) &&
            data.quoteOrderCompleted === true &&
            data.order?.status === "awaiting_odoo_test_configuration") {
          return {receipt: publicReceipt(data.order), alreadyExists: true};
        }
        const publishedSnap = await tx.get(pricingRef);
        const discountSnap = await tx.get(discountRef);
        const published = publishedState(publishedSnap, "ADVERTISER_RADIUS");
        const percent = discountSnap.exists ?
          validatePercent(discountSnap.data().percent) : 0;
        const order = preparedOrder(data, published, percent,
            requestId, claims.uid, new Date());
        assertClientSawQuote(order, body.expected);
        tx.update(requestRef, {
          order: {...order, createdAt: admin.firestore.FieldValue.serverTimestamp()},
          quoteOrderCompleted: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return {receipt: publicReceipt(order), alreadyExists: false};
      });
      res.status(200).json({success: true, ...result});
    } catch (error) {
      if (!error.httpStatus) console.error("SPHOT advertiser order failed", error);
      res.status(error.httpStatus || 500).json({success: false,
        error: error.httpStatus ? error.message :
          "Confirmation de commande indisponible."});
    }
  });
}

module.exports = {referenceFor, preparedOrder, publicReceipt,
  assertClientSawQuote,
  registerAdvertiserInitialOrder};
