/* eslint-disable max-len, require-jsdoc, valid-jsdoc, object-curly-spacing, indent */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {archiveOfficialAdminQuote} =
    require("../admin_official_quote_archive");

const NUMBER = "DV-2026-000001-001";
const REFERENCE = "SPHOT-ADM-2026-000001";
const ID = "admin-1";
const QUOTE_ID = "quote-1";
const DOC_ID = ID + "_" + NUMBER;
const PDF_PATH = "adminRequests/" + ID +
    "/documents/financier/2026/devis/" + NUMBER + ".pdf";

function fakePdf(seed = 0) {
  const result = Buffer.concat([
    Buffer.from("%PDF-1.7\n", "ascii"),
    Buffer.alloc(1100, seed),
    Buffer.from("\n%%EOF", "ascii"),
  ]);
  return result;
}

function approvedContext() {
  return {
    adminUid: ID, requestId: ID,
    administrativeReference: REFERENCE,
    quoteNumber: NUMBER,
    issuedOn: "2026-10-15", subscriptionYear: 2026,
    issuer: {
      legalName: "Émetteur FICTIF de test",
      country: "FR", siret: "12345678901234",
      address: "1 rue Test", postalCode: "75001", city: "Paris",
      legalRegistrationVerified: true, commercialIssuanceEnabled: true,
    },
    buyer: {
      legalName: "Commune FICTIVE",
      country: "FR", siret: "12345678901234",
      address: "2 rue Test", postalCode: "75002", city: "Paris",
      billingEmail: "facturation@example.invalid",
      legalIdentityVerified: true, isDifferentFromManager: false,
    },
    stations: [
      {spotDocumentId: "spot-1", name: "Plage du Rocher",
        isRescueStation: true, belongsToAdminTerritory: true},
      {spotDocumentId: "spot-2", name: "Plage des Conches",
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
      taxTreatment: "Fixture fiscale uniquement",
      legalBasis: "Fixture fiscale uniquement",
      amountExclTax: 898, taxAmount: 179.60, amountInclTax: 1077.60,
      calculationVerified: true,
    },
  };
}

function fakeServices() {
  const records = new Map();
  const storedPdf = new Map();
  const counters = {
    uploads: 0, downloads: 0, transactions: 0, commits: 0,
    generationPreconditions: [],
  };
  records.set("quotes/" + QUOTE_ID, {
    adminUid: ID, requestId: ID, quoteNumber: NUMBER,
    administrativeReference: REFERENCE,
    issuedOn: "2026-10-15", subscriptionYear: 2026,
    validUntil: "2026-11-13",
    status: "numbered_pending_archive",
  });
  const snapshot = (path) => {
    const value = records.get(path);
    return {
      exists: value !== undefined,
      data: () => value && {...value},
    };
  };
  const db = {
    failTransactionOnce: false,
    collection(collection) {
      return {
        doc(id) {
          const path = collection + "/" + id;
          return {
            path,
            get: async () => snapshot(path),
          };
        },
      };
    },
    async runTransaction(callback) {
      counters.transactions++;
      const staged = [];
      const tx = {
        get: async (ref) => snapshot(ref.path),
        create(ref, value) {
          if (records.has(ref.path)) throw new Error("Already exists");
          staged.push(() => records.set(ref.path, {...value}));
        },
        update(ref, patch) {
          if (!records.has(ref.path)) throw new Error("Missing quote");
          staged.push(() => records.set(
              ref.path, {...records.get(ref.path), ...patch}));
        },
      };
      const output = await callback(tx);
      if (this.failTransactionOnce) {
        this.failTransactionOnce = false;
        throw new Error("Transaction firestore interrompue");
      }
      staged.forEach((action) => action());
      counters.commits++;
      return output;
    },
  };
  const bucket = {
    file(path) {
      return {
        async save(bytes, options) {
          counters.generationPreconditions.push(
              options.preconditionOpts?.ifGenerationMatch);
          if (storedPdf.has(path)) {
            const error = new Error("Precondition Failed");
            error.code = 412;
            throw error;
          }
          storedPdf.set(path, Buffer.from(bytes));
          counters.uploads++;
        },
        async download() {
          counters.downloads++;
          return [storedPdf.get(path)];
        },
      };
    },
  };
  return {
    db, bucket, records, storedPdf, counters,
    serverTimestamp: () => "SERVER_TIMESTAMP_FOR_TESTS",
    args(pdfBuffer = fakePdf(), verifiedContext = approvedContext()) {
      return {
        db, bucket, serverTimestamp: this.serverTimestamp,
        quoteId: QUOTE_ID, pdfBuffer, verifiedContext,
      };
    },
  };
}

test("L'archiveur ne peut pas être appelé sans serveur ni PDF", () => {
  assert.throws(() => archiveOfficialAdminQuote({}),
      /Services Firestore et Storage/);
  const fake = fakeServices();
  assert.throws(() => archiveOfficialAdminQuote(
      fake.args(Buffer.from("fake"))), /PDF officiel invalide/);
});

test("Le dossier devis doit exister et être numéroté au préalable", async () => {
  const fake = fakeServices();
  fake.records.delete("quotes/" + QUOTE_ID);
  await assert.rejects(
      archiveOfficialAdminQuote(fake.args()), /introuvable/);
  assert.equal(fake.counters.uploads, 0);
  assert.equal(fake.records.has("documents/" + DOC_ID), false);
});

test("La vérification juridique et fiscale bloque tout archivage", async () => {
  const fake = fakeServices();
  const context = approvedContext();
  context.issuer.legalRegistrationVerified = false;
  await assert.rejects(archiveOfficialAdminQuote(fake.args(fakePdf(), context)),
      {code: "QUOTE_NOT_READY"});
  assert.equal(fake.counters.uploads, 0);
  assert.equal(fake.records.has("documents/" + DOC_ID), false);
});

test("Le contexte Admin ne peut référencer une autre identité", async () => {
  const fake = fakeServices();
  const context = approvedContext();
  context.adminUid = "autre-admin";
  await assert.rejects(archiveOfficialAdminQuote(fake.args(fakePdf(), context)),
      /Contexte serveur différent/);
  assert.equal(fake.counters.uploads, 0);
});

test("Devis PDF archivé : objet non écrasable et registre chronologique", async () => {
  const fake = fakeServices();
  const pdf = fakePdf();
  const result = await archiveOfficialAdminQuote(fake.args(pdf));
  assert.equal(result.alreadyArchived, false);
  assert.equal(result.storagePath, PDF_PATH);
  assert.equal(fake.counters.uploads, 1);
  assert.deepEqual(fake.counters.generationPreconditions, [0]);
  assert.deepEqual(fake.storedPdf.get(PDF_PATH), pdf);
  const registry = fake.records.get("documents/" + DOC_ID);
  assert.equal(registry.documentType, "quote");
  assert.equal(registry.category, "financial");
  assert.equal(registry.subcategory, "devis");
  assert.equal(registry.documentNumber, NUMBER);
  assert.equal(registry.status, "issued");
  assert.equal(registry.createdByRole, "system");
  assert.equal(registry.issuedAt, "SERVER_TIMESTAMP_FOR_TESTS");
  assert.equal(registry.pdfSize, pdf.length);
  assert.equal(registry.amountExclTax, 898);
  assert.equal(registry.taxAmount, 179.60);
  assert.equal(registry.amountInclTax, 1077.60);
  assert.equal(registry.pricingReference, "FR_ADMIN-V3");
  assert.equal(registry.numberOfRescueStations, 2);
  assert.equal(registry.sha256, result.sha256);
  assert.equal("downloadUrl" in registry, false);
  assert.equal(fake.records.get("quotes/" + QUOTE_ID).status, "issued");
  assert.equal(
      fake.records.get("quotes/" + QUOTE_ID).documentId, DOC_ID);
});

test("Répéter le même archivage ne crée pas d'autre document", async () => {
  const fake = fakeServices();
  const first = await archiveOfficialAdminQuote(fake.args());
  const second = await archiveOfficialAdminQuote(fake.args());
  assert.equal(first.documentId, second.documentId);
  assert.equal(second.alreadyArchived, true);
  assert.equal(fake.counters.uploads, 1);
  assert.equal([...fake.records.keys()].filter((p) =>
    p.startsWith("documents/")).length, 1);
});

test("Un PDF déjà émis ne peut être remplacé par une version différente",
    async () => {
      const fake = fakeServices();
      await archiveOfficialAdminQuote(fake.args());
      await assert.rejects(
          archiveOfficialAdminQuote(fake.args(fakePdf(2))),
          /Conflit d'archivage/,
      );
      assert.equal(fake.counters.uploads, 1);
    });

test("Une panne après sauvegarde Storage peut être reprise sans perte",
    async () => {
      const fake = fakeServices();
      fake.db.failTransactionOnce = true;
      await assert.rejects(
          archiveOfficialAdminQuote(fake.args()),
          /Transaction firestore interrompue/,
      );
      assert.equal(fake.counters.uploads, 1);
      assert.equal(fake.records.has("documents/" + DOC_ID), false);
      const restored = await archiveOfficialAdminQuote(fake.args());
      assert.equal(restored.alreadyArchived, false);
      assert.equal(fake.counters.uploads, 1);
      assert.equal(fake.counters.downloads, 1);
      assert.equal(fake.records.get("documents/" + DOC_ID).status, "issued");
    });

test("Un objet Storage préexistant différent bloque l'archive",
    async () => {
      const fake = fakeServices();
      fake.storedPdf.set(PDF_PATH, fakePdf(5));
      await assert.rejects(
          archiveOfficialAdminQuote(fake.args()),
          /Conflit Storage/,
      );
      assert.equal(fake.records.has("documents/" + DOC_ID), false);
    });

test("Un état non prêt pour archivage ne consomme aucun numéro ni PDF",
    async () => {
      const fake = fakeServices();
      fake.records.get("quotes/" + QUOTE_ID).status = "draft";
      await assert.rejects(archiveOfficialAdminQuote(fake.args()),
          /pas autorisé à être archivé/);
      assert.equal(fake.counters.uploads, 0);
      assert.equal(fake.records.has("documents/" + DOC_ID), false);
    });
