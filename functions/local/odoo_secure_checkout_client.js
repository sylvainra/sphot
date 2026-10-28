/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Adaptateur technique de la NOUVELLE passerelle Odoo, distinct du parcours
// historique. Il n'est exposé par aucune route HTTP et ne déclenche aucun
// paiement, aucune écriture Firebase et aucune activation de campagne.
// Les corps correspondent aux signatures de models/checkout.py communiquées
// le 28/10/2026. Le test réel Odoo reste à faire sur la base neutralisée.

const crypto = require("node:crypto");
const {buildOdooDraft} = require("../odoo_commercial_bridge");

const CHECKOUT_TEST_DATABASE = "sphot_publicitaire_checkout_test";
const CHECKOUT_MODEL = "sphot.advertiser.checkout";
const DRAFT_METHOD = "create_or_get_draft_order";
const INVOICE_METHOD = "confirm_and_post_one_invoice";
const ORDER_CONTRACT = "sphot_advertiser_atomic_order_v1";
const INVOICE_CONTRACT = "sphot_advertiser_atomic_invoice_v1";

function invalid(message) {
  const error = new Error(message);
  error.httpStatus = 400;
  return error;
}

function assertNeutralizedDatabase(database) {
  if (database !== CHECKOUT_TEST_DATABASE) {
    throw invalid("Passerelle sécurisée réservée à la base Odoo neutralisée.");
  }
}

// Empreinte observée lors des tests Odoo du 27/10/2026 :
// référence|client_id|produit_id|montant_HT_à_2_décimales|remise.
// Les valeurs doivent provenir d'un devis recalculé côté serveur, jamais
// d'un prix ou d'un identifiant librement transmis par le navigateur.
function trustedFingerprint({reference, partnerId, productId,
  amountExclTaxCents, discountPercent}) {
  if (typeof reference !== "string" ||
      !/^SPHOT-PUB-PROD-[A-F0-9]{16}$/.test(reference) ||
      !Number.isSafeInteger(partnerId) || partnerId <= 0 ||
      !Number.isSafeInteger(productId) || productId <= 0 ||
      !Number.isSafeInteger(amountExclTaxCents) || amountExclTaxCents <= 0 ||
      !Number.isInteger(discountPercent) ||
      discountPercent < 0 || discountPercent > 90) {
    throw invalid("Données serveur invalides pour l'empreinte Odoo.");
  }
  const amount = `${Math.floor(amountExclTaxCents / 100)}.${String(
      amountExclTaxCents % 100).padStart(2, "0")}`;
  return crypto.createHash("sha256")
      .update(`${reference}|${partnerId}|${productId}|${amount}|${discountPercent}`)
      .digest("hex");
}

function secureReferenceFor(requestId) {
  if (typeof requestId !== "string" ||
      !/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) {
    throw invalid("Dossier publicitaire SPHOT invalide.");
  }
  const hex = crypto.createHash("sha256")
      .update("SPHOT_ADVERTISER_CHECKOUT_V2:").update(requestId)
      .digest("hex").slice(0, 16).toUpperCase();
  return `SPHOT-PUB-PROD-${hex}`;
}

function prepareTrustedOrder({requestId, quote, partnerId, productId}) {
  const reference = secureReferenceFor(requestId);
  const draft = buildOdooDraft({quote, partnerId,
    productIds: {advertiser: productId}, sphotReference: reference});
  const amountExclTaxCents = quote.amountExclTax * 100;
  const fingerprint = trustedFingerprint({reference, partnerId, productId,
    amountExclTaxCents, discountPercent: quote.discountPercent});
  return {
    reference, fingerprint, partnerId, productId,
    expectedUntaxedCents: draft.expectedUntaxedCents,
    priceUnitCents: amountExclTaxCents,
    discountPercent: quote.discountPercent,
    orderValues: draft.values,
  };
}

function assertMethodBody(body) {
  if (!body || typeof body !== "object" || Array.isArray(body) ||
      Object.getPrototypeOf(body) !== Object.prototype) {
    throw invalid("Paramètres de passerelle Odoo invalides.");
  }
}

function assertOutcome(result) {
  if (!result || typeof result !== "object" || Array.isArray(result) ||
      !["created", "existing"].includes(result.outcome)) {
    throw invalid("Résultat de passerelle Odoo inattendu.");
  }
  return result;
}

function cents(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw invalid("Montant retourné par Odoo invalide.");
  }
  const result = Math.round(value * 100);
  if (!Number.isSafeInteger(result)) {
    throw invalid("Montant Odoo hors limites.");
  }
  return result;
}

function relationId(value) {
  if (Number.isSafeInteger(value) && value > 0) return value;
  return Array.isArray(value) && Number.isSafeInteger(value[0]) &&
      value[0] > 0 ? value[0] : null;
}

function verifiedOrder(order, prepared) {
  if (!order || !Number.isSafeInteger(order.id) || order.id < 1 ||
      order.x_sphot_reference !== prepared.reference ||
      order.x_sphot_fingerprint !== prepared.fingerprint ||
      order.client_order_ref !== prepared.reference ||
      relationId(order.partner_id) !== prepared.partnerId ||
      !Array.isArray(order.currency_id) || order.currency_id[1] !== "EUR" ||
      !["draft", "sent", "sale"].includes(order.state) ||
      cents(order.amount_untaxed) !== prepared.expectedUntaxedCents ||
      cents(order.amount_total) <= 0) {
    throw invalid("Commande Odoo sécurisée incohérente.");
  }
  return order;
}

function verifiedLine(line, prepared) {
  if (!line || relationId(line.product_id) !== prepared.productId ||
      line.product_uom_qty !== 1 ||
      cents(line.price_unit) !== prepared.priceUnitCents ||
      line.discount !== prepared.discountPercent) {
    throw invalid("Ligne de vente Odoo sécurisée incohérente.");
  }
}

function verifiedInvoice(invoice, order, prepared) {
  if (!invoice || !Number.isSafeInteger(invoice.id) || invoice.id < 1 ||
      invoice.x_sphot_reference !== prepared.reference ||
      invoice.x_sphot_fingerprint !== prepared.fingerprint ||
      relationId(invoice.x_sphot_sale_order_id) !== order.id ||
      invoice.invoice_origin !== order.name ||
      relationId(invoice.partner_id) !== prepared.partnerId ||
      !Array.isArray(invoice.currency_id) || invoice.currency_id[1] !== "EUR" ||
      invoice.move_type !== "out_invoice" || invoice.state !== "posted" ||
      !["not_paid", "in_payment", "paid", "partial"].includes(invoice.payment_state) ||
      cents(invoice.amount_untaxed) !== cents(order.amount_untaxed) ||
      cents(invoice.amount_tax) !== cents(order.amount_tax) ||
      cents(invoice.amount_total) !== cents(order.amount_total) ||
      cents(invoice.amount_residual) < 0 ||
      cents(invoice.amount_residual) > cents(invoice.amount_total)) {
    throw invalid("Facture Odoo sécurisée incohérente.");
  }
  return invoice;
}

function createSecureCheckoutClient({database = CHECKOUT_TEST_DATABASE,
  odooClient} = {}) {
  assertNeutralizedDatabase(database);
  const odoo = odooClient;
  if (!odoo || typeof odoo.call !== "function") {
    throw invalid("Client Odoo sécurisé indisponible.");
  }

  async function call(method, body, contract, prepared) {
    // Ne jamais transférer directement un objet fourni par Flutter ici.
    // L'orchestration serveur construit exclusivement les champs attendus
    // par la signature Python vérifiée de models/checkout.py.
    assertMethodBody(body);
    const result = assertOutcome(await odoo.call(CHECKOUT_MODEL, method, body));
    if (result.contract !== contract ||
        result.reference !== prepared.reference ||
        result.fingerprint !== prepared.fingerprint) {
      throw invalid("Contrat Odoo sécurisé non respecté.");
    }
    verifiedOrder(result.order, prepared);
    if (method === DRAFT_METHOD) verifiedLine(result.line, prepared);
    if (method === INVOICE_METHOD) {
      verifiedInvoice(result.invoice, result.order, prepared);
      if (result.invoice.payment_state !== "not_paid" ||
          cents(result.invoice.amount_residual) !==
          cents(result.invoice.amount_total)) {
        throw invalid("La nouvelle facture Odoo ne doit pas être réglée.");
      }
    }
    return result;
  }

  async function status(prepared) {
    const rows = await odoo.call("sale.order", "search_read", {
      domain: [["x_sphot_reference", "=", prepared.reference]],
      fields: ["id", "name", "state", "client_order_ref", "partner_id",
        "currency_id", "amount_untaxed", "amount_tax", "amount_total",
        "order_line", "invoice_ids", "x_sphot_reference", "x_sphot_fingerprint"],
      limit: 2,
    });
    if (!Array.isArray(rows) || rows.length > 1) {
      throw invalid("Plusieurs commandes Odoo pour une référence SPHOT.");
    }
    if (!rows.length) return null;
    const order = verifiedOrder(rows[0], prepared);
    if (!Array.isArray(order.order_line) || !order.order_line.length) {
      throw invalid("Lignes de commande Odoo absentes.");
    }
    const lines = await odoo.call("sale.order.line", "read", {
      ids: order.order_line,
      fields: ["id", "product_id", "product_uom_qty", "price_unit", "discount"],
    });
    if (!Array.isArray(lines) || lines.length !== order.order_line.length) {
      throw invalid("Lignes Odoo introuvables.");
    }
    const productLines = lines.filter((line) => relationId(line.product_id));
    if (productLines.length !== 1) {
      throw invalid("Nombre de produits Odoo inattendu.");
    }
    verifiedLine(productLines[0], prepared);
    if (!Array.isArray(order.invoice_ids) || order.invoice_ids.length > 1) {
      throw invalid("Nombre de factures Odoo ambigu.");
    }
    let invoice = null;
    if (order.invoice_ids.length) {
      const found = await odoo.call("account.move", "read", {
        ids: order.invoice_ids,
        fields: ["id", "name", "invoice_origin", "partner_id",
          "currency_id", "move_type", "state", "payment_state",
          "amount_untaxed", "amount_tax", "amount_total", "amount_residual",
          "matched_payment_ids", "x_sphot_reference", "x_sphot_fingerprint",
          "x_sphot_sale_order_id"],
      });
      if (!Array.isArray(found) || found.length !== 1 ||
          found[0].id !== order.invoice_ids[0] || order.state !== "sale") {
        throw invalid("Facture Odoo liée incohérente.");
      }
      invoice = verifiedInvoice(found[0], order, prepared);
    } else if (!["draft", "sent"].includes(order.state)) {
      throw invalid("Commande confirmée sans facture sécurisée.");
    }
    return {order, invoice};
  }

  async function draft(prepared) {
    const existing = await status(prepared);
    if (existing) return {outcome: "existing", ...existing};
    const result = await call(DRAFT_METHOD, {
      sphot_reference: prepared.reference,
      sphot_fingerprint: prepared.fingerprint,
      expected_untaxed_cents: prepared.expectedUntaxedCents,
      order_values: prepared.orderValues,
    }, ORDER_CONTRACT, prepared);
    return {outcome: result.outcome, ...await status(prepared)};
  }

  async function invoice(prepared) {
    const existing = await status(prepared);
    if (!existing) throw invalid("Commande Odoo non créée.");
    if (existing.invoice) return {outcome: "existing", ...existing};
    const result = await call(INVOICE_METHOD, {
      sphot_reference: prepared.reference,
      sphot_fingerprint: prepared.fingerprint,
      sale_order_id: existing.order.id,
      expected_total_cents: cents(existing.order.amount_total),
    }, INVOICE_CONTRACT, prepared);
    return {outcome: result.outcome, ...await status(prepared)};
  }

  return {status, draft, invoice};
}

module.exports = {CHECKOUT_TEST_DATABASE, CHECKOUT_MODEL,
  DRAFT_METHOD, INVOICE_METHOD, ORDER_CONTRACT, INVOICE_CONTRACT,
  assertNeutralizedDatabase, trustedFingerprint, secureReferenceFor,
  prepareTrustedOrder, createSecureCheckoutClient};
