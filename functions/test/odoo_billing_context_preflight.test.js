"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {assertPreview, previewBillingFromOdoo} =
  require("../odoo_billing_context_preflight");
const id = "admin_1234567890";
const cycle = "INITIAL_2026";
const siret = "12345678901234";
const reference = "SPHOT-ADM-" + crypto.createHash("sha256")
    .update(JSON.stringify(["ADMIN", id, cycle])).digest("hex")
    .slice(0, 24).toUpperCase();
const quote = {market: "ADMIN", version: 1,
  pricingReference: "FR_ADMIN-V1", country: "FR", currency: "EUR",
  amountExclTax: 500, discountPercent: 0, payableExclTaxCents: 50000,
  lines: [
    {count: 1, unitExclTax: 500, amountExclTax: 500},
    ...Array.from({length: 3}, () => ({count: 0, unitExclTax: 500,
      amountExclTax: 0})),
  ],
};
const valid = {contract: "sphot_odoo_billing_preview_v1", market: "ADMIN",
  reference, partnerId: 45, buyerActive: true, buyerCompany: true,
  billingAddressComplete: true, buyerCountry: "FR", buyerLegalId: siret,
  buyerSiret: siret, currency: "EUR", fiscalPositionId: 8,
  productIds: [11], amountUntaxedCents: 50000, amountTaxCents: 10000,
  amountTotalCents: 60000, testOnly: false};
const orderValues = {order_line: [[0, 0, {product_id: 11}]]};
const args = {market: "ADMIN", reference, partnerId: 45,
  quote, billingSiret: siret, orderValues};

test("Odoo: retour fiscal complet, TTC calcule cote Odoo", () => {
  const v = assertPreview(valid, args);
  assert.equal(v.expectedTotalCents, 60000);
  assert.match(v.buyerEvidenceId, /^ODOO_BUYER_/);
  assert.match(v.taxEvidenceId, /^ODOO_TAX_/);
});
for (const [label, change] of [
  ["partenaire", {partnerId: 46}], ["siret", {buyerSiret: "00000000000000"}],
  ["devise", {currency: "USD"}], ["fiscalite", {fiscalPositionId: null}],
  ["montant HT", {amountUntaxedCents: 49999}],
  ["montant TTC", {amountTotalCents: 59000}],
  ["adresse", {billingAddressComplete: false}],
  ["produits", {productIds: [12]}], ["test", {testOnly: true}],
]) {
  test(`Odoo: ${label} incoherent refuse`, () => {
    assert.throws(() => assertPreview({...valid, ...change}, args));
  });
}
test("Odoo: lecture uniquement, aucune commande creee", async () => {
  let calls = 0;
  const odooClient = {async call(model, method, payload) {
    calls++;
    assert.equal(model, "sphot.admin.checkout");
    assert.equal(method, "preview_billing_context");
    assert.deepEqual(Object.keys(payload).sort(),
        ["order_values", "sphot_reference"]);
    return valid;
  }};
  const proof = await previewBillingFromOdoo({odooClient,
    identity: {market: "ADMIN", requestId: id},
    cycleKey: cycle, quote, productIds: {adminTiers: [11, 12, 13, 14]},
    partnerId: 45, billingSiret: siret,
    draftBuilder: ({quote, partnerId, sphotReference}) => ({
      expectedUntaxedCents: quote.payableExclTaxCents,
      values: {client_order_ref: sphotReference, partner_id: partnerId,
        order_line: [[0, 0, {product_id: 11}]]},
    }),
  });
  assert.equal(calls, 1);
  assert.equal(proof.expectedUntaxedCents, 50000);
});
test("Odoo: liaison Odoo manquante bloque sans substitution", async () => {
  await assert.rejects(() => previewBillingFromOdoo({
    identity: {market: "ADMIN", requestId: id}, cycleKey: cycle,
    quote, productIds: {adminTiers: [11, 12, 13, 14]},
    partnerId: 45, billingSiret: siret,
  }));
});

test("Odoo: annonceur, devis et TVA controlees", async () => {
  const requestId = "advertiser_123456";
  const r = "SPHOT-PUB-" + crypto.createHash("sha256")
      .update(JSON.stringify(["ADVERTISER", requestId, cycle]))
      .digest("hex").slice(0, 24).toUpperCase();
  const q = {market: "ADVERTISER_RADIUS", version: 1,
    pricingReference: "FR_ADVERTISER_RADIUS-V1", country: "FR",
    currency: "EUR", amountExclTax: 149, discountPercent: 0,
    payableExclTaxCents: 14900, territory: "radius_5km",
    offer: "map", duration: "1 mois"};
  const v = {...valid, market: "ADVERTISER", reference: r,
    amountUntaxedCents: 14900, amountTaxCents: 2980,
    amountTotalCents: 17880, productIds: [21]};
  const proof = await previewBillingFromOdoo({
    odooClient: {async call(model, method) {
      assert.equal(model, "sphot.advertiser.checkout");
      assert.equal(method, "preview_billing_context");
      return v;
    }},
    identity: {market: "ADVERTISER", requestId}, cycleKey: cycle,
    quote: q, partnerId: 45, productIds: {advertiser: 21},
    draftBuilder: ({quote, partnerId, sphotReference}) => ({
      expectedUntaxedCents: quote.payableExclTaxCents,
      values: {client_order_ref: sphotReference, partner_id: partnerId,
        order_line: [[0, 0, {product_id: 21}]]},
    }),
  });
  assert.equal(proof.expectedTotalCents, 17880);
});
