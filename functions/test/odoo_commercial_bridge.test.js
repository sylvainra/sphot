/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildOdooDraft} = require("../odoo_commercial_bridge");

const base = {
  market: "ADVERTISER_RADIUS",
  version: 2,
  pricingReference: "FR_ADVERTISER_RADIUS-V2",
  currency: "EUR",
  amountExclTax: 100,
  territory: "radius_15km",
  offer: "pack",
  duration: "1 mois",
  discountPercent: 10,
  payableExclTaxCents: 9000,
};

test("Odoo: commande annonceur sans TVA SPHOT et remise nominative", () => {
  const result = buildOdooDraft({
    quote: base, partnerId: 1234,
    productIds: {advertiser: 42},
    sphotReference: "SPHOT-TEST-001",
  });
  assert.equal(result.model, "sale.order");
  assert.equal(result.method, "create");
  assert.equal(result.values.partner_id, 1234);
  assert.equal(result.values.client_order_ref, "SPHOT-TEST-001");
  assert.equal(result.values.order_line[0][2].discount, 10);
  assert.equal(result.values.order_line[0][2].price_unit, 100);
  assert.equal(result.expectedUntaxedCents, 9000);
  assert.equal(result.automaticRenewal, false);
  assert.equal(result.paymentState, "not_started");
  assert.equal(result.values.taxes_id, undefined);
});

test("Odoo: postes Admin selon quatre tranches, sans total fictif", () => {
  const lines = [1, 3, 5, 1].map((count, i) => ({
    count, unitExclTax: 500 - i * 100,
    amountExclTax: count * (500 - i * 100),
  }));
  const sum = lines.reduce((total, l) => total + l.amountExclTax, 0);
  const result = buildOdooDraft({
    quote: {
      market: "ADMIN", version: 3, pricingReference: "FR_ADMIN-V3",
      currency: "EUR", amountExclTax: sum,
      discountPercent: 5, payableExclTaxCents: Math.round(sum * 95),
      lines,
    },
    partnerId: 12, productIds: {adminTiers: [1, 2, 3, 4]},
    sphotReference: "SPHOT-ADMIN-01",
  });
  assert.equal(result.values.order_line.length, 4);
  assert.ok(result.values.order_line.every((l) => l[2].discount === 5));
});

test("Odoo: refuse devis non certifie et identifiants absents", () => {
  const valid = {
    quote: base, partnerId: 1, productIds: {advertiser: 42},
    sphotReference: "SPHOT-TEST-001",
  };
  assert.throws(() => buildOdooDraft({...valid,
    quote: {...base, pricingReference: "FR_ADVERTISER-V2"},
  }));
  assert.throws(() => buildOdooDraft({...valid, partnerId: null}));
  assert.throws(() => buildOdooDraft({...valid,
    productIds: {advertiser: 0},
  }));
  assert.throws(() => buildOdooDraft({...valid,
    quote: {...base, discountPercent: 110},
  }));
});
