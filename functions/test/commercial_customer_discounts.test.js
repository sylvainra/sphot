/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  validateCustomer, validatePercent, computeDiscountCents,
} = require("../commercial_discounts");

test("remise -5% avec centimes corrects", () => {
  assert.deepEqual(computeDiscountCents(49, 5), {
    baseAmountExclTaxCents: 4900,
    discountPercent: 5,
    discountAmountCents: 245,
    payableExclTaxCents: 4655,
  });
});

test("remise -10% sur montant entier", () => {
  const d = computeDiscountCents(1000, 10);
  assert.equal(d.discountAmountCents, 10000);
  assert.equal(d.payableExclTaxCents, 90000);
});

test("0% conserve le tarif du catalogue", () => {
  assert.equal(computeDiscountCents(49, 0).payableExclTaxCents, 4900);
});

test("pourcentages invalides et hausse interdits", () => {
  for (const p of [-5, -1, 91, 100, 4.5, "10", null]) {
    assert.throws(() => validatePercent(p));
  }
});

test("remises distinctes et UID requis", () => {
  assert.equal(validateCustomer("ADMIN", "user123"), "ADMIN__user123");
  assert.equal(
      validateCustomer("ADVERTISER_RADIUS", "user123"),
      "ADVERTISER_RADIUS__user123");
  for (const market of ["ADVERTISER", "bad", ""]) {
    assert.throws(() => validateCustomer(market, "user123"));
  }
  assert.throws(() => validateCustomer("ADMIN", "../admin"));
});

test("montants invalides ou trop eleves bloques", () => {
  for (const amount of [-1, 1.5, "100"]) {
    assert.throws(() => computeDiscountCents(amount, 10));
  }
});
