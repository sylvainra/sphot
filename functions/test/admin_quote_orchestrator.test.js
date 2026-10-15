/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {inspectOfficialAdminQuote} =
    require("../admin_quote_orchestrator");

const ID = "admin-1";
const TERRITORY = "territoire-1";
const QUOTE = "quote-1";
const REF = "SPHOT-ADM-2026-000001";

function fixture() {
  const trace = [];
  const session = {
    uid: ID, adminUid: ID, role: "ADMIN", territoireId: TERRITORY,
  };
  const access = {
    uid: ID, role: "ADMIN", accountStatus: "ACTIVE",
    accessStatus: "approved", territoireId: TERRITORY,
  };
  const request = {uid: ID, requestNumber: REF};
  const context = {
    quoteId: QUOTE, adminUid: ID, requestId: ID,
    territoireId: TERRITORY, administrativeReference: REF,
    issuedOn: "2026-10-15", subscriptionYear: 2026,
    issuer: {
      legalName: "Emetteur FICTIF", country: "FR",
      siret: "12345678901234",
      address: "1 rue Test", postalCode: "75001", city: "Paris",
      legalRegistrationVerified: true, commercialIssuanceEnabled: true,
    },
    buyer: {
      legalName: "Acheteur FICTIF", country: "FR",
      siret: "12345678901234",
      address: "2 rue Test", postalCode: "75002", city: "Paris",
      billingEmail: "facturation@example.invalid",
      legalIdentityVerified: true, isDifferentFromManager: false,
    },
    stations: [
      {spotDocumentId: "spot-1", name: "Poste 1",
        isRescueStation: true, belongsToAdminTerritory: true},
      {spotDocumentId: "spot-2", name: "Poste 2",
        isRescueStation: true, belongsToAdminTerritory: true},
    ],
    taxDecision: {
      status: "validated", jurisdiction: "FR", currency: "EUR",
      taxTreatment: "Test uniquement", legalBasis: "Test uniquement",
      amountExclTax: 898, taxAmount: 179.60, amountInclTax: 1077.60,
      calculationVerified: true,
    },
    // Valeur client volontairement fausse : le prix doit être recalculé.
    publishedQuote: {amountExclTax: 1},
  };
  const published = {
    type: "ADMIN", country: "FR", currency: "EUR",
    publishedVersion: 3, publishedPrices: [499, 399, 299, 199],
  };
  const services = {
    verifyIdToken: async () => {
      trace.push("auth");
      return session;
    },
    getAdminAccess: async () => {
      trace.push("rights");
      return access;
    },
    getAdminRequest: async () => {
      trace.push("dossier");
      return request;
    },
    getVerifiedQuoteContext: async () => {
      trace.push("verified-context");
      return context;
    },
    getPublishedPricing: async () => {
      trace.push("published-price");
      return {exists: true, data: () => published};
    },
  };
  const inspect = (extra = {}) =>
    inspectOfficialAdminQuote({
      idToken: "TEST_TOKEN", quoteId: QUOTE, services, ...extra,
    });
  return {session, access, request, context, published,
    services, trace, inspect};
}

test("Aucun service fiable : refus sans effet secondaire", async () => {
  const result = await inspectOfficialAdminQuote({
    idToken: "TEST_TOKEN", quoteId: QUOTE,
  });
  assert.equal(result.status, "blocked");
  assert.deepEqual(result.reasonCodes,
      ["TRUSTED_SERVER_SERVICES_UNAVAILABLE"]);
});

test("Jeton ou identifiant de devis absent : refus immédiat", async () => {
  const f = fixture();
  const result = await f.inspect({idToken: ""});
  assert.deepEqual(result.reasonCodes, ["INVALID_REQUEST"]);
  assert.deepEqual(f.trace, []);
});

test("Session Admin non authentifiée : refus", async () => {
  const f = fixture();
  f.session.uid = "autre";
  const result = await f.inspect();
  assert.deepEqual(result.reasonCodes, ["ADMIN_AUTHENTICATION_INVALID"]);
  assert.deepEqual(f.trace, ["auth"]);
});

test("Un rôle non Admin ne peut obtenir l'analyse", async () => {
  const f = fixture();
  f.session.role = "SAUVETEUR";
  assert.deepEqual((await f.inspect()).reasonCodes,
      ["ADMIN_AUTHENTICATION_INVALID"]);
});

test("Compte suspendu : aucun accès au dossier", async () => {
  const f = fixture();
  f.access.accountStatus = "SUSPENDED";
  assert.deepEqual((await f.inspect()).reasonCodes,
      ["ADMIN_ACCESS_DENIED"]);
  assert.deepEqual(f.trace, ["auth", "rights"]);
});

test("Le territoire du jeton doit correspondre au compte", async () => {
  const f = fixture();
  f.session.territoireId = "autre-territoire";
  assert.deepEqual((await f.inspect()).reasonCodes,
      ["ADMIN_ACCESS_DENIED"]);
});

test("Le dossier administratif doit correspondre à l'UID Admin", async () => {
  const f = fixture();
  f.request.uid = "autre";
  assert.deepEqual((await f.inspect()).reasonCodes,
      ["ADMIN_REQUEST_NOT_VERIFIED"]);
});

test("Impossible de consulter le contexte d'un autre Admin", async () => {
  const f = fixture();
  f.context.adminUid = "autre";
  assert.deepEqual((await f.inspect()).reasonCodes,
      ["QUOTE_CONTEXT_MISMATCH"]);
});

test("Le devis ne doit pas être déjà numéroté", async () => {
  const f = fixture();
  f.context.quoteNumber = "DV-2026-000001-001";
  assert.deepEqual((await f.inspect()).reasonCodes,
      ["QUOTE_CONTEXT_MISMATCH"]);
});

test("Aucun tarif non publié ne permet un résultat prêt", async () => {
  const f = fixture();
  f.published.publishedVersion = 0;
  assert.deepEqual((await f.inspect()).reasonCodes,
      ["PUBLISHED_PRICING_UNAVAILABLE"]);
});

test("Émetteur non immatriculé : dossier bloqué", async () => {
  const f = fixture();
  f.context.issuer.legalRegistrationVerified = false;
  const result = await f.inspect();
  assert.equal(result.status, "blocked");
  assert.ok(result.reasonCodes.includes("ISSUER_NOT_LEGALLY_VERIFIED"));
});

test("Payeur tiers sans autorisation : dossier bloqué", async () => {
  const f = fixture();
  f.context.buyer.isDifferentFromManager = true;
  const result = await f.inspect();
  assert.ok(result.reasonCodes.includes("THIRD_PARTY_PAYER_NOT_AUTHORIZED"));
});

test("Poste hors territoire : contrôle préalable bloqué", async () => {
  const f = fixture();
  f.context.stations[0].belongsToAdminTerritory = false;
  const result = await f.inspect();
  assert.ok(result.reasonCodes.includes("RESCUE_STATIONS_NOT_VERIFIED"));
});

test("Fiscalité invalide : aucun dossier prêt", async () => {
  const f = fixture();
  f.context.taxDecision.calculationVerified = false;
  const result = await f.inspect();
  assert.ok(result.reasonCodes.includes("TAX_TREATMENT_NOT_VERIFIED"));
});

test("Aperçu serveur valide : sans émission, DV, PDF ou envoi", async () => {
  const f = fixture();
  const result = await f.inspect();
  assert.equal(result.status, "preflight_passed");
  assert.equal(result.emissionAuthorized, false);
  assert.equal(result.amountExclTax, 898);
  assert.equal(result.pricingReference, "FR_ADMIN-V3");
  assert.equal(result.numberOfRescueStations, 2);
  assert.equal(result.validUntil, "2026-11-13");
  assert.equal(Object.hasOwn(result, "quoteNumber"), false);
  assert.deepEqual(f.trace, [
    "auth", "rights", "dossier", "verified-context", "published-price",
  ]);
});

test("Un prix client falsifié ne remplace jamais le prix publié", async () => {
  const f = fixture();
  f.context.publishedQuote.amountExclTax = 999999;
  const result = await f.inspect();
  assert.equal(result.status, "preflight_passed");
  assert.equal(result.amountExclTax, 898);
});
