/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {sendIssuedAdminQuoteEmail} = require("../admin_quote_send");

const UID = "admin-1";
const ID = "quote-1";
const REF = "SPHOT-ADM-2026-000001";
const DV = "DV-2026-000001-001";
const DOC_ID = UID + "_" + DV;
const PATH = "adminRequests/" + UID +
    "/documents/financier/2026/devis/" + DV + ".pdf";
const EMAIL = "admin@example.invalid";
const PDF = Buffer.concat([Buffer.from("%PDF-1.7\n"),
  Buffer.alloc(1300, 17), Buffer.from("\n%%EOF")]);
const HASH = crypto.createHash("sha256").update(PDF).digest("hex");

function fixture() {
  const records = new Map();
  const stats = {send: 0, transactions: 0, failCompletion: false};
  const quote = {
    quoteId: ID, adminUid: UID, requestId: UID,
    quoteNumber: DV, status: "issued", pdfArchived: true,
    documentId: DOC_ID, pdfSha256: HASH,
    administrativeReference: REF, storagePath: PATH,
    issuedOn: "2026-10-16", subscriptionYear: 2026,
    validUntil: "2026-11-14",
  };
  records.set("quotes/" + ID, quote);
  records.set("documents/" + DOC_ID, {
    documentNumber: DV, quoteId: ID,
    documentType: "quote", status: "issued",
    adminUid: UID, requestId: UID, storagePath: PATH,
    sha256: HASH, pdfSize: PDF.length,
    issuedOn: "2026-10-16", validUntil: "2026-11-14",
  });
  records.set("quoteIssueAuthorizations/" + ID, {
    type: "official_admin_quote", status: "numbered",
    quoteId: ID, adminUid: UID, requestId: UID,
    quoteNumber: DV, administrativeReference: REF,
    issuedOn: "2026-10-16", subscriptionYear: 2026,
    validUntil: "2026-11-14",
    issuerLegallyVerified: true, fiscalityVerified: true,
    publishedPricingVerified: true, buyerVerified: true,
    stationsVerified: true, adminRightsVerified: true,
    thirdPartyBillingVerified: true,
  });
  records.set("adminAccounts/" + EMAIL, {
    email: EMAIL, accountStatus: "ACTIVE", role: "ADMIN",
    adminUid: UID, territoireId: "terr-1",
  });
  const ref = (path) => ({
    path,
    get: async () => ({exists: records.has(path),
      data: () => records.get(path) && {...records.get(path)}}),
  });
  const db = {
    collection(name) {
      return {
        doc: (id) => ref(name + "/" + id),
        where(field, operator, value) {
          assert.equal(name, "adminAccounts");
          assert.equal(field, "adminUid");
          assert.equal(operator, "==");
          return {
            limit(count) {
              assert.equal(count, 10);
              return {
                async get() {
                  return {docs: [...records.entries()].filter(
                      ([p, data]) => p.startsWith(name + "/") &&
                      data.adminUid === value).map(([, data]) => ({
                    data: () => ({...data}),
                  }))};
                },
              };
            },
          };
        },
      };
    },
    async runTransaction(fn) {
      stats.transactions++;
      const updates = [];
      const tx = {
        get: async (r) => ({exists: records.has(r.path),
          data: () => records.get(r.path) && {...records.get(r.path)}}),
        update: (r, patch) => updates.push([r.path, patch]),
      };
      const result = await fn(tx);
      if (stats.failCompletion && updates.some(([, data]) =>
        data.emailDelivery?.status === "sent")) {
        throw new Error("Firestore write error after send");
      }
      for (const [path, patch] of updates) {
        records.set(path, {...records.get(path), ...patch});
      }
      return result;
    },
  };
  const preparedDelivery = {
    status: "email_prepared_not_sent", emailSent: false,
    quoteNumber: DV, documentId: DOC_ID, storagePath: PATH,
    message: {
      to: EMAIL, subject: "SPHOT ADMIN - Votre devis " + DV,
      attachments: [{filename: DV + ".pdf",
        contentType: "application/pdf", content: Buffer.from(PDF)}],
    },
  };
  const sendMail = async () => {
    stats.send++;
    return {accepted: [EMAIL], rejected: [], messageId: "SMTP_TEST"};
  };
  const serverTimestamp = () => "FAKE_NOW";
  const call = (changes = {}) => sendIssuedAdminQuoteEmail({
    db, quoteId: ID, preparedDelivery, sendMail, serverTimestamp,
    ...changes,
  });
  return {db, stats, records, preparedDelivery, call};
}

test("Envoi confirmé une fois, historisé sur le devis", async () => {
  const f = fixture();
  const result = await f.call();
  assert.deepEqual(result, {status: "sent", emailSent: true});
  assert.equal(f.stats.send, 1);
  const delivery = f.records.get("quotes/" + ID).emailDelivery;
  assert.equal(delivery.status, "sent");
  assert.equal(delivery.attemptCount, 1);
  assert.equal(delivery.recipient, EMAIL);
  assert.equal(delivery.pdfSha256, HASH);
  assert.equal(delivery.messageId, "SMTP_TEST");
  assert.equal(f.records.size, 4);
});

test("Une relance ne renvoie jamais le devis déjà expédié", async () => {
  const f = fixture();
  await f.call();
  const again = await f.call();
  assert.deepEqual(again, {status: "already_sent", emailSent: false});
  assert.equal(f.stats.send, 1);
});

test("Un double clic pendant SMTP ne déclenche qu'un essai", async () => {
  const f = fixture();
  let resume;
  let begun;
  const sending = new Promise((resolve) => {
    resume = resolve;
  });
  const started = new Promise((resolve) => {
    begun = resolve;
  });
  const sendMail = async () => {
    f.stats.send++;
    begun();
    await sending;
    return {accepted: [EMAIL]};
  };
  const first = f.call({sendMail});
  await started;
  const second = await f.call({sendMail});
  assert.deepEqual(second, {status: "requires_review", emailSent: false});
  assert.equal(f.stats.send, 1);
  resume();
  assert.equal((await first).status, "sent");
});

test("Un timeout SMTP interdit toute relance automatique", async () => {
  const f = fixture();
  const sendMail = async () => {
    f.stats.send++;
    throw new Error("SMTP connection lost AFTER DATA");
  };
  assert.deepEqual(await f.call({sendMail}),
      {status: "requires_review", emailSent: false});
  assert.equal(f.records.get("quotes/" + ID).emailDelivery.status,
      "needs_review");
  await f.call({sendMail});
  assert.equal(f.stats.send, 1);
});

test("Une acceptation SMTP ambiguë ne doit pas annoncer un mail envoyé", async () => {
  const f = fixture();
  const sendMail = async () => {
    f.stats.send++;
    return {accepted: [], rejected: [EMAIL]};
  };
  const result = await f.call({sendMail});
  assert.equal(result.emailSent, false);
  assert.equal(result.status, "requires_review");
  assert.equal(f.records.get("quotes/" + ID).emailDelivery.status,
      "needs_review");
});

test("Panne Firestore après SMTP : aucune confirmation ni second essai", async () => {
  const f = fixture();
  f.stats.failCompletion = true;
  const result = await f.call();
  assert.equal(result.status, "requires_review");
  assert.equal(result.emailSent, false);
  assert.equal(f.records.get("quotes/" + ID).emailDelivery.status,
      "sending");
  await f.call();
  assert.equal(f.stats.send, 1);
});

test("Un devis non archivé ne peut partir", async () => {
  const f = fixture();
  f.records.get("quotes/" + ID).pdfArchived = false;
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("Un registre altéré empêche tout envoi", async () => {
  const f = fixture();
  f.records.get("documents/" + DOC_ID).sha256 = "a".repeat(64);
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("Sans autorisation juridique consommée, aucun SMTP", async () => {
  const f = fixture();
  f.records.get("quoteIssueAuthorizations/" + ID).status =
      "approved_for_numbering";
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("Fausse déclaration fiscale : refus d'envoi", async () => {
  const f = fixture();
  f.records.get("quoteIssueAuthorizations/" + ID).fiscalityVerified = false;
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("L'adresse mail vient du compte Admin protégé", async () => {
  const f = fixture();
  f.preparedDelivery.message.to = "pirate@example.invalid";
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("Une pièce jointe PDF altérée empêche l'envoi", async () => {
  const f = fixture();
  f.preparedDelivery.message.attachments[0].content[22] ^= 1;
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("Un compte Admin suspendu ou un doublon ne peut envoyer", async () => {
  const f = fixture();
  f.records.get("adminAccounts/" + EMAIL).accountStatus = "SUSPENDED";
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  f.records.get("adminAccounts/" + EMAIL).accountStatus = "ACTIVE";
  f.records.set("adminAccounts/other@example.invalid", {
    email: "other@example.invalid", role: "ADMIN", accountStatus: "ACTIVE",
    adminUid: UID, territoireId: "terr-1",
  });
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("Sans PDF préparé ou transporteur, aucun départ", async () => {
  const f = fixture();
  await assert.rejects(f.call({preparedDelivery: {}}),
      {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  await assert.rejects(f.call({sendMail: null}),
      {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});

test("Un historique d'envoi altéré interdit toute nouvelle tentative", async () => {
  const f = fixture();
  await f.call();
  f.records.get("quotes/" + ID).emailDelivery.recipient =
      "autre@example.invalid";
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 1);
});

test("Une autorisation ne peut porter une autre période", async () => {
  const f = fixture();
  f.records.get("quoteIssueAuthorizations/" + ID).validUntil =
      "2026-11-13";
  await assert.rejects(f.call(), {code: "ADMIN_QUOTE_EMAIL_NOT_ALLOWED"});
  assert.equal(f.stats.send, 0);
});
