/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {handleAdminQuotePortalRequest} =
    require("../admin_quote_portal_api");

const PDF = Buffer.concat([
  Buffer.from("%PDF-1.7\n"), Buffer.alloc(1200), Buffer.from("\n%%EOF"),
]);
function fixture(action = "preview") {
  const headers = {};
  const answers = [];
  const calls = {preview: 0, pdf: 0, request: null};
  const req = {
    method: "POST", body: {action},
    get: (name) => name === "Authorization" ? "Bearer FAKE_TOKEN" : "",
  };
  const res = {
    code: null,
    set(name, value) {
      headers[name] = value;
      return this;
    },
    status(code) {
      this.code = code;
      return this;
    },
    json(data) {
      answers.push(data);
      return this;
    },
    send(data) {
      answers.push(data);
      return this;
    },
  };
  const services = {
    auth: {}, db: {}, bucket: {},
    async readDraft(args) {
      calls.preview++;
      calls.request = args;
      return {
        status: "draft_preview", issuanceAuthorized: false,
        administrativeReference: "SPHOT-ADM-2026-000001",
        stations: [{idSphot: "TEST 01", name: "Poste fictif"}],
        buyer: {legalName: "Commune fictive"},
        buyerFieldsComplete: true,
        publishedQuote: {
          amountExclTax: 499, pricingReference: "FR_ADMIN-V3",
          currency: "EUR",
        },
      };
    },
    async readPdf(args) {
      calls.pdf++;
      calls.request = args;
      return {
        pdfBuffer: PDF,
        filename: "DV-2026-000001-001.pdf", mimeType: "application/pdf",
      };
    },
  };
  const run = async () => handleAdminQuotePortalRequest(req, res, services);
  return {req, res, headers, answers, services, calls, run};
}

test("Aperçu : prix publié et statut non émis, jamais les prix clients", async () => {
  const f = fixture();
  f.req.body.amountExclTax = 999999;
  f.req.body.adminUid = "autre";
  f.req.body.issuanceAuthorized = true;
  await f.run();
  assert.equal(f.res.code, 200);
  assert.equal(f.answers[0].amountExclTax, 499);
  assert.equal(f.answers[0].issuanceAuthorized, false);
  assert.equal(f.answers[0].taxAmount, null);
  assert.equal(f.answers[0].amountInclTax, null);
  assert.equal(f.answers[0].status, "draft_preview");
  assert.equal(f.calls.request.idToken, "FAKE_TOKEN");
  assert.equal(Object.hasOwn(f.calls.request, "adminUid"), false);
  assert.equal(Object.hasOwn(f.calls.request, "amountExclTax"), false);
  assert.equal(f.headers["Cache-Control"], "no-store, private");
  assert.equal(f.calls.pdf, 0);
});

test("Téléchargement : octets exacts et aucune URL publique", async () => {
  const f = fixture("download");
  f.req.body.documentId = "admin-1_DV-2026-000001-001";
  f.req.body.storagePath = "public/faux.pdf";
  await f.run();
  assert.equal(f.res.code, 200);
  assert.equal(f.calls.preview, 0);
  assert.equal(f.calls.pdf, 1);
  assert.equal(f.calls.request.documentId, f.req.body.documentId);
  assert.equal(Object.hasOwn(f.calls.request, "storagePath"), false);
  assert.deepEqual(f.answers[0], PDF);
  assert.equal(f.headers["Content-Type"], "application/pdf");
  assert.equal(f.headers["Content-Disposition"],
      "attachment; filename=\"DV-2026-000001-001.pdf\"");
});

test("Sans jeton, aucune lecture n'est possible", async () => {
  const f = fixture();
  f.req.get = () => "";
  await f.run();
  assert.equal(f.res.code, 401);
  assert.equal(f.calls.preview, 0);
  assert.equal(f.calls.pdf, 0);
});

test("Méthode ou action non autorisée : aucune lecture", async () => {
  const f = fixture();
  f.req.method = "GET";
  await f.run();
  assert.equal(f.res.code, 405);
  assert.equal(f.calls.preview, 0);
  const x = fixture("issue_quote");
  await x.run();
  assert.equal(x.res.code, 400);
  assert.equal(x.calls.preview, 0);
  assert.equal(x.calls.pdf, 0);
});

test("Un brouillon dont l'émission est annoncée est refusé", async () => {
  const f = fixture();
  f.services.readDraft = async () => ({
    status: "draft_preview", issuanceAuthorized: true,
  });
  await f.run();
  assert.equal(f.res.code, 403);
});

test("Le refus du lecteur PDF ne révèle ni identité ni document", async () => {
  const f = fixture("download");
  f.services.readPdf = async () => {
    throw new Error("Compte utilisateur et Storage sensibles");
  };
  await f.run();
  assert.equal(f.res.code, 403);
  assert.deepEqual(f.answers[0], {
    success: false, error: "ACCESS_DENIED",
  });
});

test("Aucune dépendance de facturation ou de SMTP n'est appelée", async () => {
  const f = fixture();
  await f.run();
  assert.equal(f.calls.preview, 1);
  assert.equal(f.calls.pdf, 0);
  assert.equal(f.answers[0].success, true);
});


test("Consultation : PDF commun et aucune donnée commerciale cliente", async () => {
  const f = fixture("consult");
  f.req.body.adminUid = "admin-pirate";
  f.req.body.amountExclTax = 0;
  f.req.body.storagePath = "other.pdf";
  let received;
  f.services.readConsultation = async (args) => {
    received = args;
    return {
      issuanceAuthorized: false, stations: [],
      buyer: {}, issuer: {}, publishedQuote: null,
    };
  };
  f.services.renderConsultation = async (context) => {
    assert.equal(context.issuanceAuthorized, false);
    return PDF;
  };
  await f.run();
  assert.equal(f.res.code, 200);
  assert.deepEqual(f.answers[0], PDF);
  assert.equal(received.idToken, "FAKE_TOKEN");
  assert.deepEqual(Object.keys(received).sort(), ["auth", "db", "idToken"]);
  assert.equal(f.headers["Content-Type"], "application/pdf");
  assert.equal(f.headers["Content-Disposition"],
      "attachment; filename=\"SPHOT-DEVIS-SPECIMEN.pdf\"");
  assert.equal(f.calls.pdf, 0);
  assert.equal(f.calls.preview, 0);
});

test("Le mode consultation ne peut être converti en émission", async () => {
  const f = fixture("consult");
  f.services.readConsultation = async () => ({
    issuanceAuthorized: true,
  });
  f.services.renderConsultation = async () => {
    throw new Error("Doit être inaccessible");
  };
  await f.run();
  assert.equal(f.res.code, 403);
  assert.deepEqual(f.answers[0], {
    success: false, error: "CONSULTATION_DENIED",
  });
});
