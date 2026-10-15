/* eslint-disable max-len, require-jsdoc, valid-jsdoc, object-curly-spacing */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {buildAdminOfficialQuoteEmail} = require("../admin_quote_email");
const {buildSphotMessage} = require("../sphot_email_design");

function officialTestRecord() {
  return {
    documentStatus: "issued",
    pdfArchived: true,
    issuerLegallyVerified: true,
    fiscalityVerified: true,
    adminEmail: "admin@example.invalid",
    quoteNumber: "DV-2026-000001-001",
    buyerName: "Mairie fictive - environnement de test",
    amountExclTax: 898,
    currency: "EUR",
    issuedOn: "2026-10-15",
    subscriptionYear: 2026,
    validUntil: "2026-11-13",
    // Faux tampon PDF : vérifie seulement l'enveloppe e-mail.
    // Le contenu vrai du PDF a son test distinct.
    pdfBuffer: Buffer.concat([
      Buffer.from("%PDF-1.7\n", "ascii"),
      Buffer.alloc(1100),
    ]),
  };
}

test("Même marker Fire et mêmes dimensions que tous les emails SPHOT", () => {
  const actual = buildAdminOfficialQuoteEmail(officialTestRecord());
  const common = buildSphotMessage({text: "Exemple"});
  const findFire = (mail) => mail.attachments.find(
      (part) => part.cid === "sphot-brand-fire-png");

  const actualFire = findFire(actual);
  const commonFire = findFire(common);
  assert.ok(actualFire);
  assert.ok(commonFire);
  assert.equal(actualFire.filename, "fire_red_icon.png");
  assert.equal(actualFire.contentType, "image/png");
  assert.ok(Buffer.isBuffer(actualFire.content));
  assert.deepEqual(actualFire.content, commonFire.content);
  assert.match(actual.html,
      /<img src="cid:sphot-brand-fire-png" alt="SPHOT" width="42" height="65"/);
  assert.equal(
      actual.html.split('src="cid:sphot-brand-fire-png"').length - 1, 1);
  assert.equal(actual.attachments.filter(
      (part) => part.cid === "sphot-brand-fire-png").length, 1);
});

test("Le devis PDF réel accompagne un mail envoyé à l'Admin", () => {
  const record = officialTestRecord();
  const mail = buildAdminOfficialQuoteEmail(record);
  assert.equal(mail.to, record.adminEmail);
  assert.equal(mail.from, '"SPHOT" <no-reply@sphot.app>');
  assert.equal(mail.replyTo, "contact@sphot.app");
  assert.ok(mail.subject.includes(record.quoteNumber));
  assert.ok(mail.html.includes("898,00 EUR HT"));
  assert.ok(mail.html.includes("2026-11-13"));
  assert.ok(mail.html.includes("ni paiement"));
  const attachment = mail.attachments.find(
      (part) => part.filename === record.quoteNumber + ".pdf");
  assert.ok(attachment);
  assert.strictEqual(attachment.content, record.pdfBuffer);
  assert.equal(attachment.contentType, "application/pdf");
});

test("Aucun mail préparable avant l'émission et l'archivage officiel", () => {
  const data = officialTestRecord();
  for (const missing of [
    {documentStatus: "draft"},
    {pdfArchived: false},
    {issuerLegallyVerified: false},
    {fiscalityVerified: false},
  ]) {
    assert.throws(
        () => buildAdminOfficialQuoteEmail({...data, ...missing}),
        /Email de devis interdit/,
    );
  }
});

test("Pas de mail sans PDF ou numéro de devis valable", () => {
  const data = officialTestRecord();
  assert.throws(() => buildAdminOfficialQuoteEmail(
      {...data, pdfBuffer: null}), /PDF officiel/);
  assert.throws(() => buildAdminOfficialQuoteEmail(
      {...data, quoteNumber: "SPHOT-ADM-2026-000001"}), /DV invalide/);
});

test("La date doit respecter les 30 jours du devis", () => {
  const data = officialTestRecord();
  assert.throws(() => buildAdminOfficialQuoteEmail(
      {...data, validUntil: "2026-12-31"}), /validité du devis incohérente/);
});

test("Le contenu HTML est échappé par le modèle email commun", () => {
  const mail = buildAdminOfficialQuoteEmail({
    ...officialTestRecord(),
    buyerName: "<script>alert('test')</script>",
  });
  assert.ok(!mail.html.includes("<script>"));
  assert.ok(mail.html.includes("&lt;script&gt;"));
});
