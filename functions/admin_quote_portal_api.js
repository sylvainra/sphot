/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const {loadRealAdminQuoteDraft} = require("./admin_quote_real_data");
const {readArchivedAdminQuotePdf} = require("./admin_quote_download");

// Liaison HTTP INTERNE en lecture seule : PAS d'export dans index.js.
// AUCUN numéro DV, aucune création de devis, aucun email, aucune commande.
// Le futur endpoint Firebase doit définir une politique CORS explicite et
// faire l'objet d'une validation avant toute mise en ligne.
async function handleAdminQuotePortalRequest(req, res, services = {}) {
  res.set("Cache-Control", "no-store, private");
  res.set("X-Content-Type-Options", "nosniff");
  res.set("Vary", "Authorization, Origin");

  if (!req || req.method !== "POST") {
    res.status(405).json({success: false, error: "METHOD_NOT_ALLOWED"});
    return;
  }
  const rawHeader = typeof req.get === "function" ?
    req.get("Authorization") : req.headers && req.headers.authorization;
  const match = typeof rawHeader === "string" ?
    rawHeader.match(/^Bearer ([^\s]+)$/) : null;
  if (!match) {
    res.status(401).json({success: false, error: "AUTH_REQUIRED"});
    return;
  }
  const body = req.body && typeof req.body === "object" &&
      !Array.isArray(req.body) ? req.body : {};
  const action = body.action;
  if (action !== "preview" && action !== "download") {
    res.status(400).json({success: false, error: "UNKNOWN_ACTION"});
    return;
  }

  const {auth, db, bucket} = services;
  if (!auth || !db || (action === "download" && !bucket)) {
    res.status(503).json({success: false, error: "SERVICE_UNAVAILABLE"});
    return;
  }

  try {
    if (action === "preview") {
      // Les seuls paramètres commerciaux proviennent de Firestore serveur.
      // Aucune propriété client (prix, UID, SIRET, poste) n'est transmise.
      const readDraft = services.readDraft || loadRealAdminQuoteDraft;
      const result = await readDraft({auth, db, idToken: match[1]});
      if (!result || result.status !== "draft_preview" ||
          result.issuanceAuthorized !== false) {
        res.status(403).json({success: false, error: "PREVIEW_DENIED"});
        return;
      }
      res.status(200).json({
        success: true,
        status: "draft_preview",
        administrativeReference: result.administrativeReference,
        stations: result.stations.map((s) => ({
          idSphot: s.idSphot, name: s.name,
        })),
        buyerName: result.buyer.legalName,
        buyerFieldsComplete: result.buyerFieldsComplete,
        amountExclTax: result.publishedQuote.amountExclTax,
        pricingReference: result.publishedQuote.pricingReference,
        currency: result.publishedQuote.currency,
        taxAmount: null,
        amountInclTax: null,
        issuanceAuthorized: false,
      });
      return;
    }

    // Une identité vérifiée peut uniquement récupérer SON PDF déjà émis.
    // Aucun chemin Storage fourni par le navigateur n'est utilisé.
    const readPdf = services.readPdf || readArchivedAdminQuotePdf;
    const file = await readPdf({
      auth, db, bucket,
      idToken: match[1], documentId: body.documentId,
    });
    if (!file || !Buffer.isBuffer(file.pdfBuffer) ||
        file.mimeType !== "application/pdf" ||
        !/^DV-\d{4}-\d{6}-\d{3,}\.pdf$/.test(file.filename)) {
      res.status(403).json({success: false, error: "DOCUMENT_DENIED"});
      return;
    }
    res.set("Content-Type", "application/pdf");
    res.set("Content-Disposition",
        "attachment; filename=\"" + file.filename + "\"");
    res.status(200).send(file.pdfBuffer);
  } catch (_) {
    // Aucune information personnelle ou chemin Storage dans les erreurs.
    res.status(403).json({success: false, error: "ACCESS_DENIED"});
  }
}

module.exports = {handleAdminQuotePortalRequest};
