/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

/**
 * Remises individuelles SPHOT: jamais de code promo partagé, ni de montant
 * prélevé dans le navigateur. Seul le Super Admin peut modifier la remise.
 */
const COLLECTION = "commercialCustomerDiscounts";
const MARKETS = new Set(["ADMIN", "ADVERTISER_RADIUS"]);

function invalid(message) {
  const error = new Error(message);
  error.status = 400;
  return error;
}

function validateCustomer(market, uid) {
  if (!MARKETS.has(market) || typeof uid !== "string" ||
      !/^[a-zA-Z0-9_-]{6,128}$/.test(uid)) {
    throw invalid("Marché ou identifiant client invalide.");
  }
  return market + "__" + uid;
}

function validatePercent(value) {
  if (!Number.isInteger(value) || value < 0 || value > 90) {
    throw invalid("Remise invalide : nombre entier de 0 à 90 % requis.");
  }
  return value;
}

function computeDiscountCents(amountExclTax, percent) {
  if (!Number.isSafeInteger(amountExclTax) || amountExclTax < 0) {
    throw new Error("Montant de base invalide.");
  }
  validatePercent(percent);
  const originalCents = amountExclTax * 100;
  if (!Number.isSafeInteger(originalCents)) {
    throw new Error("Montant trop élevé.");
  }
  // Le calcul reste intégralement en centimes, jamais en flotteurs HT.
  const discountCents = Math.round(originalCents * percent / 100);
  return {
    baseAmountExclTaxCents: originalCents,
    discountPercent: percent,
    discountAmountCents: discountCents,
    payableExclTaxCents: originalCents - discountCents,
  };
}

async function readDiscount(admin, market, uid) {
  const key = validateCustomer(market, uid);
  const snapshot = await admin.firestore().collection(COLLECTION).doc(key).get();
  if (!snapshot.exists) return 0;
  const data = snapshot.data();
  // Fail closed when the stored value is corrupted.
  return validatePercent(data.percent);
}

async function getForSuperAdmin(admin, market, uid) {
  return {
    uid,
    market,
    percent: await readDiscount(admin, market, uid),
  };
}

async function setForSuperAdmin(admin, market, uid, percent, actor) {
  const key = validateCustomer(market, uid);
  validatePercent(percent);
  const db = admin.firestore();
  if (percent === 0) {
    await db.collection(COLLECTION).doc(key).delete();
    return {uid, market, percent: 0};
  }
  await db.collection(COLLECTION).doc(key).set({
    uid, market, percent,
    updatedBy: actor,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {uid, market, percent};
}

module.exports = {
  COLLECTION,
  validateCustomer,
  validatePercent,
  computeDiscountCents,
  readDiscount,
  getForSuperAdmin,
  setForSuperAdmin,
};
