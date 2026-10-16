/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {readArchivedAdminQuotePdf} =
    require("../admin_quote_download");

const UID = "admin-1";
const NUMBER = "DV-2026-000001-001";
const DOCUMENT_ID = UID + "_" + NUMBER;
const QUOTE_ID = "quote-1";
const PATH = "adminRequests/" + UID +
    "/documents/financier/2026/devis/" + NUMBER + ".pdf";
const PDF = Buffer.concat([
  Buffer.from("%PDF-1.7\n", "ascii"),
  Buffer.alloc(1200, 17),
  Buffer.from("\n%%EOF", "ascii"),
]);
const HASH = crypto.createHash("sha256").update(PDF).digest("hex");

function fixture() {
  const records = new Map([
    ["adminAccounts/example@example.invalid", {
      adminUid: UID, accountStatus: "ACTIVE",
      territoireId: "terr-1", role: "ADMIN",
    }],
    ["documents/" + DOCUMENT_ID, {
      adminUid: UID, requestId: UID,
      documentNumber: NUMBER, quoteNumber: NUMBER,
      quoteId: QUOTE_ID, documentType: "quote",
      status: "issued", storagePath: PATH,
      sha256: HASH, pdfSize: PDF.length,
    }],
    ["quotes/" + QUOTE_ID, {
      adminUid: UID, requestId: UID,
      documentId: DOCUMENT_ID, quoteNumber: NUMBER,
      pdfSha256: HASH, storagePath: PATH,
      status: "issued", pdfArchived: true,
    }],
  ]);
  const files = new Map([[PATH, Buffer.from(PDF)]]);
  const calls = {auth: 0, reads: [], downloads: 0, writes: 0};
  const session = {
    uid: UID, adminUid: UID, role: "ADMIN", territoireId: "terr-1",
  };
  const auth = {
    async verifyIdToken(token, checkRevoked) {
      calls.auth++;
      assert.equal(checkRevoked, true);
      if (token !== "TEST_TOKEN") throw new Error("Invalid token");
      return session;
    },
  };
  const reference = (path) => ({
    async get() {
      calls.reads.push(path);
      return {
        exists: records.has(path),
        data: () => records.get(path),
      };
    },
  });
  const db = {
    collection(name) {
      return {
        doc(id) {
          return reference(name + "/" + id);
        },
        where(field, op, value) {
          assert.equal(name, "adminAccounts");
          assert.equal(field, "adminUid");
          assert.equal(op, "==");
          return {
            limit(count) {
              assert.equal(count, 10);
              return {
                async get() {
                  calls.reads.push("adminAccounts?uid=" + value);
                  return {docs: [...records.entries()].filter(([p, data]) =>
                    p.startsWith("adminAccounts/") &&
                    data.adminUid === value).map(([, data]) => ({
                    data: () => data,
                  }))};
                },
              };
            },
          };
        },
      };
    },
  };
  const bucket = {
    file(path) {
      return {
        async download() {
          calls.downloads++;
          return [files.get(path)];
        },
      };
    },
  };
  const call = (change = {}) => readArchivedAdminQuotePdf({
    auth, db, bucket, idToken: "TEST_TOKEN",
    documentId: DOCUMENT_ID, ...change,
  });
  return {records, files, calls, session, call};
}

test("Le propriétaire retrouve les octets exacts de son PDF SPHOT",
    async () => {
      const f = fixture();
      const result = await f.call();
      assert.equal(result.documentId, DOCUMENT_ID);
      assert.equal(result.filename, NUMBER + ".pdf");
      assert.equal(result.mimeType, "application/pdf");
      assert.deepEqual(result.pdfBuffer, PDF);
      assert.equal(f.calls.downloads, 1);
      assert.equal(f.calls.writes, 0);
    });

test("Aucune pièce sans identité Firebase vérifiée", async () => {
  const f = fixture();
  await assert.rejects(f.call({idToken: ""}),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  await assert.rejects(f.call({idToken: "INVALID"}),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 0);
});

test("Un autre Admin ne peut pas télécharger le PDF", async () => {
  const f = fixture();
  f.session.uid = "admin-2";
  f.session.adminUid = "admin-2";
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 0);
});

test("Un compte suspendu n'accède plus aux devis archivés", async () => {
  const f = fixture();
  f.records.get("adminAccounts/example@example.invalid")
      .accountStatus = "SUSPENDED";
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 0);
});

test("Une session ANNONCEUR ne donne jamais accès aux PDF Admin", async () => {
  const f = fixture();
  f.session.role = "ANNONCEUR";
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.reads.length, 0);
});

test("Une identité de compte multiple reste bloquée", async () => {
  const f = fixture();
  f.records.set("adminAccounts/duplicate@example.invalid", {
    adminUid: UID, accountStatus: "ACTIVE", role: "ADMIN",
    territoireId: "terr-1",
  });
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 0);
});

test("Un registre étranger est refusé avant Storage", async () => {
  const f = fixture();
  f.records.get("documents/" + DOCUMENT_ID).adminUid = "admin-2";
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 0);
});

test("Un registre pointant vers un autre fichier est refusé", async () => {
  const f = fixture();
  f.records.get("documents/" + DOCUMENT_ID).storagePath =
      "public/other.pdf";
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 0);
});

test("Un devis disparu ou non émis interdit tout téléchargement", async () => {
  const f = fixture();
  f.records.get("quotes/" + QUOTE_ID).status = "draft";
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 0);
});

test("Le PDF modifié ou tronqué ne peut être restitué", async () => {
  const f = fixture();
  f.files.set(PATH, Buffer.concat([
    Buffer.from("%PDF-1.7\n", "ascii"),
    Buffer.alloc(1200, 29),
    Buffer.from("\n%%EOF", "ascii"),
  ]));
  await assert.rejects(f.call(),
      {code: "QUOTE_DOCUMENT_ACCESS_DENIED"});
  assert.equal(f.calls.downloads, 1);
});

test("Aucune commande, facture, email ou écriture n'est déclenchée",
    async () => {
      const f = fixture();
      await f.call();
      assert.equal(f.calls.writes, 0);
      assert.equal(f.records.size, 3);
    });
