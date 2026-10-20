"use strict";

const {evaluateRenewal, validateRenewalTerritory} =
    require("./advertiser_renewal_rules");
const {advertiserQuote, publishedState} =
    require("./commercial_quote_pricing");
const discounts = require("./commercial_discounts");

const ALLOWED_ORIGINS = new Set([
  "https://sphot.app",
  "https://www.sphot.app",
  "https://sphot-ab80b.web.app",
  "https://sphot-ab80b.firebaseapp.com",
]);
const localOrigin = /^http:\/\/(localhost|127\.0\.0\.1):[0-9]{2,5}$/;

function registerAdvertiserRenewalEndpoint({admin, onRequest}) {
  return onRequest({
    region: "europe-west1",
    cpu: 1,
    memory: "256MiB",
    maxInstances: 5,
    timeoutSeconds: 30,
  }, async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("Vary", "Origin, Authorization");
    const origin = req.get("Origin") || "";
    if (origin) {
      if (!ALLOWED_ORIGINS.has(origin) && !localOrigin.test(origin)) {
        res.status(403).json({error: "ORIGIN_DENIED"});
        return;
      }
      res.set("Access-Control-Allow-Origin", origin);
      res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
      res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    }
    if (req.method === "OPTIONS") {
      res.status(204).end();
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({error: "METHOD_NOT_ALLOWED"});
      return;
    }

    const match = /^Bearer (.+)$/i.exec(req.get("Authorization") || "");
    if (!match) {
      res.status(401).json({error: "AUTH_REQUIRED"});
      return;
    }

    let uid;
    try {
      const decoded = await admin.auth().verifyIdToken(match[1], true);
      uid = decoded.uid;
    } catch (_) {
      res.status(401).json({error: "AUTH_INVALID"});
      return;
    }
    const body = req.body || {};
    const requestId = String(body.requestId || "").trim();
    if (!/^[A-Za-z0-9_-]{6,128}$/.test(requestId)) {
      res.status(400).json({error: "REQUEST_INVALID"});
      return;
    }
    const db = admin.firestore();
    try {
      const requestRef = db.collection("advertiserRequests").doc(requestId);
      const doc = await requestRef.get();
      const advertiser = doc.data() || {};
      const owner = [
        requestId,
        String(advertiser.uid || ""),
        String(advertiser.ownerUid || ""),
      ];
      if (!doc.exists || !owner.includes(uid)) {
        res.status(403).json({error: "NOT_OWNER"});
        return;
      }
      if (String(advertiser.status || "") !== "approved") {
        res.status(409).json({error: "NOT_APPROVED"});
        return;
      }
      // Lier uniquement par l'identifiant du dossier, jamais par le nom.
      const snap = await db.collection("adRequests")
          .where("advertiserRequestId", "==", requestId).get();
      const campaigns = new Map(snap.docs.map((d) => [d.id, d.data()]));
      const legacy = await db.collection("adRequests").doc(requestId).get();
      if (legacy.exists) campaigns.set(legacy.id, legacy.data());
      const now = Date.now();
      const evaluation = evaluateRenewal([...campaigns.values()], now);
      const response = {
        ...evaluation,
        campaignCount: campaigns.size,
        endAt: evaluation.endAt === null ?
          null : new Date(evaluation.endAt).toISOString(),
      };

      if (body.action === "eligibility") {
        res.status(200).json(response);
        return;
      }
      if (body.action !== "prepare") {
        res.status(400).json({error: "ACTION_INVALID"});
        return;
      }
      if (!evaluation.eligible) {
        res.status(409).json({error: "PERIOD_NOT_FINISHED", ...response});
        return;
      }
      let territory;
      try {
        territory = validateRenewalTerritory(body.territory);
      } catch (_) {
        res.status(400).json({error: "TERRITORY_INVALID"});
        return;
      }
      // Prix RE-CALCULÉ côté serveur et figé dans un brouillon, jamais
      // fourni par le navigateur. Aucun devis/commande/paiement n'est créé.
      const priceDoc = await db.collection("commercialPricingMarkets")
          .doc("FR_ADVERTISER_RADIUS").get();
      const published = publishedState(priceDoc, "ADVERTISER_RADIUS");
      const offer = String(body.offer || "");
      const duration = String(body.duration || "");
      let quote;
      try {
        quote = advertiserQuote(published, territory.level,
            offer, duration);
      } catch (_) {
        res.status(400).json({error: "PRICE_SELECTION_INVALID"});
        return;
      }
      const percent = await discounts.readDiscount(
          admin, "ADVERTISER_RADIUS", uid);
      const reduction = discounts.computeDiscountCents(
          quote.amountExclTax, percent);
      // DRAFT SEULEMENT. Aucune écriture dans advertisingTerritory,
      // adRequests, planning, devis, factures ni statut de paiement.
      await requestRef.set({
        renewalDraft: {
          status: "awaiting_commercial_checkout",
          proposedTerritory: territory,
          originalTerritory: advertiser.advertisingTerritory || null,
          visibilityType: offer,
          durationLabel: duration,
          tariff: {
            pricingReference: quote.pricingReference,
            amountExclTax: quote.amountExclTax,
            discountPercent: percent,
            payableExclTaxCents: reduction.payableExclTaxCents,
            currency: "EUR",
            indicativeOnly: true,
          },
          eligibleAt: admin.firestore.Timestamp.fromMillis(evaluation.endAt),
          preparedAt: admin.firestore.FieldValue.serverTimestamp(),
          paymentStatus: "not_started",
          subscriptionActivated: false,
        },
      }, {merge: true});
      res.status(200).json({
        ...response,
        draftStatus: "awaiting_commercial_checkout",
        territory,
        pricingReference: quote.pricingReference,
        payableExclTaxCents: reduction.payableExclTaxCents,
      });
    } catch (error) {
      console.error("advertiserRenewalEligibility:", error);
      res.status(500).json({error: "SERVER_ERROR"});
    }
  });
}

module.exports = {registerAdvertiserRenewalEndpoint};
