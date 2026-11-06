/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Consultation exclusivement : aucune création de commande, facture, paiement,
// mise à jour Firestore ou activation de droits commerciaux.
const {createOdooHttpsClient} = require("./odoo_https_client");
const {resolveOdooCheckoutIdentity} = require("./odoo_checkout_identity");

function refused(status, message) {
  const error = new Error(message);
  error.httpStatus = status;
  return error;
}

function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

function monetaryCents(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw refused(502, "Montant de facture Odoo incohérent.");
  }
  const result = Math.round(value * 100);
  if (!Number.isSafeInteger(result) ||
      Math.abs(value * 100 - result) > 0.000001) {
    throw refused(502, "Précision de facture Odoo incohérente.");
  }
  return result;
}

function relationId(value) {
  if (Number.isSafeInteger(value) && value > 0) return value;
  return Array.isArray(value) && Number.isSafeInteger(value[0]) ?
    value[0] : null;
}

async function linkedBillingRecord(admin, identity) {
  const db = admin.firestore();
  if (identity.market === "ADVERTISER") {
    // Seul l'orchestrateur de paiement serveur pourra déposer ce lien Odoo.
    const linked = identity.dossier.odooBilling || {};
    return linked.ownerUid === identity.uid && linked.market === "ADVERTISER" ?
      linked : null;
  }

  const subscription = await db.collection("subscriptions")
      .doc(identity.requestId).get();
  const reference = clean(subscription.data()?.odooAdminCycleRef);
  if (!reference) return null;
  const cycle = await db.collection("adminOdooCycles").doc(reference).get();
  const linked = cycle.data() || {};
  return cycle.exists && linked.adminUid === identity.uid &&
      linked.market === "ADMIN" && linked.orderReference === reference ?
    linked : null;
}

async function readOdooBillingStatus({admin, odooClient, identity}) {
  const linked = await linkedBillingRecord(admin, identity);
  if (!linked) return {status: "not_linked"};
  const reference = clean(linked.orderReference);
  const fingerprint = clean(linked.orderFingerprint);
  // Aucune commande TEST ou projection incomplète n'est présentée comme une
  // facture commerciale réelle.
  if (linked.testOnly !== false ||
      !/^SPHOT-(ADM|PUB)-[A-Z0-9_-]{8,100}$/.test(reference) ||
      !/^[a-f0-9]{64}$/.test(fingerprint)) {
    return {status: "not_linked"};
  }

  const orders = await odooClient.call("sale.order", "search_read", {
    domain: [["x_sphot_reference", "=", reference]],
    fields: ["id", "name", "state", "client_order_ref",
      "x_sphot_reference", "x_sphot_fingerprint", "invoice_ids"],
    limit: 2,
  });
  if (!Array.isArray(orders) || orders.length > 1) {
    throw refused(502, "Commande Odoo ambiguë.");
  }
  if (orders.length === 0) return {status: "order_pending"};

  const order = orders[0];
  if (!Number.isSafeInteger(order.id) || order.id < 1 ||
      order.client_order_ref !== reference ||
      order.x_sphot_reference !== reference ||
      order.x_sphot_fingerprint !== fingerprint ||
      !Array.isArray(order.invoice_ids) || order.invoice_ids.length > 1 ||
      !["draft", "sent", "sale"].includes(order.state)) {
    throw refused(502, "Commande Odoo non conforme au dossier SPHOT.");
  }
  const base = {
    status: "order_found", orderNumber: clean(order.name),
    orderState: order.state,
  };
  if (order.invoice_ids.length === 0) return base;
  if (order.state !== "sale") {
    throw refused(502, "Facture liée à une commande non confirmée.");
  }
  const invoices = await odooClient.call("account.move", "read", {
    ids: order.invoice_ids,
    fields: ["id", "name", "state", "move_type", "invoice_origin",
      "payment_state", "currency_id", "amount_total", "amount_residual",
      "x_sphot_reference", "x_sphot_fingerprint",
      "x_sphot_sale_order_id"],
  });
  if (!Array.isArray(invoices) || invoices.length !== 1) {
    throw refused(502, "Facture Odoo introuvable ou multiple.");
  }
  const invoice = invoices[0];
  if (invoice.id !== order.invoice_ids[0] ||
      invoice.x_sphot_reference !== reference ||
      invoice.x_sphot_fingerprint !== fingerprint ||
      relationId(invoice.x_sphot_sale_order_id) !== order.id ||
      invoice.invoice_origin !== order.name ||
      invoice.move_type !== "out_invoice" ||
      !["draft", "posted"].includes(invoice.state) ||
      !["not_paid", "in_payment", "partial", "paid"].includes(
          invoice.payment_state) ||
      !Array.isArray(invoice.currency_id) ||
      invoice.currency_id[1] !== "EUR") {
    throw refused(502, "Facture Odoo non conforme à la commande SPHOT.");
  }
  const amountTotalCents = monetaryCents(invoice.amount_total);
  const amountResidualCents = monetaryCents(invoice.amount_residual);
  if (amountResidualCents > amountTotalCents ||
      (invoice.payment_state === "paid" && amountResidualCents !== 0)) {
    throw refused(502, "État de règlement Odoo incohérent.");
  }
  return {
    ...base, status: "invoice_found",
    invoiceNumber: clean(invoice.name),
    invoiceState: invoice.state,
    paymentState: invoice.payment_state,
    currency: "EUR", amountTotalCents, amountResidualCents,
    // Ce statut de lecture ne vaut jamais autorisation d'activer un service.
    activatesCommercialRights: false,
  };
}

function registerOdooBillingStatus({admin, onRequest}) {
  return onRequest({region: "us-central1", cors: ["https://sphot.app"],
    cpu: 1, memory: "256MiB", maxInstances: 5,
    secrets: ["SPHOT_ODOO_API_KEY"]}, async (request, response) => {
    response.set("Cache-Control", "no-store");
    if (request.method !== "POST") {
      response.status(405).json({success: false});
      return;
    }
    try {
      const body = request.body || {};
      if (!body || typeof body !== "object" || Array.isArray(body) ||
          Object.keys(body).sort().join("|") !== "market|requestId") {
        throw refused(400, "Demande de facture invalide.");
      }
      const identity = await resolveOdooCheckoutIdentity({
        admin, authorization: request.get("Authorization"),
        market: body.market, requestId: body.requestId,
      });
      if (!process.env.SPHOT_ODOO_BASE_URL ||
          !process.env.SPHOT_ODOO_DATABASE ||
          !process.env.SPHOT_ODOO_API_KEY) {
        throw refused(503, "Facturation Odoo momentanément indisponible.");
      }
      const odooClient = createOdooHttpsClient({
        baseUrl: process.env.SPHOT_ODOO_BASE_URL,
        database: process.env.SPHOT_ODOO_DATABASE,
        apiKey: process.env.SPHOT_ODOO_API_KEY,
      });
      const status = await readOdooBillingStatus({admin, odooClient, identity});
      response.status(200).json({success: true, ...status});
    } catch (error) {
      const status = error.httpStatus ||
        (error.code === "ODOO_GATEWAY_UNAVAILABLE" ? 503 : 500);
      if (status === 500) {
        console.error("Lecture facturation Odoo indisponible.");
      }
      response.status(status).json({success: false,
        error: status === 401 || status === 403 ? error.message :
          "Facturation momentanément indisponible."});
    }
  });
}

module.exports = {readOdooBillingStatus, registerOdooBillingStatus};
