/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  VALIDITY_DAYS,
  quoteValidityForCalendarYear,
} = require("../admin_quote_validity");

test("La durée de référence est exactement de 30 jours calendaires", () => {
  assert.equal(VALIDITY_DAYS, 30);
  assert.deepEqual(quoteValidityForCalendarYear("2026-10-14", 2026), {
    issuedOn: "2026-10-14",
    validUntil: "2026-11-12",
    validityDaysMaximum: 30,
    subscriptionYear: 2026,
    expiresAtYearEnd: false,
  });
});

test("Le devis expire au plus tard le 31 décembre de l'année concernée", () => {
  assert.deepEqual(quoteValidityForCalendarYear("2026-12-20", 2026), {
    issuedOn: "2026-12-20",
    validUntil: "2026-12-31",
    validityDaysMaximum: 30,
    subscriptionYear: 2026,
    expiresAtYearEnd: true,
  });
  assert.equal(
      quoteValidityForCalendarYear("2026-12-31", 2026).validUntil,
      "2026-12-31",
  );
});

test("Les jours calendaires traversent février et les années bissextiles", () => {
  assert.equal(
      quoteValidityForCalendarYear("2028-02-10", 2028).validUntil,
      "2028-03-10",
  );
});

test("Un devis pour l'année suivante garde sa validité de 30 jours", () => {
  assert.equal(
      quoteValidityForCalendarYear("2026-10-14", 2027).validUntil,
      "2026-11-12",
  );
});

test("Refuser les dates invalides, les années invalides et devis tardifs", () => {
  assert.throws(() => quoteValidityForCalendarYear("2026-02-30", 2026));
  assert.throws(() => quoteValidityForCalendarYear("14/10/2026", 2026));
  assert.throws(() => quoteValidityForCalendarYear("2027-01-01", 2026));
  assert.throws(() => quoteValidityForCalendarYear("2026-10-14", "2026"));
});
