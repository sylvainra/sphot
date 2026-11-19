"use strict";

// SPHOT / Odoo : facturation idempotente INTERNE, NON EXPOSEE en HTTP.
// Aucun export functions/index.js, aucun deploiement ni synchronisation droit.
// Preparation commerciale exclusivement depuis Firestore (tarifs publies,
// CGV versionnees, donnees payeur et preuves fiscales Odoo).
// AUCUN montant, prepared ou identifiant Odoo provenant du navigateur.
// Le lien Firestore vers les factures sera traite separement et seulement
// apres verification du rapprochement - pas de simulation de paiement.

const {resolveOdooCheckoutIdentity} = require("./odoo_checkout_identity");
const {prepareCheckoutFromFirestore} =
    require("./odoo_checkout_verified_preparation");
const {assertServerPreparation, sameIntent} =
    require("./odoo_checkout_orchestrator");

const COLLECTION = "odooCheckoutIntents";
const INVOICE_CONTRACT = Object.freeze({
  ADMIN: "sphot_admin_atomic_invoice_v1",
  ADVERTISER: "sphot_advertiser_atomic_invoice_v1",
});
const MODEL = Object.freeze({
  ADMIN: "sphot.admin.checkout",
  ADVERTISER: "sphot.advertiser.checkout",
});

function refuse(message) {
  const error = new Error(message);
  error.code = "SPHOT_ODOO_INVOICE_NOT_VERIFIED";
  error.httpStatus = 409;
  return error;
}
function integer(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw refuse("Montant Odoo invalide.");
  }
  const result = Math.round(value * 100);
  if (!Number.isSafeInteger(result) ||
      Math.abs(value * 100 - result) > 0.000001) {
    throw refuse("Precision Odoo invalide.");
  }
  return result;
}
function relatedId(value) {
  return Array.isArray(value) ? value[0] : value;
}
function validRelation(value, id) {
  return relatedId(value) === id;
}
function validateIntent(identity, prepared, intent) {
  const market = assertServerPreparation(identity, prepared);
  if (!intent || !sameIntent(intent, identity, prepared) ||
      intent.status !== "draft_created" ||
      intent.activatesCommercialRights !== false ||
      intent.paymentStatus !== "unverified" ||
      typeof intent.orderNumber !== "string" ||
      !intent.orderNumber.trim()) {
    throw refuse("Commande SPHOT non reservee ou non verifiee.");
  }
  return market;
}
function validateOrder(order, prepared, intent) {
  if (!order || !Number.isSafeInteger(order.id) || order.id <= 0 ||
      order.name !== intent.orderNumber ||
      order.x_sphot_reference !== prepared.reference ||
      order.x_sphot_fingerprint !== prepared.fingerprint ||
      order.client_order_ref !== prepared.reference ||
      !validRelation(order.partner_id, prepared.orderValues.partner_id) ||
      !Array.isArray(order.currency_id) || order.currency_id[1] !== "EUR" ||
      !["draft", "sent", "sale"].includes(order.state) ||
      !Array.isArray(order.invoice_ids) || order.invoice_ids.length > 1 ||
      integer(order.amount_untaxed) !== prepared.expectedUntaxedCents ||
      integer(order.amount_total) !== prepared.expectedTotalCents ||
      integer(order.amount_tax) !==
        prepared.expectedTotalCents - prepared.expectedUntaxedCents) {
    throw refuse("Commande Odoo incoherente avec le dossier.");
  }
  return order;
}
function validateInvoice(invoice, order, prepared) {
  const state = invoice?.payment_state;
  if (!invoice || !Number.isSafeInteger(invoice.id) || invoice.id <= 0 ||
      invoice.state !== "posted" || invoice.move_type !== "out_invoice" ||
      !["not_paid", "in_payment", "partial", "paid"].includes(state) ||
      invoice.invoice_origin !== order.name ||
      !validRelation(invoice.partner_id, prepared.orderValues.partner_id) ||
      !Array.isArray(invoice.currency_id) ||
      invoice.currency_id[1] !== "EUR" ||
      invoice.x_sphot_reference !== prepared.reference ||
      invoice.x_sphot_fingerprint !== prepared.fingerprint ||
      !validRelation(invoice.x_sphot_sale_order_id, order.id) ||
      integer(invoice.amount_untaxed) !== prepared.expectedUntaxedCents ||
      integer(invoice.amount_tax) !==
        prepared.expectedTotalCents - prepared.expectedUntaxedCents ||
      integer(invoice.amount_total) !== prepared.expectedTotalCents ||
      integer(invoice.amount_residual) > prepared.expectedTotalCents ||
      (state === "paid" && integer(invoice.amount_residual) !== 0)) {
    throw refuse("Facture Odoo incoherente avec la commande SPHOT.");
  }
  return invoice;
}
async function readOrder(odooClient, prepared, intent) {
  const rows = await odooClient.call("sale.order", "search_read", {
    domain: [["x_sphot_reference", "=", prepared.reference]],
    fields: ["id", "name", "state", "partner_id", "currency_id",
      "client_order_ref", "invoice_ids", "amount_untaxed", "amount_tax",
      "amount_total", "x_sphot_reference", "x_sphot_fingerprint"],
    limit: 2,
  });
  if (!Array.isArray(rows) || rows.length !== 1) {
    throw refuse("Commande Odoo unique introuvable.");
  }
  return validateOrder(rows[0], prepared, intent);
}
async function readInvoice(odooClient, order, prepared) {
  if (order.state !== "sale" || order.invoice_ids.length !== 1) {
    throw refuse("Commande Odoo sans facture unique confirmee.");
  }
  const invoices = await odooClient.call("account.move", "read", {
    ids: order.invoice_ids,
    fields: ["id", "name", "state", "payment_state", "move_type",
      "invoice_origin", "partner_id", "currency_id", "amount_untaxed",
      "amount_tax", "amount_total", "amount_residual",
      "x_sphot_reference", "x_sphot_fingerprint",
      "x_sphot_sale_order_id"],
  });
  if (!Array.isArray(invoices) || invoices.length !== 1 ||
      invoices[0].id !== order.invoice_ids[0]) {
    throw refuse("Facture Odoo unique introuvable.");
  }
  return validateInvoice(invoices[0], order, prepared);
}

/**
 * Etape comptable d'un dossier DEJA commande : controle Firestore et Odoo
 * avant d'appeler la methode atomique Odoo; aucun retry aveugle.
 * Ne change aucun droit, abonnement ou statut de paiement Firestore.
 */
async function confirmVerifiedInvoiceFromServer({
  admin, authorization, market, requestId, odooClient,
} = {}) {
  if (!admin || typeof admin.auth !== "function" ||
      typeof admin.firestore !== "function" ||
      !odooClient || typeof odooClient.call !== "function") {
    throw refuse("Dependances du serveur de facturation absentes.");
  }
  const identity = await resolveOdooCheckoutIdentity({
    admin, authorization, market, requestId,
  });
  const db = admin.firestore();
  const prepared = await prepareCheckoutFromFirestore({identity, db, admin});
  const marketKey = assertServerPreparation(identity, prepared);
  const intentId = identity.market + "_" + identity.requestId + "_" +
      prepared.cycleKey;
  const snap = await db.collection(COLLECTION).doc(intentId).get();
  if (!snap.exists) throw refuse("Commande SPHOT absente.");
  const intent = snap.data() || {};
  validateIntent(identity, prepared, intent);

  const first = await readOrder(odooClient, prepared, intent);
  let outcome = "existing";
  if (first.invoice_ids.length === 0) {
    if (!["draft", "sent"].includes(first.state)) {
      throw refuse("Commande confirmee sans facture : traitement manuel.");
    }
    // Une facture est creee exclusivement par la methode atomique du
    // module Odoo deja valide sur le clone, jamais par account.move.create.
    const answer = await odooClient.call(MODEL[marketKey],
        "confirm_and_post_one_invoice", {
          sphot_reference: prepared.reference,
          sphot_fingerprint: prepared.fingerprint,
          sale_order_id: first.id,
          expected_total_cents: prepared.expectedTotalCents,
        });
    if (!answer || answer.contract !== INVOICE_CONTRACT[marketKey] ||
        answer.reference !== prepared.reference ||
        answer.fingerprint !== prepared.fingerprint ||
        !["created", "existing"].includes(answer.outcome) ||
        answer.invoice?.id <= 0 ||
        !Number.isSafeInteger(answer.invoice?.id)) {
      throw refuse("Reponse de facturation atomique non conforme.");
    }
    outcome = answer.outcome;
  }

  // Toujours relire depuis Odoo pour verifier l'etat final, y compris lors
  // de reprises et de deux appels simultanes au meme dossier.
  const order = await readOrder(odooClient, prepared, intent);
  const invoice = await readInvoice(odooClient, order, prepared);
  return Object.freeze({
    outcome, reference: prepared.reference,
    market: marketKey, cycleKey: prepared.cycleKey,
    orderId: order.id, orderNumber: order.name,
    invoiceId: invoice.id, invoiceNumber: invoice.name,
    invoiceState: invoice.state,
    amountUntaxedCents: prepared.expectedUntaxedCents,
    amountTotalCents: prepared.expectedTotalCents,
    // Facture emise != preuve de paiement ; Stripe ou engagement public
    // doivent etre rapproches par le futur service de reglement.
    paymentStatus: "unverified",
    activatesCommercialRights: false,
    requiresSeparatePaymentEvidence: true,
  });
}

module.exports = {confirmVerifiedInvoiceFromServer, validateIntent,
  validateOrder, validateInvoice};
