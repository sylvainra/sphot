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

const prices = {};
for (let t = 0; t < 5; t++) {
  for (let o = 0; o < 3; o++) {
    for (let d = 0; d < 6; d++) {
      prices[t + ":" + o + ":" + d] = 10 + t * 1000 + o * 100 + d;
    }
  }
}
const advertiser = {
  type: "ADVERTISER", country: "FR", currency: "EUR",
  publishedVersion: 3, publishedPrices: prices,
};

test("ADVERTISER reads an exact published cell and version", () => {
  const quote = advertiserQuote(
      advertiser, "national", "pack", "1 an",
  );
  assert.equal(quote.amountExclTax, 4215);
  assert.equal(quote.tariffKey, "4:2:5");
  assert.equal(quote.pricingReference, "FR_ADVERTISER-V3");
  assert.equal(quote.previewOnly, undefined);
});

test("ADVERTISER refuses unsupported territory, offer or duration", () => {
  for (const choices of [
    ["rayon_5km", "map", "1 mois"],
    ["commune", "exclusive", "1 mois"],
    ["commune", "map", "10 jours"],
  ]) {
    assert.throws(() => advertiserQuote(advertiser, ...choices),
        (error) => error.httpStatus === 400);
  }
});

test("ADVERTISER fails closed on incomplete catalog", () => {
  assert.throws(() => advertiserQuote(
      {...advertiser, publishedPrices: {"4:2:5": 11900}},
      "national", "pack", "1 an",
  ), (error) => error.httpStatus === 503);
});

test("Only a published Firestore catalog can be quoted", () => {
  assert.throws(() => publishedState({exists: false}, "ADMIN"),
      (error) => error.httpStatus === 503);
  assert.throws(() => publishedState({
    exists: true, data: () => ({...admin, publishedVersion: null}),
  }, "ADMIN"), (error) => error.httpStatus === 503);
});
