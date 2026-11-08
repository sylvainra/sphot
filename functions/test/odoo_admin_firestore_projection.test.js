/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {adminQuote} = require("../commercial_quote_pricing");
const {computeDiscountCents} = require("../commercial_discounts");
const {prepareAdminCheckout} =
  require("../local/odoo_admin_checkout_contract");
const {SOURCE, buildAdminActivationProjection, dueActions} =
  require("../local/odoo_admin_firestore_projection");

function prepared(paymentMethod = "public_invoice") {
  const base = adminQuote({publishedVersion: 3,
    publishedPrices: [499, 399, 299, 199]}, 3);
  const quote = {...base, ...computeDiscountCents(base.amountExclTax, 10),
    fromServerPublishedCatalog: true};
  const amountExclTax = quote.payableExclTaxCents / 100;
  const taxAmount = Math.round(quote.payableExclTaxCents * 0.2) / 100;
  return prepareAdminCheckout({
    adminUid: "admin_uid_001", requestId: "admin_uid_001",
    cycleId: "cycle_2026_001", year: 2026,
    approval: {status: "approved", adminUid: "admin_uid_001",
      territoireId: "territoire_001", siret: "21630123400012",
      siren: "216301234"},
    buyer: {verified: true, relation: "manager", siret: "21630123400012",
      legalName: "Commune de Test", billingEmail: "compta@example.fr"},
    stations: ["station_001", "station_002", "station_003"].map(
        (spotDocumentId) => ({spotDocumentId,
          belongsToAdminTerritory: true, isRescueStation: true})),
    quote,
    fiscality: {status: "validated", calculationVerified: true,
      amountExclTax, taxAmount,
      amountInclTax: amountExclTax + taxAmount,
      legalBasis: "TAX_DECISION_TEST"},
    legalAcceptance: {verified: true, adminUid: "admin_uid_001",
      version: "CGV_ADMIN_V3", acceptedAt: "2026-10-31T12:00:00Z"},
    paymentMethod, partnerId: 42,
    adminTierProductIds: [11, 12, 13, 14],
  });
}

function status(prep, invoice = null) {
  return {order: {id: 77, name: "S00077", state: "sale",
    client_order_ref: prep.reference,
    x_sphot_reference: prep.reference,
    x_sphot_fingerprint: prep.fingerprint}, invoice};
}

function commitment(prep) {
  return {status: "verified", orderReference: prep.reference,
    orderFingerprint: prep.fingerprint,
    documentHash: "sha256-contract-test", verificationSource: "super_admin",
    verifiedAt: "2026-10-31T12:00:00Z"};
}

test("ADMIN Firestore : engagement validé active jusqu'au 31 décembre", () => {
  const prep = prepared();
  const projection = buildAdminActivationProjection({prepared: prep,
    verifiedOdooStatus: status(prep), commitment: commitment(prep),
    activatedAt: new Date("2026-10-31T12:00:00Z")});
  assert.equal(projection.cycleCollection, "adminOdooCycles");
  assert.equal(projection.cycle.source, SOURCE);
  assert.equal(projection.cycle.paymentStatus, "not_paid");
  assert.equal(projection.cycle.odooInvoiceId, null);
  assert.equal(projection.subscriptionCollection, "subscriptions");
  assert.equal(projection.subscriptionDocumentId, "admin_uid_001");
  assert.equal(projection.subscriptionPatch.odooAdminManaged, true);
  assert.equal(projection.subscriptionPatch.status, "active");
  assert.deepEqual(projection.subscriptionPatch.selectedRescueStationIds,
      ["station_001", "station_002", "station_003"]);
  assert.equal(projection.subscriptionPatch.subscriptionEndDate.toISOString(),
      "2026-12-31T22:59:59.999Z");
  assert.equal(projection.cycle.validUntilExclusive.toISOString(),
      "2026-12-31T23:00:00.000Z");
});

test("ADMIN Firestore : simple numéro de BC ou preuve absente n'active pas", () => {
  const prep = prepared();
  assert.throws(() => buildAdminActivationProjection({prepared: prep,
    verifiedOdooStatus: status(prep),
    commitment: {status: "verified", engagementNumber: "BC-123"},
    activatedAt: new Date("2026-10-31T12:00:00Z")}), /refusée/);
});

test("ADMIN Firestore : carte sans facture Odoo payée n'active pas", () => {
  const prep = prepared("card");
  const payment = {provider: "stripe", transactionState: "done",
    invoiceState: "posted", invoicePaymentState: "paid",
    invoiceTotalCents: prep.expectedTotalCents, amountResidualCents: 0,
    orderReference: prep.reference};
  assert.throws(() => buildAdminActivationProjection({prepared: prep,
    verifiedOdooStatus: status(prep), payment,
    activatedAt: new Date("2026-10-31T12:00:00Z")}), /facture/);
  const projection = buildAdminActivationProjection({prepared: prep,
    verifiedOdooStatus: status(prep, {id: 88}), payment,
    activatedAt: new Date("2026-10-31T12:00:00Z")});
  assert.equal(projection.cycle.activationBasis, "stripe_verified");
  assert.equal(projection.cycle.odooInvoiceId, 88);
  assert.equal(projection.cycle.paymentStatus, "paid");
});

test("ADMIN Firestore : référence altérée ou année expirée sont bloquées", () => {
  const prep = prepared();
  const instant = new Date("2026-10-31T12:00:00Z");
  assert.throws(() => buildAdminActivationProjection({prepared: prep,
    verifiedOdooStatus: {order: {...status(prep).order,
      x_sphot_fingerprint: "other"}}, commitment: commitment(prep),
    activatedAt: instant}), /refusée/);
  assert.throws(() => buildAdminActivationProjection({prepared: prep,
    verifiedOdooStatus: status(prep), commitment: commitment(prep),
    activatedAt: new Date("2027-01-01T00:00:00Z")}), /période/);
});

test("ADMIN impayés : J+7, J+15 et revue J+30, aucune suspension", () => {
  const common = {dueDate: "2026-11-01", amountResidualCents: 140076,
    invoicePaymentState: "not_paid"};
  const on = (date) => dueActions({...common, asOfDate: new Date(date)});
  assert.deepEqual(on("2026-11-07T12:00:00Z").actionsDue, []);
  assert.deepEqual(on("2026-11-08T12:00:00Z").actionsDue,
      ["reminder_j7"]);
  assert.deepEqual(on("2026-11-16T12:00:00Z").actionsDue,
      ["reminder_j7", "reminder_j15"]);
  assert.deepEqual(on("2026-12-01T12:00:00Z").actionsDue,
      ["reminder_j7", "reminder_j15", "manual_review_j30"]);
  assert.equal(on("2026-12-01T12:00:00Z").suspendAccess, false);
});

test("ADMIN impayés : Odoo payé ne déclenche aucune relance", () => {
  assert.deepEqual(dueActions({dueDate: "2026-11-01",
    asOfDate: new Date("2026-12-01T12:00:00Z"),
    amountResidualCents: 0, invoicePaymentState: "paid"}),
  {daysLate: 0, actionsDue: [], paymentStatus: "paid", suspendAccess: false});
});

test("ADMIN impayés : réconciliation et date Odoo invalides refusées", () => {
  assert.throws(() => dueActions({dueDate: "2026-02-30",
    asOfDate: new Date("2026-03-31T12:00:00Z"),
    amountResidualCents: 100, invoicePaymentState: "not_paid"}),
  /date impossible/);
  assert.throws(() => dueActions({dueDate: "2026-11-01",
    asOfDate: new Date("2026-12-01T12:00:00Z"),
    amountResidualCents: 100, invoicePaymentState: "paid"}),
  /réconciliation Odoo/);
});
