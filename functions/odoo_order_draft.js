/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Brique INTERNE au serveur SPHOT : création idempotente d'un BROUILLON Odoo.
// N'exposer en HTTP que derrière un orchestrateur qui RELIT dans Firestore
// les droits, la grille, les CGV et l'identité du payeur, puis calcule la TVA.
// Aucun champ reçu d'un navigateur ne doit être passé comme `prepared`.
// Ne confirme pas les ventes, n'émet pas de facture, ne facture pas Stripe,
// n'active aucun droit et n'écrit rien dans Firestore.

const ALLOWED = Object.freeze({
  ADMIN: {model: "sphot.admin.checkout",
    contract: "sphot_admin_atomic_order_v1", prefix: "SPHOT-ADM-",
    origin: /^SPHOT FR_ADMIN-V[1-9]\d*$/},
  ADVERTISER: {model: "sphot.advertiser.checkout",
    contract: "sphot_advertiser_atomic_order_v1",
    prefix: "SPHOT-PUB-", origin: /^SPHOT FR_ADVERTISER_RADIUS-V[1-9]\d*$/},
});

function denied(message) {
  const error = new Error(message);
  error.code = "SPHOT_ODOO_ORDER_DRAFT_REFUSED";
  return error;
}

function exactKeys(object, expected) {
  return object !== null && typeof object === "object" &&
    !Array.isArray(object) &&
    Object.keys(object).sort().join("|") === [...expected].sort().join("|");
}

function cents(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw denied("Montant Odoo non vérifié.");
  }
  const rounded = Math.round(value * 100);
  if (!Number.isSafeInteger(rounded) ||
      Math.abs(value * 100 - rounded) > 0.000001) {
    throw denied("Précision du montant Odoo non vérifiée.");
  }
  return rounded;
}

function relationId(value) {
  if (Number.isSafeInteger(value) && value > 0) return value;
  if (Array.isArray(value) && value.length === 2 &&
      Number.isSafeInteger(value[0]) && value[0] > 0) return value[0];
  return null;
}

// Normalise une préparation faite dans une AUTRE fonction serveur vérifiée.
// La propriété source n'est PAS une signature de confiance : le contrôleur
// futur doit bâtir cet objet, sans recopier un body JSON du navigateur.
function assertPrepared(market, prepared) {
  const cfg = ALLOWED[market];
  if (!cfg || !prepared || prepared.market !== market ||
      prepared.testOnly !== false ||
      prepared.source !== "SPHOT_SERVER_VERIFIED_CHECKOUT_V1" ||
      prepared.verified !== true ||
      typeof prepared.reference !== "string" ||
      !new RegExp(`^${cfg.prefix}[A-Z0-9_-]{8,100}$`).test(prepared.reference) ||
      prepared.reference.includes("-TEST-") ||
      !/^[a-f0-9]{64}$/.test(prepared.fingerprint || "") ||
      !Number.isSafeInteger(prepared.expectedUntaxedCents) ||
      prepared.expectedUntaxedCents <= 0 ||
      !Number.isSafeInteger(prepared.expectedTotalCents) ||
      prepared.expectedTotalCents < prepared.expectedUntaxedCents) {
    throw denied("Devis commercial serveur absent ou incomplet.");
  }
  const values = prepared.orderValues;
  if (!exactKeys(values, ["partner_id", "client_order_ref", "origin",
    "order_line"]) ||
      !Number.isSafeInteger(values.partner_id) || values.partner_id < 1 ||
      values.client_order_ref !== prepared.reference ||
      !cfg.origin.test(values.origin) ||
      !Array.isArray(values.order_line) ||
      values.order_line.length < 1 ||
      values.order_line.length > (market === "ADMIN" ? 4 : 1)) {
    throw denied("Données de commande Odoo incomplètes.");
  }
  let totalBeforeDiscount = 0;
  let discount = null;
  const products = new Set();
  let lastTier = 0;
  for (const row of values.order_line) {
    if (!Array.isArray(row) || row.length !== 3 || row[0] !== 0 ||
        row[1] !== 0 || !exactKeys(row[2], ["name", "product_id",
          "product_uom_qty", "price_unit", "discount"])) {
      throw denied("Ligne de commande Odoo non autorisée.");
    }
    const item = row[2];
    if (!Number.isSafeInteger(item.product_id) || item.product_id < 1 ||
        products.has(item.product_id) ||
        !Number.isSafeInteger(item.product_uom_qty) ||
        item.product_uom_qty < 1 || item.product_uom_qty > 10000 ||
        !Number.isSafeInteger(item.price_unit) || item.price_unit < 1 ||
        !Number.isInteger(item.discount) || item.discount < 0 ||
        item.discount > 90 || typeof item.name !== "string") {
      throw denied("Produit ou prix Odoo non vérifié.");
    }
    products.add(item.product_id);
    if (discount === null) discount = item.discount;
    if (discount !== item.discount) {
      throw denied("Remise Odoo incohérente entre produits.");
    }
    if (market === "ADMIN") {
      const match = /^SPHOT ADMIN \/ Tranche ([1-4]) \/ Tarif (FR_ADMIN-V[1-9]\d*)$/
          .exec(item.name);
      if (!match || values.origin !== `SPHOT ${match[2]}` ||
          Number(match[1]) <= lastTier) {
        throw denied("Tranche ADMIN Odoo incohérente.");
      }
      lastTier = Number(match[1]);
    } else if (!item.name.startsWith("SPHOT PUBLICITAIRE / ") ||
        !item.name.endsWith(` / Tarif ${values.origin.slice(6)}`) ||
        item.name.length > 300) {
      throw denied("Ligne PUBLICITAIRE Odoo incohérente.");
    }
    totalBeforeDiscount += item.product_uom_qty * item.price_unit;
    if (!Number.isSafeInteger(totalBeforeDiscount)) {
      throw denied("Total de commande Odoo invalide.");
    }
  }
  if (totalBeforeDiscount * (100 - discount) !==
      prepared.expectedUntaxedCents ||
      !Number.isSafeInteger(totalBeforeDiscount * (100 - discount))) {
    throw denied("Montant HT recalculé différent du devis SPHOT.");
  }
  return cfg;
}

function validateOrder(order, prepared, outcome) {
  if (!order || !Number.isSafeInteger(order.id) || order.id < 1 ||
      typeof order.name !== "string" || !order.name.trim() ||
      order.x_sphot_reference !== prepared.reference ||
      order.x_sphot_fingerprint !== prepared.fingerprint ||
      order.client_order_ref !== prepared.reference ||
      relationId(order.partner_id) !== prepared.orderValues.partner_id ||
      !Array.isArray(order.currency_id) || order.currency_id[1] !== "EUR" ||
      !["draft", "sent", "sale"].includes(order.state) ||
      !Array.isArray(order.order_line) ||
      order.order_line.length < prepared.orderValues.order_line.length ||
      !Array.isArray(order.invoice_ids) || order.invoice_ids.length > 1 ||
      (outcome === "created" &&
        (order.state !== "draft" || order.invoice_ids.length > 0)) ||
      cents(order.amount_untaxed) !== prepared.expectedUntaxedCents ||
      cents(order.amount_total) !== prepared.expectedTotalCents ||
      cents(order.amount_tax) !==
        prepared.expectedTotalCents - prepared.expectedUntaxedCents) {
    throw denied("Commande Odoo différente du devis vérifié.");
  }
  return {outcome, reference: prepared.reference,
    orderNumber: order.name, orderState: order.state,
    amountUntaxedCents: prepared.expectedUntaxedCents,
    amountTotalCents: prepared.expectedTotalCents,
    // Ne prouve ni règlement ni activation commerciale.
    paymentStatus: "unverified", activatesCommercialRights: false};
}

async function createOrGetOdooDraft({market, prepared, odooClient} = {}) {
  const cfg = assertPrepared(market, prepared);
  if (!odooClient || typeof odooClient.call !== "function") {
    throw denied("Passerelle HTTPS Odoo absente.");
  }
  // La méthode Odoo est atomique sur x_sphot_reference : en cas de reprise,
  // elle doit retourner la même commande, jamais en créer une deuxième.
  // Pas de retry réseau aveugle après résultat incertain.
  const result = await odooClient.call(cfg.model,
      "create_or_get_draft_order", {
        sphot_reference: prepared.reference,
        sphot_fingerprint: prepared.fingerprint,
        expected_untaxed_cents: prepared.expectedUntaxedCents,
        expected_total_cents: prepared.expectedTotalCents,
        order_values: prepared.orderValues,
      });
  if (!result || result.contract !== cfg.contract ||
      !["created", "existing"].includes(result.outcome) ||
      result.reference !== prepared.reference ||
      result.fingerprint !== prepared.fingerprint) {
    throw denied("Réponse de commande Odoo non vérifiée.");
  }
  return validateOrder(result.order, prepared, result.outcome);
}

module.exports = {assertPrepared, createOrGetOdooDraft};
