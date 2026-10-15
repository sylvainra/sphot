/* eslint-disable max-len, require-jsdoc, valid-jsdoc, object-curly-spacing */
"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  makeOfficialQuoteArchivePlan, archiveOfficialAdminQuote,
} = require("../admin_quote_archive");

const number = "DV-2026-000001-001";
const dossier = "SPHOT-ADM-2026-000001";
const pdf = Buffer.concat([Buffer.from("%PDF-1.7\n"), Buffer.alloc(1150)]);
const input = () => ({
  adminUid: "admin1", requestId: "admin1",
  administrativeReference: dossier, quoteId: "quote1",
  quoteNumber: number, issuedOn: "2026-10-15", pdfBuffer: pdf,
});
const snapshot = () => ({
  id: "quote1", exists: true,
  data: () => ({
    ...input(), status: "issued", pdfReadyToArchive: true,
  }),
});
const gate = () => ({
  isServerAuthorized: true, issuerLegallyVerified: true,
  fiscalityVerified: true,
});

function fakeStorageAndRegistry() {
  const documents = new Map();
  const objects = new Map();
  const db = {
    collection: (name) => {
      assert.equal(name, "documents");
      return {doc: (id) => ({
        get: async () => ({
          exists: documents.has(id),
          data: () => documents.get(id),
        }),
        create: async (data) => {
          if (documents.has(id)) throw new Error("Already exists");
          documents.set(id, data);
        },
      })};
    },
  };
  const bucket = {file: (name) => ({
    exists: async () => [objects.has(name)],
    download: async () => [objects.get(name)],
    save: async (bytes, options) => {
      assert.equal(options.preconditionOpts.ifGenerationMatch, 0);
      if (objects.has(name)) throw new Error("Precondition failed");
      objects.set(name, Buffer.from(bytes));
    },
  })};
  return {db, bucket, documents, objects};
}
const archive = (fake, overrides = {}) => archiveOfficialAdminQuote({
  db: fake.db, bucket: fake.bucket,
  quoteSnapshot: snapshot(), pdfBuffer: pdf,
  trustedServerGate: gate(), ...overrides,
});

test("Aucun numéro ou registre n'est créé par la préparation", () => {
  const plan = makeOfficialQuoteArchivePlan(input());
  assert.equal(plan.registryId, "admin1_" + number);
  assert.equal(plan.storagePath,
      "adminRequests/admin1/documents/financier/2026/devis/" +
      number + ".pdf");
  assert.match(plan.sha256, /^[0-9a-f]{64}$/);
});

test("L'archivage n'est possible qu'après vérification de l'émetteur", async () => {
  const fake = fakeStorageAndRegistry();
  await assert.rejects(archive(fake, {
    trustedServerGate: {...gate(), issuerLegallyVerified: false},
  }), /ARCHIVE_BLOCKED/);
  assert.equal(fake.documents.size, 0);
  assert.equal(fake.objects.size, 0);
});

test("Pas d'archivage d'un devis non émis", async () => {
  const fake = fakeStorageAndRegistry();
  await assert.rejects(archive(fake, {
    quoteSnapshot: {...snapshot(), data: () => ({
      ...input(), status: "draft", pdfReadyToArchive: true,
    })},
  }), /Devis non émis/);
  assert.equal(fake.objects.size, 0);
});

test("PDF conservé une seule fois et inscrit au registre", async () => {
  const fake = fakeStorageAndRegistry();
  const record = await archive(fake);
  assert.equal(record.documentNumber, number);
  assert.equal(record.status, "issued");
  assert.equal(fake.documents.size, 1);
  assert.equal(fake.objects.size, 1);
  const rerun = await archive(fake);
  assert.deepEqual(rerun, record);
  assert.equal(fake.documents.size, 1);
  assert.equal(fake.objects.size, 1);
});

test("Un PDF différent ne peut jamais remplacer l'original", async () => {
  const fake = fakeStorageAndRegistry();
  await archive(fake);
  const otherPdf = Buffer.concat([Buffer.from("%PDF-1.7\n"),
    Buffer.alloc(1150, 1)]);
  await assert.rejects(archive(fake, {pdfBuffer: otherPdf}),
      /ARCHIVE_CONFLICT_IMMUTABLE/);
  assert.equal(fake.objects.size, 1);
});

test("Une reprise complète un registre absent sans changer le PDF", async () => {
  const fake = fakeStorageAndRegistry();
  await archive(fake);
  fake.documents.clear();
  const result = await archive(fake);
  assert.equal(result.documentNumber, number);
  assert.equal(fake.documents.size, 1);
  assert.equal(fake.objects.size, 1);
});

test("Un fichier de stockage existant avec un autre hash est refusé", async () => {
  const fake = fakeStorageAndRegistry();
  const plan = makeOfficialQuoteArchivePlan(input());
  fake.objects.set(plan.storagePath, Buffer.from("not the issued PDF"));
  await assert.rejects(archive(fake), /ARCHIVE_STORAGE_CONFLICT/);
  assert.equal(fake.documents.size, 0);
});

test("Un enregistrement déjà existant différent est protégé", async () => {
  const fake = fakeStorageAndRegistry();
  const plan = makeOfficialQuoteArchivePlan(input());
  fake.documents.set(plan.registryId, {
    quoteId: plan.quoteId, sha256: "incorrect",
    storagePath: plan.storagePath, documentNumber: plan.quoteNumber,
    status: "issued",
  });
  await assert.rejects(archive(fake), /ARCHIVE_CONFLICT_IMMUTABLE/);
  assert.equal(fake.objects.size, 0);
});
