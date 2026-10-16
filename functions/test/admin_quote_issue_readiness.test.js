/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  assessAdminQuoteIssueReadiness,
} = require("../admin_quote_issue_readiness");

function verifiedFixture() {
  return {
    issuedOn: "2026-10-15",
    subscriptionYear: 2026,
    issuer: {
      legalName: "Editeur fictif de test",
      country: "FR", siret: "12345678901234",
      address: "1 rue Exemple", postalCode: "75001", city: "Paris",
      legalRegistrationVerified: true, commercialIssuanceEnabled: true,
    },
    buyer: {
      legalName: "Commune fictive de test",
      country: "FR", siret: "12345678901234",
      address: "2 rue Exemple", postalCode: "75002", city: "Paris",
      billingEmail: "factures@example.invalid",
      legalIdentityVerified: true, isDifferentFromManager: false,
    },
    stations: [
      {spotDocumentId: "spot-1", name: "Poste 1",
        isRescueStation: true, belongsToAdminTerritory: true},
      {spotDocumentId: "spot-2", name: "Poste 2",
        isRescueStation: true, belongsToAdminTerritory: true},
    ],
    publishedQuote: {
      market: "ADMIN", country: "FR", currency: "EUR",
      version: 3, pricingReference: "FR_ADMIN-V3",
      fromServerPublishedCatalog: true,
      numberOfRescueStations: 2, amountExclTax: 898,
      lines: [
        {tier: 1, count: 1, unitExclTax: 499, amountExclTax: 499},
        {tier: 2, count: 1, unitExclTax: 399, amountExclTax: 399},
        {tier: 3, count: 0, unitExclTax: 299, amountExclTax: 0},
        {tier: 4, count: 0, unitExclTax: 199, amountExclTax: 0},
      ],
    },
    taxDecision: {
      status: "validated", jurisdiction: "FR", currency: "EUR",
      taxTreatment: "test_only", legalBasis: "test_only",
      amountExclTax: 898, taxAmount: 0, amountInclTax: 898,
      calculationVerified: true,
    },
  };
}

test("Aucun contexte ne peut préparer un devis officiel", () => {
  const result = assessAdminQuoteIssueReadiness();
  assert.equal(result.ready, false);
  assert.equal(result.validity, null);
  assert.ok(result.issues.includes("ISSUER_NOT_LEGALLY_VERIFIED"));
  assert.ok(result.issues.includes("OFFICIAL_ISSUANCE_NOT_AUTHORIZED"));
  assert.ok(result.issues.includes("TAX_TREATMENT_NOT_VERIFIED"));
});

test("Contexte complet et attesté côté serveur : validité de 30 jours", () => {
  // Fixture UNIQUEMENT pour tester les invariants, pas un devis commercial.
  const result = assessAdminQuoteIssueReadiness(verifiedFixture());
  assert.equal(result.ready, true);
  assert.deepEqual(result.issues, []);
  assert.equal(result.validity.validUntil, "2026-11-13");
});

test("Émetteur non immatriculé ou émission désactivée : blocage", () => {
  const c = verifiedFixture();
  c.issuer.legalRegistrationVerified = false;
  c.issuer.commercialIssuanceEnabled = false;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("ISSUER_NOT_LEGALLY_VERIFIED"));
  assert.ok(result.issues.includes("OFFICIAL_ISSUANCE_NOT_AUTHORIZED"));
});

test("L'identité d'un organisme payeur doit être vérifiée", () => {
  const c = verifiedFixture();
  c.buyer.siret = "0123";
  c.buyer.legalIdentityVerified = false;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("BUYER_NOT_LEGALLY_VERIFIED"));
});

test("Payeur différent du gestionnaire : habilitation obligatoire", () => {
  const c = verifiedFixture();
  c.buyer.isDifferentFromManager = true;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("THIRD_PARTY_PAYER_NOT_AUTHORIZED"));
});

test("Les postes doivent appartenir au périmètre et être uniques", () => {
  const c = verifiedFixture();
  c.stations[1].spotDocumentId = "spot-1";
  c.stations[1].belongsToAdminTerritory = false;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("RESCUE_STATIONS_NOT_VERIFIED"));
});

test("La grille publiée et les lignes doivent être recalculées au serveur", () => {
  const c = verifiedFixture();
  c.publishedQuote.lines[0].amountExclTax = 500;
  c.publishedQuote.fromServerPublishedCatalog = false;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("PUBLISHED_PRICE_NOT_REVALIDATED"));
});

test("La somme des quantités des tranches doit égaler les postes", () => {
  const c = verifiedFixture();
  c.publishedQuote.lines[1].count = 0;
  c.publishedQuote.lines[1].amountExclTax = 0;
  c.publishedQuote.amountExclTax = 499;
  c.taxDecision.amountExclTax = 499;
  c.taxDecision.amountInclTax = 499;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("PUBLISHED_PRICE_NOT_REVALIDATED"));
});

test("Aucun taux ni montant TTC ne peut être présumé", () => {
  const c = verifiedFixture();
  c.taxDecision.calculationVerified = false;
  c.taxDecision.amountInclTax = 1077;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("TAX_TREATMENT_NOT_VERIFIED"));
});

test("Une fiscalité vérifiée peut comporter des centimes", () => {
  const c = verifiedFixture();
  c.taxDecision.taxAmount = 179.60;
  c.taxDecision.amountInclTax = 1077.60;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, true);
  assert.deepEqual(result.issues, []);
});

test("Un montant avec plus de deux décimales n'est pas accepté", () => {
  const c = verifiedFixture();
  c.taxDecision.taxAmount = 179.601;
  c.taxDecision.amountInclTax = 1077.601;
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, false);
  assert.ok(result.issues.includes("TAX_TREATMENT_NOT_VERIFIED"));
});

test("La validité contractuelle est plafonnée au 31 décembre", () => {
  const c = verifiedFixture();
  c.issuedOn = "2026-12-20";
  const result = assessAdminQuoteIssueReadiness(c);
  assert.equal(result.ready, true);
  assert.equal(result.validity.validUntil, "2026-12-31");
});

test("Aucun document n'est créé par le contrôleur de prérequis", () => {
  const c = verifiedFixture();
  const before = JSON.stringify(c);
  const first = assessAdminQuoteIssueReadiness(c);
  const second = assessAdminQuoteIssueReadiness(c);
  assert.equal(JSON.stringify(c), before);
  assert.deepEqual(first, second);
  assert.equal(Object.hasOwn(first, "quoteNumber"), false);
});
