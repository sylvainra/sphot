/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Adaptateur local TEST SPHOT ADMIN -> addon Odoo dédié.
// Aucune route HTTP, aucun accès Firebase, aucune activation ici.
// Le modèle Odoo sphot.admin.checkout doit être installé et vérifié séparément.
const crypto = require("node:crypto");
const {CHECKOUT_TEST_DATABASE} = require("./odoo_secure_checkout_client");

const MODEL = "sphot.admin.checkout";
const DRAFT_METHOD = "create_or_get_draft_order";
const INVOICE_METHOD = "confirm_and_post_one_invoice";
const STRIPE_EVIDENCE_METHOD = "read_stripe_checkout_evidence";
const ORDER_CONTRACT = "sphot_admin_atomic_order_v1";
const INVOICE_CONTRACT = "sphot_admin_atomic_invoice_v1";
const STRIPE_EVIDENCE_CONTRACT = "sphot_admin_stripe_evidence_v1";

const ORDER_FIELDS = ["id", "name", "state", "client_order_ref", "partner_id",
  "currency_id", "amount_untaxed", "amount_tax", "amount_total",
  "order_line", "invoice_ids", "x_sphot_reference", "x_sphot_fingerprint"];
const INVOICE_FIELDS = ["id", "name", "invoice_origin", "partner_id",
  "currency_id", "move_type", "state", "payment_state", "amount_untaxed",
  "amount_tax", "amount_total", "amount_residual", "matched_payment_ids", "x_sphot_reference",
  "x_sphot_fingerprint", "x_sphot_sale_order_id"];

function invalid(message) {
  const error = new Error(message);
  error.code = "ADMIN_ODOO_CONTRACT_ERROR";
  return error;
}

function moneyCents(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw invalid("Montant Odoo ADMIN invalide.");
  }
  const scaled = value * 100;
  const rounded = Math.round(scaled);
  if (!Number.isSafeInteger(rounded) || Math.abs(scaled - rounded) > 0.000001) {
    throw invalid("Précision du montant Odoo ADMIN invalide.");
  }
  return rounded;
}

function relationId(value) {
  if (Number.isSafeInteger(value) && value > 0) return value;
  return Array.isArray(value) && Number.isSafeInteger(value[0]) &&
      value[0] > 0 ? value[0] : null;
}

function assertPrepared(prepared) {
  if (!prepared || prepared.testOnly !== true ||
      !/^SPHOT-ADM-TEST-[A-F0-9]{16}$/.test(prepared.reference) ||
      !/^[a-f0-9]{64}$/.test(prepared.fingerprint) ||
      !prepared.locked ||
      !Number.isSafeInteger(prepared.locked.partnerId) ||
      prepared.locked.partnerId < 1 ||
      !Number.isSafeInteger(prepared.expectedUntaxedCents) ||
      prepared.expectedUntaxedCents < 1 ||
      !Number.isSafeInteger(prepared.expectedTotalCents) ||
      prepared.expectedTotalCents < prepared.expectedUntaxedCents ||
      !Array.isArray(prepared.locked.orderLines) ||
      prepared.locked.orderLines.length < 1 ||
      prepared.locked.orderLines.length > 4 ||
      !prepared.orderValues ||
      prepared.orderValues.client_order_ref !== prepared.reference ||
      prepared.orderValues.partner_id !== prepared.locked.partnerId ||
      !Array.isArray(prepared.orderValues.order_line) ||
      prepared.orderValues.order_line.length !== prepared.locked.orderLines.length ||
      crypto.createHash("sha256").update(JSON.stringify(prepared.locked))
          .digest("hex") !== prepared.fingerprint) {
    throw invalid("Dossier ADMIN serveur non préparé.");
  }
  const allowedOrderKeys = ["partner_id", "client_order_ref", "origin", "order_line"];
  if (Object.keys(prepared.orderValues).some((key) =>
    !allowedOrderKeys.includes(key)) ||
      prepared.orderValues.order_line.some((command, index) => {
        const expected = prepared.locked.orderLines[index];
        const line = command?.[2];
        return !Array.isArray(command) || command.length !== 3 ||
          command[0] !== 0 || command[1] !== 0 ||
          !line || Object.keys(line).some((key) =>
            !["product_id", "product_uom_qty", "price_unit", "discount", "name"].includes(key)) ||
          line.product_id !== expected.productId ||
          line.product_uom_qty !== expected.quantity ||
          line.price_unit !== expected.priceUnit ||
          line.discount !== expected.discount ||
          typeof line.name !== "string" ||
          !line.name.startsWith("SPHOT ADMIN / Tranche ");
      })) {
    throw invalid("Lignes ADMIN envoyées à Odoo altérées.");
  }
}

function verifyOrder(order, prepared) {
  assertPrepared(prepared);
  if (!order || !Number.isSafeInteger(order.id) || order.id < 1 ||
      typeof order.name !== "string" || !order.name ||
      order.x_sphot_reference !== prepared.reference ||
      order.x_sphot_fingerprint !== prepared.fingerprint ||
      order.client_order_ref !== prepared.reference ||
      relationId(order.partner_id) !== prepared.locked.partnerId ||
      !Array.isArray(order.currency_id) || order.currency_id[1] !== "EUR" ||
      !["draft", "sent", "sale"].includes(order.state) ||
      moneyCents(order.amount_untaxed) !== prepared.expectedUntaxedCents ||
      moneyCents(order.amount_total) !== prepared.expectedTotalCents ||
      moneyCents(order.amount_tax) !==
        prepared.expectedTotalCents - prepared.expectedUntaxedCents ||
      !Array.isArray(order.order_line) ||
      order.order_line.length !== prepared.locked.orderLines.length ||
      new Set(order.order_line).size !== order.order_line.length ||
      !Array.isArray(order.invoice_ids) || order.invoice_ids.length > 1) {
    throw invalid("Commande ADMIN Odoo incompatible avec le dossier figé.");
  }
  return order;
}

function verifyLines(lines, order, prepared) {
  if (!Array.isArray(lines) || lines.length !== order.order_line.length ||
      lines.some((line) => !line || !order.order_line.includes(line.id))) {
    throw invalid("Lignes ADMIN Odoo incomplètes.");
  }
  const expected = new Map();
  for (const item of prepared.locked.orderLines) {
    if (expected.has(item.productId)) {
      throw invalid("Produits ADMIN Odoo doublonnés.");
    }
    expected.set(item.productId, item);
  }
  const found = new Set();
  for (const line of lines) {
    const productId = relationId(line.product_id);
    const item = expected.get(productId);
    if (!item || found.has(productId) ||
        line.product_uom_qty !== item.quantity ||
        moneyCents(line.price_unit) !== moneyCents(item.priceUnit) ||
        line.discount !== item.discount) {
      throw invalid("Tranche ADMIN Odoo différente du devis serveur.");
    }
    found.add(productId);
  }
  if (found.size !== expected.size) {
    throw invalid("Tranches ADMIN Odoo manquantes.");
  }
  return lines;
}

function verifyInvoice(invoice, order, prepared) {
  if (!invoice || !Number.isSafeInteger(invoice.id) || invoice.id < 1 ||
      invoice.x_sphot_reference !== prepared.reference ||
      invoice.x_sphot_fingerprint !== prepared.fingerprint ||
      relationId(invoice.x_sphot_sale_order_id) !== order.id ||
      invoice.invoice_origin !== order.name ||
      relationId(invoice.partner_id) !== prepared.locked.partnerId ||
      !Array.isArray(invoice.currency_id) || invoice.currency_id[1] !== "EUR" ||
      invoice.move_type !== "out_invoice" || invoice.state !== "posted" ||
      !["not_paid", "in_payment", "partial", "paid"].includes(invoice.payment_state) ||
      !Array.isArray(invoice.matched_payment_ids) ||
      moneyCents(invoice.amount_untaxed) !== prepared.expectedUntaxedCents ||
      moneyCents(invoice.amount_tax) !==
        prepared.expectedTotalCents - prepared.expectedUntaxedCents ||
      moneyCents(invoice.amount_total) !== prepared.expectedTotalCents ||
      moneyCents(invoice.amount_residual) > prepared.expectedTotalCents ||
      (invoice.payment_state === "paid" &&
        (moneyCents(invoice.amount_residual) !== 0 ||
          invoice.matched_payment_ids.length === 0)) ||
      (invoice.payment_state === "not_paid" &&
        moneyCents(invoice.amount_residual) !== prepared.expectedTotalCents)) {
    throw invalid("Facture ADMIN Odoo incompatible avec le dossier figé.");
  }
  return invoice;
}

function createAdminCheckoutClient({database, odooClient} = {}) {
  if (database !== CHECKOUT_TEST_DATABASE ||
      !odooClient || typeof odooClient.call !== "function") {
    throw invalid("Passerelle ADMIN réservée à Odoo TEST neutralisé.");
  }

  async function status(prepared) {
    assertPrepared(prepared);
    const orders = await odooClient.call("sale.order", "search_read", {
      domain: [["x_sphot_reference", "=", prepared.reference]],
      fields: ORDER_FIELDS, limit: 2,
    });
    if (!Array.isArray(orders) || orders.length > 1) {
      throw invalid("Référence ADMIN dupliquée dans Odoo.");
    }
    if (!orders.length) return null;
    const order = verifyOrder(orders[0], prepared);
    const lines = await odooClient.call("sale.order.line", "read", {
      ids: order.order_line, fields: ["id", "product_id", "product_uom_qty",
        "price_unit", "discount"],
    });
    verifyLines(lines, order, prepared);
    let invoice = null;
    if (order.invoice_ids.length) {
      if (order.state !== "sale") {
        throw invalid("Facture Odoo liée à un devis non confirmé.");
      }
      const invoices = await odooClient.call("account.move", "read", {
        ids: order.invoice_ids, fields: INVOICE_FIELDS,
      });
      if (!Array.isArray(invoices) || invoices.length !== 1 ||
          invoices[0].id !== order.invoice_ids[0]) {
        throw invalid("Facture ADMIN introuvable ou multiple.");
      }
      invoice = verifyInvoice(invoices[0], order, prepared);
    }
    return {order, invoice};
  }

  async function callAtomic(method, body, contract, prepared) {
    const result = await odooClient.call(MODEL, method, body);
    if (!result || !["created", "existing"].includes(result.outcome) ||
        result.contract !== contract ||
        result.reference !== prepared.reference ||
        result.fingerprint !== prepared.fingerprint) {
      throw invalid("Réponse atomique ADMIN Odoo non vérifiée.");
    }
    verifyOrder(result.order, prepared);
    if (method === INVOICE_METHOD) {
      verifyInvoice(result.invoice, result.order, prepared);
    }
    return result;
  }

  async function draft(prepared) {
    const existing = await status(prepared);
    if (existing) return {outcome: "existing", ...existing};
    const result = await callAtomic(DRAFT_METHOD, {
      sphot_reference: prepared.reference,
      sphot_fingerprint: prepared.fingerprint,
      expected_untaxed_cents: prepared.expectedUntaxedCents,
      expected_total_cents: prepared.expectedTotalCents,
      order_values: prepared.orderValues,
    }, ORDER_CONTRACT, prepared);
    return {outcome: result.outcome, ...await status(prepared)};
  }

  async function invoice(prepared) {
    const existing = await status(prepared);
    if (!existing) throw invalid("Commande ADMIN Odoo absente.");
    if (existing.invoice) return {outcome: "existing", ...existing};
    const result = await callAtomic(INVOICE_METHOD, {
      sphot_reference: prepared.reference,
      sphot_fingerprint: prepared.fingerprint,
      sale_order_id: existing.order.id,
      expected_total_cents: prepared.expectedTotalCents,
    }, INVOICE_CONTRACT, prepared);
    return {outcome: result.outcome, ...await status(prepared)};
  }

  async function stripeEvidence(prepared, invoiceRow) {
    assertPrepared(prepared);
    if (!invoiceRow || !Number.isSafeInteger(invoiceRow.id) ||
        invoiceRow.id < 1) {
      throw invalid("Facture ADMIN requise pour contrôler Stripe.");
    }
    const evidence = await odooClient.call(MODEL, STRIPE_EVIDENCE_METHOD, {
      sphot_reference: prepared.reference,
      sphot_fingerprint: prepared.fingerprint,
      invoice_id: invoiceRow.id,
    });
    if (!evidence || evidence.contract !== STRIPE_EVIDENCE_CONTRACT ||
        evidence.reference !== prepared.reference ||
        evidence.fingerprint !== prepared.fingerprint ||
        evidence.invoice_id !== invoiceRow.id ||
        !Array.isArray(evidence.stripe_providers) ||
        !Array.isArray(evidence.demo_providers) ||
        !Array.isArray(evidence.transactions) ||
        evidence.transactions.length >= 20) {
      throw invalid("Preuve Stripe ADMIN Odoo non vérifiée.");
    }
    return evidence;
  }

  async function verifiedStripePayment(prepared) {
    const current = await status(prepared);
    const row = current?.invoice;
    if (!row || row.state !== "posted" || row.payment_state !== "paid" ||
        moneyCents(row.amount_residual) !== 0 ||
        row.matched_payment_ids.length === 0) {
      throw invalid("Stripe ADMIN : facture Odoo non réglée ou non rapprochée.");
    }
    const evidence = await stripeEvidence(prepared, row);
    const providers = evidence.stripe_providers;
    const demo = evidence.demo_providers;
    if (providers.length !== 1 || providers[0].code !== "stripe" ||
        providers[0].is_live !== false ||
        demo.length !== 1 || demo[0].code !== "demo" ||
        demo[0].is_published !== false) {
      throw invalid("Stripe ADMIN : prestataires Odoo TEST incohérents.");
    }
    const transactions = evidence.transactions;
    const confirmed = transactions.filter((tx) => tx.state === "done");
    if (confirmed.length !== 1 || transactions.some((tx) =>
      !tx || !Number.isSafeInteger(tx.id) || tx.id < 1 ||
      typeof tx.reference !== "string" || !tx.reference.trim() ||
      tx.provider_code !== "stripe" ||
      relationId(tx.provider_id) !== providers[0].id ||
      relationId(tx.currency_id) !== relationId(row.currency_id) ||
      !Array.isArray(tx.invoice_ids) || tx.invoice_ids.length !== 1 ||
      tx.invoice_ids[0] !== row.id ||
      moneyCents(tx.amount) !== prepared.expectedTotalCents)) {
      throw invalid("Stripe ADMIN : transaction non conforme à la facture.");
    }
    return {
      provider: "stripe", transactionState: "done",
      invoiceState: row.state, invoicePaymentState: row.payment_state,
      amountResidualCents: 0,
      invoiceTotalCents: prepared.expectedTotalCents,
      orderReference: prepared.reference,
    };
  }

  return {status, draft, invoice, stripeEvidence, verifiedStripePayment};
}

module.exports = {MODEL, DRAFT_METHOD, INVOICE_METHOD,
  STRIPE_EVIDENCE_METHOD, ORDER_CONTRACT, INVOICE_CONTRACT,
  STRIPE_EVIDENCE_CONTRACT, createAdminCheckoutClient};
