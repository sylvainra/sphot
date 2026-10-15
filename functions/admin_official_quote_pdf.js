/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const PDFDocument = require("pdfkit");
const {buildSphotMessage} = require("./sphot_email_design");
const {assessAdminQuoteIssueReadiness} =
    require("./admin_quote_issue_readiness");

const BLUE = "#1E3A8A";
const RED = "#DC2626";
const PAD = 42;

// Moteur PDF du véritable DEVIS officiel.
// AUCUN téléchargement client, AUCUNE écriture Firestore et AUCUN devis
// émis par ce module. Le serveur appellera ce moteur seulement APRÈS :
// authentification, vérification des droits et du payeur, fiscalité déterminée,
// recalcul du tarif PUBLIÉ, numérotation DV transactionnelle.
// Un document sans émetteur immatriculé ou sans numéro DV est refusé.
function renderOfficialAdminQuotePdf(context, quoteNumber,
    administrativeReference) {
  const readiness = assessAdminQuoteIssueReadiness(context);
  if (!readiness.ready) {
    const error = new Error("Devis officiel impossible : " +
        readiness.issues.join(", "));
    error.code = "QUOTE_NOT_READY";
    throw error;
  }
  if (typeof quoteNumber !== "string" ||
      !/^DV-\d{4}-\d{6}-\d{3,}$/.test(quoteNumber)) {
    throw new Error("Numéro DV officiel attribué au serveur requis.");
  }
  if (Number(quoteNumber.slice(3, 7)) !==
      Number(context.issuedOn.slice(0, 4))) {
    throw new Error("L'année du devis ne correspond pas à son émission.");
  }
  if (typeof administrativeReference !== "string" ||
      !administrativeReference.startsWith("SPHOT-ADM-")) {
    throw new Error("Référence du dossier administratif manquante.");
  }

  const issuer = context.issuer;
  const buyer = context.buyer;
  const quote = context.publishedQuote;
  const tax = context.taxDecision;
  const stations = context.stations;
  const validity = readiness.validity;

  // Images de la charte SPHOT déjà utilisées dans les emails :
  // vrai titre PNG en haut (sans carte ni contour), Fire en bas sans signature.
  const images = buildSphotMessage({text: ""}).attachments;
  const titleImage = images.find((a) => a.filename === "sphot_title.png");
  const fireImage = images.find((a) => a.filename === "fire_red_icon.png");
  if (!titleImage || !fireImage) {
    throw new Error("Images de la charte SPHOT indisponibles.");
  }
  const money = (n) => n.toFixed(2).replace(".", ",") + " EUR";
  const clean = (value) => String(value ?? "").trim();
  const address = (data) => [
    clean(data.address), clean(data.postalCode) + " " + clean(data.city),
    clean(data.country),
  ].filter(Boolean).join(", ");

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "A4",
      margins: {top: 28, bottom: 72, left: PAD, right: PAD},
      info: {
        Title: "DEVIS SPHOT ADMIN " + quoteNumber,
        Author: issuer.legalName,
        Subject: administrativeReference,
      },
    });
    const buffers = [];
    doc.on("data", (part) => buffers.push(part));
    doc.on("end", () => resolve(Buffer.concat(buffers)));
    doc.on("error", reject);

    const fullWidth = doc.page.width - 2 * PAD;
    const usableBottom = () => doc.page.height - 104;
    const paragraph = (text, size = 9, color = BLUE, options = {}) => {
      doc.font("Helvetica").fontSize(size).fillColor(color)
          .text(clean(text), PAD, doc.y, {
            width: fullWidth, lineGap: 2, ...options,
          });
      doc.moveDown(0.35);
    };
    const heading = (text) => {
      if (doc.y > usableBottom() - 55) doc.addPage();
      doc.moveDown(0.6);
      doc.font("Helvetica-Bold").fontSize(10).fillColor(BLUE)
          .text(text, PAD, doc.y, {width: fullWidth});
      doc.moveDown(0.3);
      doc.moveTo(PAD, doc.y).lineTo(PAD + fullWidth, doc.y)
          .strokeColor(BLUE).lineWidth(0.6).stroke();
      doc.moveDown(0.5);
    };
    const safeLine = (text) => {
      if (doc.y > usableBottom() - 24) doc.addPage();
      paragraph(text);
    };

    // Ne jamais utiliser le nom commercial à la place de l'émetteur légal.
    doc.image(titleImage.content, doc.page.width / 2 - 115, 27,
        {fit: [230, 43], align: "center"});
    doc.y = 85;
    doc.font("Helvetica-Bold").fontSize(15).fillColor(RED)
        .text("DEVIS SPHOT ADMIN", PAD, doc.y, {width: fullWidth});
    doc.moveDown(0.5);
    paragraph("Devis : " + quoteNumber);
    paragraph("Dossier administratif : " + administrativeReference);
    paragraph("Émis le : " + validity.issuedOn +
        "  |  Valable jusqu'au : " + validity.validUntil + " inclus");

    heading("ÉMETTEUR");
    safeLine(issuer.legalName);
    safeLine("Identifiant : " +
        (issuer.country === "FR" ? "SIRET " + issuer.siret : issuer.officialId));
    safeLine(address(issuer));

    heading("ORGANISME PAYEUR");
    safeLine(buyer.legalName);
    safeLine("Identifiant : " +
        (buyer.country === "FR" ? "SIRET " + buyer.siret : buyer.officialId));
    safeLine(address(buyer));
    safeLine("Contact facturation : " + buyer.billingEmail);

    heading("SPHOTS CONCERNÉS");
    for (const spot of stations) {
      safeLine((spot.idSphot ? spot.idSphot + " - " : "") +
          "Poste de secours - " + spot.name);
    }

    heading("OFFRE ANNUELLE");
    safeLine("Tarif publié : " + quote.pricingReference);
    safeLine("Nombre de postes : " + quote.numberOfRescueStations);
    const tiers = [
      "1er poste", "Du 2e au 4e", "Du 5e au 9e", "À partir du 10e",
    ];
    quote.lines.forEach((line, index) => {
      if (line.count > 0) {
        safeLine(tiers[index] + " : " + line.count + " x " +
            money(line.unitExclTax) + " = " + money(line.amountExclTax));
      }
    });

    heading("MONTANTS ET FISCALITÉ");
    safeLine("Total HT : " + money(tax.amountExclTax));
    safeLine("Taxes applicables : " + money(tax.taxAmount));
    doc.font("Helvetica-Bold").fontSize(12).fillColor(RED)
        .text("TOTAL TTC : " + money(tax.amountInclTax), PAD, doc.y);
    doc.moveDown(0.6);
    safeLine("Traitement fiscal : " + tax.taxTreatment);
    safeLine("Fondement fiscal : " + tax.legalBasis);
    safeLine("Pays de facturation : " + buyer.country);

    heading("PÉRIODE ET VALIDITÉ");
    safeLine("Année d'abonnement : " + context.subscriptionYear);
    safeLine("Abonnement annuel jusqu'au 31 décembre, sans prorata. " +
        "Renouvellement au 1er janvier selon les conditions contractuelles.");
    safeLine("Offre valable 30 jours calendaires maximum, " +
        "jusqu'au " + validity.validUntil + " inclus.");
    safeLine("Un devis n'est ni une commande ni un paiement. " +
        "Les modalités et CGV applicables seront présentées à l'engagement.");

    // PIED : véritable Fire SPHOT au centre, sans « L'équipe SPHOT ».
    // L'emplacement est fixe sur la dernière page, hors du contenu.
    const page = doc.page;
    if (doc.y > usableBottom()) doc.addPage();
    doc.image(fireImage.content, doc.page.width / 2 - 15,
        doc.page.height - 94, {fit: [30, 47]});
    doc.strokeColor(BLUE).lineWidth(0.5)
        .moveTo(PAD, doc.page.height - 42)
        .lineTo(doc.page.width - PAD, doc.page.height - 42).stroke();
    doc.font("Helvetica").fontSize(7).fillColor(BLUE)
        .text("Document officiel " + quoteNumber,
            PAD, doc.page.height - 35,
            {width: fullWidth, align: "center"});
    void page;
    doc.end();
  });
}

module.exports = {renderOfficialAdminQuotePdf};
