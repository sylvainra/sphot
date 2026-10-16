/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {prepareOfficialAdminQuoteDelivery} =
    require("../admin_quote_delivery");
const {assignAuthorizedAdminQuoteNumber} =
    require("../admin_quote_numbering");

const ADMIN = "admin-1";
const QUOTE = "quote-1";
const REF = "SPHOT-ADM-2026-000001";
const DV = "DV-2026-000001-001";
const EMAIL = "admin@example.invalid";

function verifiedContext() {
  return {
    adminUid: ADMIN, requestId: ADMIN,
    administrativeReference: REF, quoteNumber: DV,
    issuedOn: "2026-10-15", subscriptionYear: 2026,
    issuer: {
      legalName: "Emetteur FICTIF de test", country: "FR",
      siret: "12345678901234", address: "1 rue Test",
      postalCode: "75001", city: "Paris",
      legalRegistrationVerified: true, commercialIssuanceEnabled: true,
    },
    buyer: {
      legalName: "Commune FICTIVE de test", country: "FR",
      siret: "12345678901234", address: "2 rue Test",
      postalCode: "75002", city: "Paris",
      billingEmail: "facturation@example.invalid",
      legalIdentityVerified: true, isDifferentFromManager: false,
    },
    stations: [
      {spotDocumentId: "spot-1", idSphot: "TEST 01", name: "Poste fictif A",
        isRescueStation: true, belongsToAdminTerritory: true},
      {spotDocumentId: "spot-2", idSphot: "TEST 02", name: "Poste fictif B",
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
      taxTreatment: "Calcul FICTIF de test",
      legalBasis: "Référence FICTIVE de test",
      amountExclTax: 898, taxAmount: 179.60,
      amountInclTax: 1077.60, calculationVerified: true,
    },
  };
}

// Émulation MINIMALE en mémoire : aucun SDK Firebase ni connexion réseau.
function memoryServices() {
  const records = new Map();
  const files = new Map();
  const count = {pdfUploads: 0, writes: 0, emailSends: 0};
  const snapshot = (r) => ({
    exists: records.has(r.path),
    data: () => records.get(r.path) && {...records.get(r.path)},
  });
  const db = {
    collection: (name) => ({
      doc: (id) => {
        const ref = {path: name + "/" + id, id};
        return {...ref, get: async () => snapshot(ref)};
      },
    }),
    runTransaction: async (callback) => {
      const staged = [];
      let wrote = false;
      const tx = {
        get: async (r) => {
          if (wrote) throw new Error("Lecture après écriture");
          return snapshot(r);
        },
        set: (r, value, options) => {
          wrote = true;
          const previous = records.get(r.path) || {};
          staged.push([r.path, options && options.merge ?
            {...previous, ...value} : value]);
        },
        create: (r, value) => {
          wrote = true;
          if (records.has(r.path)) throw new Error("Record exists");
          staged.push([r.path, value]);
        },
        update: (r, value) => {
          wrote = true;
          if (!records.has(r.path)) throw new Error("Record missing");
          staged.push([r.path, {...records.get(r.path), ...value}]);
        },
      };
      const result = await callback(tx);
      for (const [path, data] of staged) {
        records.set(path, {...data});
        count.writes++;
      }
      return result;
    },
  };
  const bucket = {
    file: (path) => ({
      save: async (content, options) => {
        assert.equal(options.preconditionOpts.ifGenerationMatch, 0);
        if (files.has(path)) {
          const err = new Error("Already uploaded");
          err.code = 412;
          throw err;
        }
        files.set(path, Buffer.from(content));
        count.pdfUploads++;
      },
      download: async () => [files.get(path)],
    }),
  };
  records.set("quotes/" + QUOTE, {
    quoteId: QUOTE, adminUid: ADMIN, requestId: ADMIN,
    administrativeReference: REF, quoteNumber: DV,
    issuedOn: "2026-10-15", validUntil: "2026-11-13",
    subscriptionYear: 2026, status: "numbered_pending_archive",
  });
  const context = verifiedContext();
  const call = (extra = {}) => prepareOfficialAdminQuoteDelivery({
    db, bucket, quoteId: QUOTE, verifiedContext: context,
    adminEmail: EMAIL, serverTimestamp: () => "MEMORY_ONLY_TIMESTAMP",
    ...extra,
  });
  return {records, files, count, context, db, bucket, call};
}

test("Aucun devis non numéroté ne peut entrer dans la livraison", async () => {
  const f = memoryServices();
  f.records.get("quotes/" + QUOTE).status = "draft";
  await assert.rejects(f.call(), /ne peut pas être préparé/);
  assert.equal(f.files.size, 0);
  assert.equal(f.count.writes, 0);
});

test("Une identité de dossier discordante interdit tout archivage", async () => {
  const f = memoryServices();
  f.context.adminUid = "autre-admin";
  await assert.rejects(f.call(), /incohérents/);
  assert.equal(f.files.size, 0);
});

test("Émetteur juridiquement non vérifié : aucun PDF archivé", async () => {
  const f = memoryServices();
  f.context.issuer.legalRegistrationVerified = false;
  await assert.rejects(f.call(), /validations du devis manquantes/);
  assert.equal(f.files.size, 0);
});

test("Adresse Admin absente : aucune écriture", async () => {
  const f = memoryServices();
  await assert.rejects(f.call({adminEmail: ""}), /Email Admin/);
  assert.equal(f.count.writes, 0);
  assert.equal(f.files.size, 0);
});

test("Un PDF SPHOT réel traverse l'archivage et prépare le mail, sans envoi", async () => {
  const f = memoryServices();
  const result = await f.call();
  assert.equal(result.status, "email_prepared_not_sent");
  assert.equal(result.emailSent, false);
  assert.equal(result.quoteNumber, DV);
  assert.ok(result.pdfSize > 1024);
  assert.equal(f.count.pdfUploads, 1);
  assert.equal(f.files.size, 1);
  assert.equal(f.count.emailSends, 0);
  assert.equal(f.records.get("quotes/" + QUOTE).status, "issued");
  const document = f.records.get("documents/" + ADMIN + "_" + DV);
  assert.equal(document.documentType, "quote");
  assert.equal(document.status, "issued");
  assert.equal(document.adminUid, ADMIN);
  assert.equal(document.commercialSnapshot.schemaVersion, 1);
  assert.equal(document.commercialSnapshot.issuer.legalName,
      "Emetteur FICTIF de test");
  assert.equal(document.commercialSnapshot.buyer.legalName,
      "Commune FICTIVE de test");
  assert.equal(document.commercialSnapshot.rescueStations.length, 2);
  assert.equal(document.commercialSnapshot.pricing.amountExclTax, 898);
  assert.equal(result.message.to, EMAIL);
  assert.ok(result.message.subject.includes(DV));
  const attachment = result.message.attachments.find(
      (a) => a.filename === DV + ".pdf");
  assert.ok(attachment);
  assert.ok(Buffer.isBuffer(attachment.content));
  assert.deepEqual(attachment.content, f.files.get(document.storagePath));
  assert.equal(attachment.content.subarray(0, 5).toString("ascii"), "%PDF-");
});

test("Reprise : le PDF déjà archivé est réutilisé sans doublon", async () => {
  const f = memoryServices();
  const first = await f.call();
  const second = await f.call();
  assert.equal(second.alreadyArchived, true);
  assert.equal(second.documentId, first.documentId);
  assert.equal(f.count.pdfUploads, 1);
  assert.equal([...f.records.keys()].filter(
      (path) => path.startsWith("documents/")).length, 1);
  const name = DV + ".pdf";
  const firstPdf = first.message.attachments.find((a) => a.filename === name);
  const secondPdf = second.message.attachments.find((a) => a.filename === name);
  assert.deepEqual(secondPdf.content, firstPdf.content);
  assert.equal(f.count.emailSends, 0);
});

test("Un PDF stocké altéré bloque la reprise et le mail", async () => {
  const f = memoryServices();
  const result = await f.call();
  f.files.set(result.storagePath, Buffer.alloc(1500));
  await assert.rejects(f.call(), /PDF archivé absent ou altéré/);
  assert.equal(f.count.pdfUploads, 1);
});

test("Un registre modifié bloque la reprise et le mail", async () => {
  const f = memoryServices();
  await f.call();
  const archive = f.records.get("documents/" + ADMIN + "_" + DV);
  archive.amountExclTax = 1;
  await assert.rejects(f.call(), /Registre d'archive incohérent/);
});

test("Aucune opération de paiement, de commande ou de SMTP", async () => {
  const f = memoryServices();
  await f.call();
  assert.equal(f.count.emailSends, 0);
  assert.equal([...f.records.keys()].some(
      (p) => p.startsWith("orders/") ||
      p.startsWith("payments/") || p.startsWith("invoices/")), false);
});

test("Chaîne complète : autorisation fictive, DV, PDF, archive, mail prêt", async () => {
  const f = memoryServices();
  const quote = f.records.get("quotes/" + QUOTE);
  quote.status = "authorized_pending_number";
  delete quote.quoteNumber;
  f.records.set("adminRequests/" + ADMIN, {
    uid: ADMIN, requestNumber: REF,
  });
  f.records.set("quoteIssueAuthorizations/" + QUOTE, {
    type: "official_admin_quote", status: "approved_for_numbering",
    quoteId: QUOTE, adminUid: ADMIN, requestId: ADMIN,
    administrativeReference: REF,
    issuedOn: "2026-10-15", subscriptionYear: 2026,
    validUntil: "2026-11-13",
    issuerLegallyVerified: true, fiscalityVerified: true,
    publishedPricingVerified: true, buyerVerified: true,
    stationsVerified: true, adminRightsVerified: true,
    thirdPartyBillingVerified: true,
  });
  const numbered = await assignAuthorizedAdminQuoteNumber({
    db: f.db,
    event: {data: {after: {
      exists: true,
      ref: f.db.collection("quotes").doc(QUOTE),
    }}},
    serverTimestamp: () => "MEMORY_ONLY_TIMESTAMP",
  });
  assert.equal(numbered, true);
  assert.equal(f.records.get("quotes/" + QUOTE).quoteNumber, DV);
  assert.equal(f.records.get("counters/quotes_2026_000001").lastNumber, 1);
  assert.equal(f.records.get("quoteIssueAuthorizations/" + QUOTE)
      .status, "numbered");
  const result = await f.call();
  assert.equal(result.status, "email_prepared_not_sent");
  assert.equal(f.records.get("quotes/" + QUOTE).status, "issued");
  assert.equal(f.count.pdfUploads, 1);
  assert.equal(f.count.emailSends, 0);
  // Rejouer le trigger : aucun numéro supplémentaire n'est consommé.
  const again = await assignAuthorizedAdminQuoteNumber({
    db: f.db,
    event: {data: {after: {
      exists: true,
      ref: f.db.collection("quotes").doc(QUOTE),
    }}},
    serverTimestamp: () => "MEMORY_ONLY_TIMESTAMP",
  });
  assert.equal(again, false);
  assert.equal(f.records.get("counters/quotes_2026_000001").lastNumber, 1);
});

test("Un changement d'organisme payeur après émission bloque la reprise",
    async () => {
      const f = memoryServices();
      await f.call();
      f.context.buyer.legalName = "Organisme modifié";
      await assert.rejects(f.call(), /Registre d'archive incohérent/);
      assert.equal(f.count.pdfUploads, 1);
    });
