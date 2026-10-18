/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, object-curly-spacing */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  adminQuote, advertiserQuote, publishedState,
} = require("../commercial_quote_pricing");

const admin = {
  type: "ADMIN", country: "FR", currency: "EUR",
  publishedVersion: 3, publishedPrices: [499, 399, 299, 199],
};

for (const [stations, expected] of [
  [1, 499], [2, 898], [4, 1696], [5, 1995],
  [9, 3191], [10, 3390], [15, 4385],
]) {
  test("ADMIN progressive quotation for " + stations + " stations", () => {
    const quote = adminQuote(admin, stations);
    assert.equal(quote.amountExclTax, expected);
    assert.equal(quote.version, 3);
    assert.equal(quote.pricingReference, "FR_ADMIN-V3");
    assert.equal(quote.lines.reduce((total, line) => total + line.count, 0),
        stations);
    assert.deepEqual(quote.rateSnapshot, [499, 399, 299, 199]);
  });
}

test("ADMIN rejects zero, negative and non-integer station counts", () => {
  for (const value of [0, -1, 1.5, "10", null, 10001]) {
    assert.throws(() => adminQuote(admin, value),
        (error) => error.httpStatus === 400);
  }
});

test("ADMIN rejects malformed published grids", () => {
  assert.throws(() =>
    adminQuote({...admin, publishedPrices: [499]}, 1),
  (error) => error.httpStatus === 503);
});


const {initialPrices} = require("../advertiser_radius_tariffs");
const prices = initialPrices();
const advertiser = {
  type: "ADVERTISER_RADIUS", country: "FR", currency: "EUR",
  publishedVersion: 1, publishedPrices: prices,
};

test("The 108 user-approved reference amounts are present", () => {
  assert.equal(Object.keys(prices).length, 108);
  const cases = [
    ["radius_5km", "map", "1 semaine", 49],
    ["radius_5km", "pack", "1 an", 2539],
    ["radius_15km", "premium", "1 an", 3009],
    ["radius_50km", "map", "1 mois", 399],
    ["radius_150km", "pack", "6 mois", 5559],
    ["radius_300km", "pack", "1 an", 10600],
    ["country", "map", "1 an", 4900],
    ["country", "premium", "1 an", 8900],
    ["country", "pack", "1 an", 11900],
  ];
  for (const [territory, offer, duration, expected] of cases) {
    const quote = advertiserQuote(advertiser, territory, offer, duration);
    assert.equal(quote.amountExclTax, expected);
    assert.equal(quote.market, "ADVERTISER_RADIUS");
    assert.equal(quote.pricingReference, "FR_ADVERTISER_RADIUS-V1");
  }
});

test("Legacy five-level offers and 500km are not quoted", () => {
  for (const territory of [
    "commune", "intercommunalite", "departement",
    "region", "national", "radius_500km",
  ]) {
    assert.throws(() =>
      advertiserQuote(advertiser, territory, "map", "1 semaine"),
    (error) => error.httpStatus === 400);
  }
  assert.throws(() => advertiserQuote({
    ...advertiser, type: "ADVERTISER",
  }, "country", "map", "1 semaine"),
  (error) => error.httpStatus === 503);
});

test("Incomplete 108-price catalogs cannot be quoted", () => {
  const incomplete = {...prices};
  delete incomplete["5:2:5"];
  assert.throws(() =>
    advertiserQuote({...advertiser, publishedPrices: incomplete},
        "country", "pack", "1 an"),
  (error) => error.httpStatus === 503);
  const extra = {...prices, "6:0:0": 1};
  assert.throws(() =>
    advertiserQuote({...advertiser, publishedPrices: extra},
        "country", "pack", "1 an"),
  (error) => error.httpStatus === 503);
});

test("Only a published Firestore catalog can be quoted", () => {
  assert.throws(() => publishedState({exists: false}, "ADMIN"),
      (error) => error.httpStatus === 503);
  assert.throws(() => publishedState({
    exists: true, data: () => ({...admin, publishedVersion: null}),
  }, "ADMIN"), (error) => error.httpStatus === 503);
});

