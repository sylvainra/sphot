/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {adminQuote} = require("../commercial_quote_pricing");
const {computeDiscountCents} = require("../commercial_discounts");
const {referenceFor, prepareAdminCheckout, assessActivation} =
  require("../local/odoo_admin_checkout_contract");

const UID = "admin_uid_001";
const SIRET = "21630123400012";

function fixture(paymentMethod = "public_invoice") {
  const base = adminQuote({publishedVersion: 3,
    publishedPrices: [499, 399, 299, 199]}, 3);
  const quote = {...base, ...computeDiscountCents(base.amountExclTax, 10),
    fromServerPublishedCatalog: true};
  const ht = quote.payableExclTaxCents / 100;
  const tax = Math.round(quote.payableExclTaxCents * 0.2) / 100;
  return {
    adminUid: UID, requestId: UID, cycleId: "cycle_2026_001", year: 2026,
    approval: {status: "approved", adminUid: UID,
      territoireId: "territoire_001", siret: SIRET,
      siren: SIRET.slice(0, 9)},
    buyer: {verified: true, relation: "manager", siret: SIRET,
      legalName: "Commune de Test", billingEmail: "compta@example.fr"},
    stations: ["station_001", "station_002", "station_003"].map(
        (spotDocumentId) => ({spotDocumentId,
          belongsToAdminTerritory: true, isRescueStation: true})),
    quote,
    fiscality: {status: "validated", calculationVerified: true,
      amountExclTax: ht, taxAmount: tax,
      amountInclTax: ht + tax, legalBasis: "TAX_DECISION_TEST"},
    legalAcceptance: {verified: true, adminUid: UID,
      version: "CGV_ADMIN_V3", acceptedAt: "2026-10-31T12:00:00Z"},
    paymentMethod, partnerId: 42,
    adminTierProductIds: [11, 12, 13, 14],
  };
}

function order(prepared) {
  return {reference: prepared.reference,
    fingerprint: prepared.fingerprint, state: "sale"};
}

function commitment(prepared) {
  return {status: "verified", orderReference: prepared.reference,
    orderFingerprint: prepared.fingerprint,
    documentHash: "sha256-test-document", verifiedAt: "2026-10-31T12:00:00Z",
    verificationSource: "institutional_review_test"};
}

test("ADMIN : référence déterministe distincte du parcours PUBLICITAIRE", () => {
  const a = referenceFor(UID, "cycle_2026_001", 2026);
  assert.match(a, /^SPHOT-ADM-TEST-[A-F0-9]{16}$/);
  assert.equal(a, referenceFor(UID, "cycle_2026_001", 2026));
  assert.notEqual(a, referenceFor(UID, "cycle_2027_001", 2027));
  assert.notEqual(a, referenceFor(UID, "cycle_2026_002", 2026));
});

test("ADMIN : prépare les tranches Odoo et fige tarif, taxes et CGV", () => {
  const input = fixture();
  const prepared = prepareAdminCheckout(input);
  assert.equal(prepared.testOnly, true);
  assert.equal(prepared.expectedUntaxedCents, 116730);
  assert.equal(prepared.expectedTotalCents, 140076);
  assert.equal(prepared.orderValues.client_order_ref, prepared.reference);
  assert.equal(prepared.orderValues.order_line.length, 2);
  const first = prepared.orderValues.order_line[0][2];
  const second = prepared.orderValues.order_line[1][2];
  assert.deepEqual([first.product_id, first.product_uom_qty,
    first.price_unit, first.discount], [11, 1, 499, 10]);
  assert.deepEqual([second.product_id, second.product_uom_qty,
    second.price_unit, second.discount], [12, 2, 399, 10]);
  assert.equal(prepared.locked.cgvVersion, "CGV_ADMIN_V3");
  assert.equal(prepared.locked.stationIds.length, 3);
});

test("ADMIN : une relecture identique conserve la même empreinte", () => {
  const input = fixture();
  const first = prepareAdminCheckout(input);
  const next = prepareAdminCheckout({...input,
    stations: [...input.stations].reverse()});
  assert.equal(first.reference, next.reference);
  assert.equal(first.fingerprint, next.fingerprint);
  const changed = fixture();
  changed.legalAcceptance.version = "CGV_ADMIN_V4";
  assert.notEqual(first.fingerprint, prepareAdminCheckout(changed).fingerprint);
});

test("ADMIN : sans approbation administrative cohérente, aucun brouillon", () => {
  const input = fixture();
  input.approval.siren = "123456789";
  assert.throws(() => prepareAdminCheckout(input),
      /Identité administrative/);
});

test("ADMIN : un payeur distinct doit être vérifié et habilité", () => {
  const input = fixture();
  input.buyer = {...input.buyer, relation: "other",
    siret: "55210055400013"};
  assert.throws(() => prepareAdminCheckout(input), /payeur non vérifié/);
  input.buyer.thirdPartyBillingAuthorized = true;
  assert.doesNotThrow(() => prepareAdminCheckout(input));
});

test("ADMIN : refus des postes doublonnés ou hors du territoire", () => {
  const input = fixture();
  input.stations[1].spotDocumentId = input.stations[0].spotDocumentId;
  assert.throws(() => prepareAdminCheckout(input), /postes non vérifiée/);
  input.stations[1].spotDocumentId = "station_002";
  input.stations[1].belongsToAdminTerritory = false;
  assert.throws(() => prepareAdminCheckout(input), /postes non vérifiée/);
});

test("ADMIN : devis, fiscalité et CGV non attestés bloquent la commande", () => {
  const missingPrice = fixture();
  missingPrice.quote.fromServerPublishedCatalog = false;
  assert.throws(() => prepareAdminCheckout(missingPrice), /Grille publiée/);
  const tax = fixture();
  tax.fiscality.amountInclTax += 1;
  assert.throws(() => prepareAdminCheckout(tax), /Fiscalité/);
  const legal = fixture();
  legal.legalAcceptance.verified = false;
  assert.throws(() => prepareAdminCheckout(legal), /CGV/);
});

test("ADMIN : produits Odoo de tranches distincts obligatoires", () => {
  const input = fixture();
  input.adminTierProductIds[1] = input.adminTierProductIds[0];
  assert.throws(() => prepareAdminCheckout(input), /Configuration Odoo/);
});

test("ADMIN : engagement vérifié active sans exiger de facture payée", () => {
  const prepared = prepareAdminCheckout(fixture());
  assert.deepEqual(assessActivation({prepared, order: order(prepared),
    commitment: commitment(prepared)}), {
    allowed: true, basis: "verified_public_commitment",
    paymentStatus: "not_paid"});
  assert.equal(assessActivation({prepared, order: order(prepared),
    commitment: {...commitment(prepared), status: "pending"}}).allowed, false);
});

test("ADMIN : un numéro ou une preuve liée à une autre commande ne suffit pas", () => {
  const prepared = prepareAdminCheckout(fixture());
  assert.equal(assessActivation({prepared, order: order(prepared),
    commitment: {status: "verified", engagementNumber: "BC-001"}}).allowed,
  false);
  assert.equal(assessActivation({prepared, order: order(prepared),
    commitment: {...commitment(prepared), orderReference: "other"}}).allowed,
  false);
});

test("ADMIN : la carte exige une facture payée et Stripe confirmé", () => {
  const prepared = prepareAdminCheckout(fixture("card"));
  const payment = {provider: "stripe", transactionState: "done",
    invoiceState: "posted", invoicePaymentState: "paid",
    amountResidualCents: 0, invoiceTotalCents: prepared.expectedTotalCents,
    orderReference: prepared.reference};
  assert.deepEqual(assessActivation({prepared, order: order(prepared),
    payment}), {allowed: true, basis: "stripe_verified",
    paymentStatus: "paid"});
  assert.equal(assessActivation({prepared, order: order(prepared),
    payment: {...payment, invoicePaymentState: "in_payment"}}).allowed, false);
});

test("ADMIN : aucune activation sans commande Odoo cohérente", () => {
  const prepared = prepareAdminCheckout(fixture());
  assert.equal(assessActivation({prepared, order: {...order(prepared),
    fingerprint: "incorrect"}, commitment: commitment(prepared)}).allowed,
  false);
});
