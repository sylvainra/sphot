/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

/**
 * Contrat de traduction SPHOT -> devis Odoo.
 * Module PUR : aucun appel reseau, aucun paiement, aucune ecriture Firestore.
 * A appeler UNIQUEMENT apres recalcul serveur et validation du client.
 * L'integration API Odoo sera ouverte quand les identifiants, produits et
 * positions fiscales de l'instance seront disponibles.
 */

function invalid(message) {
  const error = new Error(message);
  error.status = 400;
  return error;
}

function positiveId(value, label) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw invalid(label + " Odoo non configure.");
  }
  return value;
}

function verifyQuote(quote) {
  if (!quote || typeof quote !== "object" ||
      !["ADMIN", "ADVERTISER_RADIUS"].includes(quote.market) ||
      !Number.isSafeInteger(quote.version) || quote.version < 1 ||
      quote.pricingReference !== "FR_" + quote.market +
          "-V" + quote.version ||
      quote.currency !== "EUR" ||
      !Number.isSafeInteger(quote.amountExclTax) ||
      quote.amountExclTax <= 0) {
    throw invalid("Devis SPHOT serveur ou reference tarifaire invalide.");
  }
  if (!Number.isInteger(quote.discountPercent) ||
      quote.discountPercent < 0 || quote.discountPercent > 90) {
    throw invalid("Remise SPHOT invalide.");
  }
  const expectedCents = quote.amountExclTax * (100 - quote.discountPercent);
  if (!Number.isSafeInteger(expectedCents) ||
      !Number.isSafeInteger(quote.payableExclTaxCents) ||
      quote.payableExclTaxCents !== expectedCents) {
    throw invalid("Total HT apres remise incoherent.");
  }
}

function buildOdooDraft({quote, partnerId, productIds, sphotReference}) {
  verifyQuote(quote);
  positiveId(partnerId, "Client");
  if (typeof sphotReference !== "string" ||
      !/^[A-Za-z0-9_-]{6,96}$/.test(sphotReference)) {
    throw invalid("Reference de dossier SPHOT invalide.");
  }

  const items = [];
  if (quote.market === "ADVERTISER_RADIUS") {
    items.push({
      product_id: positiveId(productIds?.advertiser, "Produit publicitaire"),
      product_uom_qty: 1,
      price_unit: quote.amountExclTax,
      discount: quote.discountPercent,
      name: "SPHOT PUBLICITAIRE / " + quote.territory + " / " +
          quote.offer + " / " + quote.duration +
          " / Tarif " + quote.pricingReference,
    });
  } else {
    if (!Array.isArray(quote.lines) || quote.lines.length !== 4 ||
        !Array.isArray(productIds?.adminTiers) ||
        productIds.adminTiers.length !== 4) {
      throw invalid("Quatre tranches ADMIN Odoo necessaires.");
    }
    let total = 0;
    for (let i = 0; i < 4; i++) {
      const line = quote.lines[i];
      if (!line || !Number.isSafeInteger(line.count) || line.count < 0 ||
          !Number.isSafeInteger(line.unitExclTax) ||
          line.unitExclTax <= 0 ||
          line.amountExclTax !== line.count * line.unitExclTax) {
        throw invalid("Tranches ADMIN invalidees.");
      }
      total += line.amountExclTax;
      if (line.count > 0) {
        items.push({
          product_id: positiveId(
              productIds.adminTiers[i], "Produit tranche ADMIN"),
          product_uom_qty: line.count,
          price_unit: line.unitExclTax,
          discount: quote.discountPercent,
          name: "SPHOT ADMIN / Tranche " + (i + 1) +
              " / Tarif " + quote.pricingReference,
        });
      }
    }
    if (total !== quote.amountExclTax) {
      throw invalid("Total des tranches ADMIN incoherent.");
    }
  }

  // Les taxes et les montants TTC ne sont JAMAIS imposes par SPHOT.
  // Le partenaire Odoo doit posseder son pays et sa position fiscale.
  // Les commandes utilisent la devise EUR de la grille SPHOT.
  return {
    model: "sale.order",
    method: "create",
    values: {
      partner_id: partnerId,
      client_order_ref: sphotReference,
      origin: "SPHOT " + quote.pricingReference,
      order_line: items.map((item) => [0, 0, item]),
    },
    // Contrats internes pour la verification des retours Odoo.
    sphotReference,
    pricingReference: quote.pricingReference,
    expectedUntaxedCents: quote.payableExclTaxCents,
    discountPercent: quote.discountPercent,
    paymentState: "not_started",
    automaticRenewal: false,
  };
}

module.exports = {buildOdooDraft, verifyQuote};
