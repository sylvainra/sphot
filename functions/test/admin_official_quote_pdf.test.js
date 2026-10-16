/* eslint-disable max-len, require-jsdoc, valid-jsdoc, object-curly-spacing */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  renderOfficialAdminQuotePdf,
  renderConsultableAdminQuotePdf,
  adminQuoteDocumentDefinition,
} = require("../admin_official_quote_pdf");

function completeTestContext() {
  // Fixtures fictives : PDF produit UNIQUEMENT en mémoire, sans émission.
  return {
    issuedOn: "2026-10-15",
    subscriptionYear: 2026,
    issuer: {
      legalName: "Émetteur fictif (test technique uniquement)",
      country: "FR", siret: "12345678901234",
      address: "1 rue Test", postalCode: "75001", city: "Paris",
      legalRegistrationVerified: true,
      commercialIssuanceEnabled: true,
    },
    buyer: {
      legalName: "Organisme fictif (test technique uniquement)",
      country: "FR", siret: "12345678901234",
      address: "2 rue Test", postalCode: "75002", city: "Paris",
      billingEmail: "facturation@example.invalid",
      legalIdentityVerified: true,
      isDifferentFromManager: false,
    },
    stations: [
      {
        spotDocumentId: "station-1",
        idSphot: "LONGE 09",
        name: "PLAGE DU ROCHER",
        isRescueStation: true,
        belongsToAdminTerritory: true,
      },
      {
        spotDocumentId: "station-2",
        idSphot: "LONGE 13",
        name: "PLAGE DES CONCHES",
        isRescueStation: true,
        belongsToAdminTerritory: true,
      },
    ],
    publishedQuote: {
      market: "ADMIN",
      country: "FR",
      currency: "EUR",
      version: 3,
      pricingReference: "FR_ADMIN-V3",
      fromServerPublishedCatalog: true,
      numberOfRescueStations: 2,
      amountExclTax: 898,
      lines: [
        {tier: 1, count: 1, unitExclTax: 499, amountExclTax: 499},
        {tier: 2, count: 1, unitExclTax: 399, amountExclTax: 399},
        {tier: 3, count: 0, unitExclTax: 299, amountExclTax: 0},
        {tier: 4, count: 0, unitExclTax: 199, amountExclTax: 0},
      ],
    },
    taxDecision: {
      status: "validated",
      jurisdiction: "FR",
      taxTreatment: "Régime fictif pour les tests",
      legalBasis: "Fondement fictif pour les tests",
      currency: "EUR",
      amountExclTax: 898,
      taxAmount: 179.60,
      amountInclTax: 1077.60,
      calculationVerified: true,
    },
  };
}

const CASE_REFERENCE = "SPHOT-ADM-FRA-2026-000001";
const CASE_DV = "DV-2026-000001-001";

test("Devis PDF interdit si SPHOT n'est pas immatriculé", () => {
  const context = completeTestContext();
  context.issuer.legalRegistrationVerified = false;
  assert.throws(
      () => renderOfficialAdminQuotePdf(context, CASE_DV, CASE_REFERENCE),
      {code: "QUOTE_NOT_READY"},
  );
});

test("Le moteur refuse l'absence de numéro DV officiel", () => {
  assert.throws(
      () => renderOfficialAdminQuotePdf(
          completeTestContext(), "", CASE_REFERENCE,
      ),
      /Numéro DV officiel/,
  );
});

test("Le moteur refuse une mauvaise année de devis", () => {
  assert.throws(
      () => renderOfficialAdminQuotePdf(
          completeTestContext(), "DV-2027-000001-001", CASE_REFERENCE,
      ),
      /année du devis/,
  );
});

test("Le moteur refuse une référence de dossier manquante", () => {
  assert.throws(
      () => renderOfficialAdminQuotePdf(
          completeTestContext(), CASE_DV, "",
      ),
      /dossier administratif/,
  );
});

test("Le moteur crée uniquement les octets d'un PDF en mémoire", async () => {
  const data = await renderOfficialAdminQuotePdf(
      completeTestContext(), CASE_DV, CASE_REFERENCE,
  );
  assert.ok(Buffer.isBuffer(data));
  assert.ok(data.length > 1024);
  assert.equal(data.subarray(0, 5).toString("ascii"), "%PDF-");
  // Ce test ne crée ni numéro, ni fichier, ni document Firestore.
});


test("Le devis consultable existe même sans identité juridique", async () => {
  const ctx = completeTestContext();
  ctx.issuer = {};
  ctx.buyer = {};
  ctx.stations = [];
  ctx.publishedQuote = {};
  ctx.taxDecision = {};
  const pdf = await renderConsultableAdminQuotePdf(ctx);
  assert.equal(pdf.subarray(0, 5).toString("ascii"), "%PDF-");
  assert.ok(pdf.length > 1024);
});

test("Consultable et officiel utilisent la même structure documentaire",
    async () => {
      const c = completeTestContext();
      const specimen = adminQuoteDocumentDefinition({
        ...c,
        issuer: {},
        taxDecision: {},
      });
      const official = adminQuoteDocumentDefinition(c, {
        official: true,
        quoteNumber: CASE_DV,
        administrativeReference: CASE_REFERENCE,
        validity: {issuedOn: c.issuedOn, validUntil: "2026-11-14"},
      });
      const keys = (document) => document.lines.map((line) =>
        line.heading ? "heading:" + line.heading : "label:" + line.label);
      assert.deepEqual(keys(specimen), keys(official));
      // Header PNG SPHOT et marker Fire rouge dans les DEUX états.
      assert.equal(specimen.quoteBranding, true);
      assert.equal(official.quoteBranding, true);
      assert.equal(specimen.statusLabel, "NON ÉMIS");
      assert.equal(official.statusLabel, "ÉMIS");
      assert.equal(specimen.documentNumber, "NON ATTRIBUÉ - SPÉCIMEN");
      assert.equal(official.documentNumber, CASE_DV);
      assert.deepEqual(specimen.lines.filter((line) =>
        line.label === "TOTAL ANNUEL HT"), official.lines.filter((line) =>
        line.label === "TOTAL ANNUEL HT"));
      const specimenPdf = await renderConsultableAdminQuotePdf(c);
      const officialPdf = await renderOfficialAdminQuotePdf(
          c, CASE_DV, CASE_REFERENCE);
      assert.ok(Buffer.isBuffer(specimenPdf));
      assert.ok(Buffer.isBuffer(officialPdf));
      assert.equal(specimenPdf.subarray(0, 5).toString("ascii"), "%PDF-");
      assert.equal(officialPdf.subarray(0, 5).toString("ascii"), "%PDF-");
    });
