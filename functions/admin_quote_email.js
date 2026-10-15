/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {buildSphotMessage} = require("./sphot_email_design");
const {quoteValidityForCalendarYear} = require("./admin_quote_validity");

// Futur mail de DEVIS OFFICIEL SPHOT ADMIN.
// Prépare uniquement les options Nodemailer ; n'envoie jamais d'email.
// Le logo et le marker Fire sont CEUX de tous les mails SPHOT existants,
// embarqués par buildSphotMessage (CID commun, Fire PNG 42 x 65).
// Le PNG est l'image de compatibilité email du marker SPHOT ; ne pas
// créer une seconde version SVG/PNG dans cette famille de courriels.
function buildAdminOfficialQuoteEmail(record) {
  const data = record && typeof record === "object" ? record : {};
  const filled = (value) =>
    typeof value === "string" && value.trim().length > 0;
  const recipient = filled(data.adminEmail) ? data.adminEmail.trim() : "";
  const number = data.quoteNumber;
  const pdfBuffer = data.pdfBuffer;

  if (data.documentStatus !== "issued" ||
      data.pdfArchived !== true ||
      data.issuerLegallyVerified !== true ||
      data.fiscalityVerified !== true) {
    throw new Error("Email de devis interdit avant son émission officielle.");
  }
  if (!filled(recipient) ||
      !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(recipient)) {
    throw new Error("Email de l'administrateur non renseigné.");
  }
  if (!filled(number) || !/^DV-\d{4}-\d{6}-\d{3,}$/.test(number)) {
    throw new Error("Numéro de devis officiel DV invalide.");
  }
  if (!Buffer.isBuffer(pdfBuffer) ||
      pdfBuffer.length < 1024 ||
      pdfBuffer.subarray(0, 5).toString("ascii") !== "%PDF-") {
    throw new Error("Document PDF officiel non disponible.");
  }
  if (!filled(data.buyerName) ||
      !Number.isFinite(data.amountExclTax) ||
      data.amountExclTax <= 0 ||
      data.currency !== "EUR") {
    throw new Error("Données commerciales du devis manquantes.");
  }
  // Les dates et la validité ne doivent jamais dépendre d'un calcul client.
  const validity = quoteValidityForCalendarYear(
      data.issuedOn, data.subscriptionYear);
  if (validity.validUntil !== data.validUntil ||
      Number(number.substring(3, 7)) !==
          Number(data.issuedOn.substring(0, 4))) {
    throw new Error("Date ou validité du devis incohérente.");
  }

  const formatMoney = (value) =>
    value.toFixed(2).replace(".", ",") + " EUR HT";
  const text = [
    "Madame, Monsieur,",
    "",
    "Votre devis SPHOT ADMIN est disponible en pièce jointe.",
    "",
    "Organisme : " + data.buyerName.trim(),
    "Référence du devis : " + number,
    "Montant annuel hors taxes : " + formatMoney(data.amountExclTax),
    "Validité : jusqu'au " + validity.validUntil + " inclus.",
    "",
    "Ce devis est facultatif. Sa réception n'entraîne ni commande, " +
      "ni paiement, ni activation de l'abonnement.",
    "",
    "Pour toute question : contact@sphot.app",
    "",
    "Cordialement,",
    "L'équipe SPHOT",
  ].join("\n");

  // Cette fonction partagée ajoute UN SEUL marker Fire en pied de mail :
  // cid:sphot-brand-fire-png, largeur 42 et hauteur 65, comme pour
  // les emails de comptes sauveteurs, administrateurs et annonceurs.
  return buildSphotMessage({
    from: '"SPHOT" <no-reply@sphot.app>',
    to: recipient,
    replyTo: "contact@sphot.app",
    subject: "SPHOT ADMIN - Votre devis " + number,
    text,
    attachments: [{
      filename: number + ".pdf",
      content: pdfBuffer,
      contentType: "application/pdf",
    }],
  });
}

module.exports = {buildAdminOfficialQuoteEmail};
