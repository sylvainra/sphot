/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {validate, defaultState} = require("../commercial_pricing");
const {advertiserQuote} = require("../commercial_quote_pricing");

function matrix(rows) {
  const result = {};
  for (let r = 0; r < rows; r++) {
    for (let o = 0; o < 3; o++) {
      for (let d = 0; d < 6; d++) {
        result[r + ":" + o + ":" + d] = 100 + 10 * r + 2 * o + d;
      }
    }
  }
  return result;
}

test("six rayons : 108 cellules exigees", () => {
  const result = validate("ADVERTISER_RADIUS", matrix(6), []);
  assert.equal(Object.keys(result.prices).length, 108);
  assert.throws(() => validate("ADVERTISER_RADIUS", matrix(5), []));
});

test("ancien marché publicitaire à 90 prix supprimé des écritures", () => {
  assert.throws(() => validate("ADVERTISER", matrix(5), []),
      /Ancien marché tarifaire retiré/);
  assert.throws(() => validate("ADVERTISER", matrix(6), []),
      /Ancien marché tarifaire retiré/);
});

test("catalogue initial à 108 tarifs non publié sans action Super Admin", () => {
  const state = defaultState("ADVERTISER_RADIUS");
  assert.equal(state.publishedVersion, 0);
  assert.equal(Object.keys(state.publishedPrices).length, 108);
  assert.equal(state.draft, null);
});

test("nouvelle reference propre au catalogue mondial", () => {
  const quote = advertiserQuote({
    type: "ADVERTISER_RADIUS", country: "FR", currency: "EUR",
    publishedVersion: 2, publishedPrices: matrix(6),
  }, "country", "pack", "1 an");
  assert.equal(quote.tariffKey, "5:2:5");
  assert.equal(quote.pricingReference, "FR_ADVERTISER_RADIUS-V2");
});

test("pas de tarif sur grille incomplete", () => {
  assert.throws(() => advertiserQuote({
    type: "ADVERTISER_RADIUS", country: "FR", currency: "EUR",
    publishedVersion: 2, publishedPrices: matrix(5),
  }, "country", "pack", "1 an"));
});
