/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// SPHOT -> Odoo Community LOCAL ONLY. Never deployed as a Cloud Function.
// The Odoo key is read from the Node process environment, NEVER Flutter.
// Reads the advertiser's existing Firebase dossier under THEIR ID token,
// obtains the published price from the existing SPHOT pricing endpoint,
// and creates an Odoo customer/product/order only after explicit confirmation.
// An additional explicit action can create/post an invoice in the LOCAL test DB.
// A separate confirmed action may record a MANUAL test accounting payment.
// A SECOND isolated order may use Odoo's own Demo portal payment provider.
// No Firestore writes, real bank transactions, emails or campaign activation.

const http = require("node:http");
const {referenceFor} = require("../advertiser_initial_order");
const {buildOdooDraft} = require("../odoo_commercial_bridge");

const HOST = "127.0.0.1";
const PORT = 8767;
const PROJECT_ID = "sphot-ab80b";
const BASE = "https://us-central1-sphot-ab80b.cloudfunctions.net";
const MAX_BODY = 4096;
const LOCAL_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1):[0-9]{2,5}$/;
const API_TIMEOUT_MS = 20000;

function httpError(status, message) {
  const error = new Error(message);
  error.httpStatus = status;
  return error;
}

function string(value) {
  return typeof value === "string" ? value.trim() : "";
}

function map(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function firestoreValue(value) {
  if ("stringValue" in value) return value.stringValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("booleanValue" in value) return value.booleanValue;
  if ("timestampValue" in value) return new Date(value.timestampValue);
  if ("nullValue" in value) return null;
  if ("mapValue" in value) {
    return Object.fromEntries(Object.entries(value.mapValue.fields || {})
        .map(([key, child]) => [key, firestoreValue(child)]));
  }
  if ("arrayValue" in value) {
    return (value.arrayValue.values || []).map(firestoreValue);
  }
  throw httpError(502, "Format Firebase non reconnu.");
}

async function readResponse(response, description) {
  let value;
  try {
    value = await response.json();
  } catch (_) {
    throw httpError(502, description + " : réponse illisible.");
  }
  if (!response.ok) {
    // Do not return upstream tracebacks, bearer tokens, or internal data.
    throw httpError(502, description + " : HTTP " + response.status + ".");
  }
  return value;
}

function makeTimeoutFetch(fetchImpl) {
  return (url, options) => fetchImpl(url, {
    ...options,
    signal: AbortSignal.timeout(API_TIMEOUT_MS),
  });
}

function createOdooClient({fetchImpl = fetch, apiKey, database,
  url = "http://127.0.0.1:8069"}) {
  if (!string(apiKey) || !/^[a-zA-Z0-9_]+$/.test(database || "") ||
      !/^http:\/\/(127\.0\.0\.1|localhost):8069$/.test(url)) {
    throw new Error("Configuration Odoo local incomplète.");
  }
  const send = makeTimeoutFetch(fetchImpl);
  async function call(model, method, body) {
    const response = await send(url + "/json/2/" + model + "/" + method, {
      method: "POST",
      headers: {
        Authorization: "bearer " + apiKey,
        "X-Odoo-Database": database,
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": "SPHOT-local-publicitaire-test",
      },
      body: JSON.stringify(body),
    });
    return readResponse(response, "API Odoo " + model + "/" + method);
  }
  return {call};
}

function readIdentity(data, email) {
  const establishment = map(data.establishment);
  const professional = map(data.professionalProfile);
  const identity = map(data.professionalIdentity);
  const businessName = string(establishment.businessName) ||
      string(data.advertiserName);
  const contactEmail = string(professional.professionalEmail) ||
      string(identity.email) || string(data.email) || email;
  if (!businessName || !contactEmail || !contactEmail.includes("@")) {
    throw httpError(409, "Nom ou email professionnel SPHOT incomplet.");
  }
  return {
    name: businessName,
    email: contactEmail,
    street: string(establishment.address),
    street2: string(establishment.addressComplement),
    zip: string(establishment.postalCode),
    city: string(establishment.city),
    phone: string(establishment.phone) || string(data.phone),
    country: string(establishment.country).toUpperCase(),
  };
}

function assertAdvertiser(data, user, requestId) {
  if (data.status !== "approved" || data.advertisingSpotCompleted !== true ||
      data.diffusionCompleted !== true || data.planningCompleted !== true) {
    throw httpError(409, "Dossier, diffusion ou planification non finalisé dans SPHOT.");
  }
  if (data.firebaseUid && data.firebaseUid !== user.uid) {
    throw httpError(403, "Dossier annonceur non autorisé.");
  }
  if (user.role !== "ANNONCEUR" || user.advertiserRequestId !== requestId) {
    throw httpError(403, "Compte annonceur non autorisé pour ce dossier.");
  }
  const accepted = map(data.acceptedDocuments);
  const legal = map(data.legalAcceptance);
  if (accepted.cgu !== true || accepted.privacy !== true ||
      accepted.rgpd !== true || accepted.advertiserCgv !== true ||
      legal.representativeDeclaration !== true) {
    throw httpError(409, "Validations juridiques SPHOT incomplètes.");
  }
  if (data.campaignActivated === true || data.orderCompleted === true ||
      ["paid", "succeeded"].includes(string(map(data.payment).status))) {
    throw httpError(409, "Une commande finalisée existe déjà pour ce dossier.");
  }
  const order = map(data.order);
  if (data.order && (order.origin !== "sphot_advertiser_initial_v1" ||
      order.reference !== referenceFor(requestId))) {
    throw httpError(409, "Une autre commande SPHOT existe déjà.");
  }
}

function assertExpected(expected, choice, quote) {
  if (!expected || Object.keys(expected).sort().join("|") !== [
    "territory", "offer", "duration", "startDate",
    "pricingReference", "payableExclTaxCents",
  ].sort().join("|")) {
    throw httpError(400, "Récapitulatif de commande incomplet.");
  }
  if (expected.territory !== choice.territory ||
      expected.offer !== choice.offer ||
      expected.duration !== choice.duration ||
      expected.startDate !== choice.startDate ||
      expected.pricingReference !== quote.pricingReference ||
      expected.payableExclTaxCents !== quote.payableExclTaxCents) {
    throw httpError(409, "Le devis affiché diffère du devis SPHOT enregistré.");
  }
}

function savedChoices(data) {
  const territory = string(map(data.advertisingTerritory).level);
  const offer = string(map(data.diffusion).visibilityType);
  const planning = map(data.planning);
  const duration = string(planning.durationLabel);
  const date = planning.campaignStartDate;
  const startDate = date instanceof Date && !Number.isNaN(date.valueOf()) ?
    date.toISOString().slice(0, 10) : "";
  if (!territory || !["map", "premium", "pack"].includes(offer) ||
      !duration || !startDate) {
    throw httpError(409, "Sélections commerciales SPHOT incomplètes.");
  }
  return {territory, offer, duration, startDate};
}

// Never recycle the already paid first invoice for a second checkout.
function demoReferenceFor(requestId) {
  return referenceFor(requestId) + "-DEMO-02";
}

// The first LOCAL sale is never written back to Firestore. Odoo is the only
// durable source for its historical terms: read its actual line rather than
// expecting data.order / quoteOrderCompleted to exist in the SPHOT dossier.
async function demoDraftFromOriginal(odoo, original, demoReference) {
  const rows = await odoo.call("sale.order", "read", {
    ids: [original.id], fields: ["partner_id", "origin", "order_line"],
  });
  if (!Array.isArray(rows) || rows.length !== 1 ||
      !Array.isArray(rows[0].order_line) ||
      rows[0].order_line.length !== 1 ||
      !/^SPHOT FR_ADVERTISER_RADIUS-V[1-9][0-9]*$/.test(rows[0].origin)) {
    throw httpError(409, "Commande SPHOT initiale incompatible avec le test Démo.");
  }
  const partnerId = relationId(rows[0].partner_id);
  const lineId = rows[0].order_line[0];
  if (!Number.isSafeInteger(partnerId) || partnerId < 1 ||
      !Number.isSafeInteger(lineId) || lineId < 1) {
    throw httpError(409, "Client ou ligne de vente Odoo d'origine invalide.");
  }
  const lines = await odoo.call("sale.order.line", "read", {
    ids: [lineId], fields: ["product_id", "product_uom_qty",
      "price_unit", "discount", "name", "tax_ids"],
  });
  if (!Array.isArray(lines) || lines.length !== 1) {
    throw httpError(409, "Ligne historique de vente Odoo introuvable.");
  }
  const line = lines[0];
  const productId = relationId(line.product_id);
  const products = Number.isSafeInteger(productId) && productId > 0 ?
    await odoo.call("product.product", "read", {
      ids: [productId], fields: ["default_code"],
    }) : [];
  const price = Number(line.price_unit);
  const discount = Number(line.discount);
  const taxIds = line.tax_ids;
  const originalUntaxedCents = Math.round(Number(original.amount_untaxed) * 100);
  if (!Array.isArray(products) || products.length !== 1 ||
      products[0].default_code !== "SPHOT-PUB-LOCAL-TEST" ||
      Number(line.product_uom_qty) !== 1 ||
      !Number.isSafeInteger(price) || price <= 0 ||
      !Number.isInteger(discount) || discount < 0 || discount > 90 ||
      typeof line.name !== "string" ||
      !line.name.startsWith("SPHOT PUBLICITAIRE / ") ||
      !line.name.endsWith(" / Tarif " + rows[0].origin.slice(6)) ||
      !Array.isArray(taxIds) ||
      !taxIds.every((id) => Number.isSafeInteger(id) && id > 0) ||
      Math.round(price * (100 - discount)) !== originalUntaxedCents) {
    throw httpError(409, "Tarif ou produit de la première commande Odoo incohérent.");
  }
  return {
    partnerId,
    values: {
      partner_id: partnerId,
      client_order_ref: demoReference,
      origin: rows[0].origin,
      order_line: [[0, 0, {
        product_id: productId,
        product_uom_qty: 1,
        price_unit: price,
        discount,
        name: line.name,
        tax_ids: [[6, 0, taxIds]],
      }]],
    },
  };
}

function verifyDemoReplica(original, duplicate, reference) {
  const result = receipt(duplicate, reference);
  const originalResult = receipt(original, original.client_order_ref);
  if (result.odooUntaxedCents !== originalResult.odooUntaxedCents ||
      result.odooTaxCents !== originalResult.odooTaxCents ||
      result.odooTotalCents !== originalResult.odooTotalCents) {
    throw httpError(409,
        "La deuxième commande ne reprend pas les montants initiaux Odoo.");
  }
  return result;
}

async function findDemoTransactions(odoo, invoice) {
  const rows = await odoo.call("payment.transaction", "search_read", {
    domain: [["invoice_ids", "in", [invoice.id]]],
    fields: ["id", "reference", "state", "provider_code", "amount"],
    order: "id desc", limit: 20,
  });
  if (!Array.isArray(rows) || rows.length === 20) {
    throw httpError(409, "Historique des transactions Démo ambigu.");
  }
  const expectedCents = Math.round(Number(invoice.amount_total) * 100);
  for (const row of rows) {
    if (row.provider_code !== "demo" ||
        Math.abs(Math.round(Number(row.amount) * 100) - expectedCents) > 1) {
      throw httpError(409,
          "Transaction non Démo ou montant inattendu : intervention requise.");
    }
  }
  return rows.map((row) => ({
    id: row.id, reference: row.reference, state: row.state,
    amountCents: Math.round(Number(row.amount) * 100),
    provider: "demo", testOnly: true,
  }));
}

async function demoCheckoutUrl(odoo, invoice) {
  const dueCents = Math.round(Number(invoice.amount_residual) * 100);
  const totalCents = Math.round(Number(invoice.amount_total) * 100);
  if (invoice.state !== "posted" || invoice.payment_state !== "not_paid" ||
      totalCents <= 0 || dueCents !== totalCents ||
      (invoice.matched_payment_ids || []).length !== 0) {
    throw httpError(409,
        "Cette facture ne peut plus ouvrir un nouveau paiement Démo.");
  }
  const providers = await odoo.call("payment.provider", "search_read", {
    domain: [["code", "=", "demo"], ["state", "=", "test"]],
    fields: ["id", "code", "state", "is_published"], limit: 2,
  });
  if (!Array.isArray(providers) || providers.length !== 1 ||
      providers[0].is_published !== true) {
    throw httpError(409, "Prestataire Odoo Démo non publié en mode TEST.");
  }
  const relative = await odoo.call("account.move", "get_portal_url", {
    ids: [invoice.id],
  });
  if (typeof relative !== "string") {
    throw httpError(502, "Lien du portail de facture Odoo invalide.");
  }
  const url = new URL(relative, "http://127.0.0.1:8069");
  if (!(["localhost", "127.0.0.1"].includes(url.hostname) &&
        url.port === "8069" && url.protocol === "http:" &&
        url.pathname === "/my/invoices/" + invoice.id &&
        url.searchParams.has("access_token"))) {
    throw httpError(502, "Le paiement Démo exige un portail Odoo local valide.");
  }
  url.hostname = "127.0.0.1";
  // This is an access link: only return it to the authenticated owner.
  // Never log it or store it in Firestore.
  return url.toString();
}

async function findOrder(odoo, reference) {
  const found = await odoo.call("sale.order", "search_read", {
    domain: [["client_order_ref", "=", reference]],
    fields: ["id", "name", "state", "client_order_ref", "amount_untaxed",
      "amount_tax", "amount_total", "invoice_status"],
    limit: 2,
  });
  if (!Array.isArray(found) || found.length > 1) {
    throw httpError(409, "Référence SPHOT dupliquée ou réponse Odoo invalide.");
  }
  return found[0] || null;
}

async function findInvoice(odoo, order) {
  const orders = await odoo.call("sale.order", "read", {
    ids: [order.id], fields: ["invoice_ids"],
  });
  if (!Array.isArray(orders) || orders.length !== 1 ||
      !Array.isArray(orders[0].invoice_ids)) {
    throw httpError(502, "Factures de la commande Odoo illisibles.");
  }
  const ids = orders[0].invoice_ids;
  if (ids.length > 1) {
    throw httpError(409, "Plusieurs factures sont liées à cette commande : intervention manuelle requise.");
  }
  if (ids.length === 0) return null;
  const invoices = await odoo.call("account.move", "read", {
    ids, fields: ["id", "name", "state", "move_type", "payment_state",
      "amount_untaxed", "amount_tax", "amount_total", "amount_residual",
      "invoice_origin", "matched_payment_ids"],
  });
  if (!Array.isArray(invoices) || invoices.length !== 1 ||
      invoices[0].move_type !== "out_invoice") {
    throw httpError(409, "Document Odoo lié non conforme à une facture client.");
  }
  return invoices[0];
}

function invoiceReceipt(invoice, order) {
  const untaxedCents = Math.round(Number(invoice.amount_untaxed) * 100);
  const totalCents = Math.round(Number(invoice.amount_total) * 100);
  if (!Number.isSafeInteger(untaxedCents) ||
      !Number.isSafeInteger(totalCents) ||
      Math.abs(untaxedCents - Math.round(Number(order.amount_untaxed) * 100)) > 1 ||
      Math.abs(totalCents - Math.round(Number(order.amount_total) * 100)) > 1) {
    throw httpError(409, "Montants de facture différents de la commande Odoo.");
  }
  return {
    odooInvoiceId: invoice.id,
    odooInvoiceName: invoice.name,
    state: invoice.state,
    paymentState: invoice.payment_state,
    amountUntaxedCents: untaxedCents,
    amountTaxCents: Math.round(Number(invoice.amount_tax) * 100),
    amountTotalCents: totalCents,
    amountResidualCents: Math.round(Number(invoice.amount_residual) * 100),
    odooPaymentRecorded: Array.isArray(invoice.matched_payment_ids) &&
        invoice.matched_payment_ids.length > 0,
    paymentInitiated: false,
    campaignActivationAllowed: false,
    testOnly: true,
  };
}

async function confirmInvoice(odoo, order) {
  if (order.state !== "sale") {
    throw httpError(409, "La commande doit être confirmée avant facturation.");
  }
  let invoice = await findInvoice(odoo, order);
  const alreadyExists = invoice !== null;
  if (!invoice) {
    // Use Odoo's native Sales invoice wizard. The resulting invoice remains
    // linked to S00001 and its order line, preserving accounting consistency.
    const wizardId = createdId(await odoo.call("sale.advance.payment.inv",
        "create", {vals_list: [{advance_payment_method: "delivered",
          sale_order_ids: [[6, 0, [order.id]]]}]}));
    await odoo.call("sale.advance.payment.inv", "create_invoices",
        {ids: [wizardId]});
    invoice = await findInvoice(odoo, order);
    if (!invoice) {
      throw httpError(502, "L'assistant Odoo n'a pas créé de facture liée.");
    }
  }
  // Verify the numbers BEFORE posting, which gives the invoice its number.
  invoiceReceipt(invoice, order);
  if (invoice.state === "draft") {
    await odoo.call("account.move", "action_post", {ids: [invoice.id]});
    invoice = await findInvoice(odoo, order);
  }
  if (!invoice || invoice.state !== "posted") {
    throw httpError(502, "Facture Odoo non validée.");
  }
  return {alreadyExists, invoice: invoiceReceipt(invoice, order)};
}

function relationId(value) {
  if (Number.isSafeInteger(value) && value > 0) return value;
  return Array.isArray(value) && Number.isSafeInteger(value[0]) ?
    value[0] : null;
}

async function findManualCashMethod(odoo) {
  // The local test must never select a real banking/payment-provider journal.
  const journals = await odoo.call("account.journal", "search_read", {
    domain: [["type", "=", "cash"]],
    fields: ["id", "name", "type"], limit: 3,
  });
  if (!Array.isArray(journals) || journals.length !== 1) {
    throw httpError(409, "Le test nécessite un seul journal de caisse Odoo (type cash). Aucun journal bancaire ne sera utilisé.");
  }
  const journal = journals[0];
  const methods = await odoo.call("account.payment.method.line", "search_read", {
    domain: [["journal_id", "=", journal.id], ["code", "=", "manual"],
      ["payment_type", "=", "inbound"]],
    fields: ["id", "code", "payment_type", "journal_id"], limit: 2,
  });
  if (!Array.isArray(methods) || methods.length !== 1 ||
      relationId(methods[0].journal_id) !== journal.id ||
      methods[0].code !== "manual" ||
      methods[0].payment_type !== "inbound") {
    throw httpError(409, "Le journal de caisse Odoo n'a pas de méthode d'encaissement manuelle.");
  }
  return {journalId: journal.id, methodId: methods[0].id};
}

async function registerTestPayment(odoo, order) {
  if (order.state !== "sale") {
    throw httpError(409, "Commande Odoo non confirmée.");
  }
  let invoice = await findInvoice(odoo, order);
  if (!invoice || invoice.state !== "posted") {
    throw httpError(409, "Une facture Odoo validée est requise avant tout règlement de test.");
  }
  invoiceReceipt(invoice, order);
  if (["in_payment", "paid"].includes(invoice.payment_state)) {
    return {alreadyExists: true, invoice: invoiceReceipt(invoice, order)};
  }
  const expectedCents = Math.round(Number(invoice.amount_total) * 100);
  const residualCents = Math.round(Number(invoice.amount_residual) * 100);
  if (invoice.payment_state !== "not_paid" || expectedCents <= 0 ||
      residualCents !== expectedCents ||
      (invoice.matched_payment_ids || []).length > 0) {
    throw httpError(409, "État de paiement Odoo déjà modifié : règlement de test bloqué pour éviter un doublon.");
  }
  const {journalId, methodId} = await findManualCashMethod(odoo);
  const lines = await odoo.call("account.move.line", "search_read", {
    domain: [["move_id", "=", invoice.id],
      ["account_type", "=", "asset_receivable"], ["reconciled", "=", false]],
    fields: ["id", "amount_residual", "reconciled"], limit: 3,
  });
  if (!Array.isArray(lines) || lines.length !== 1 ||
      Math.abs(Math.round(Number(lines[0].amount_residual) * 100) -
        residualCents) > 1) {
    throw httpError(409, "Une seule ligne client non réglée est requise pour ce test.");
  }
  const wizardId = createdId(await odoo.call("account.payment.register",
      "create", {vals_list: [{line_ids: [[6, 0, [lines[0].id]]],
        journal_id: journalId, payment_method_line_id: methodId,
        installments_mode: "full", amount: expectedCents / 100}]}));
  const wizard = await odoo.call("account.payment.register", "read", {
    ids: [wizardId], fields: ["amount", "journal_id", "payment_method_line_id",
      "payment_type", "partner_type", "line_ids"],
  });
  if (!Array.isArray(wizard) || wizard.length !== 1 ||
      wizard[0].payment_type !== "inbound" ||
      wizard[0].partner_type !== "customer" ||
      relationId(wizard[0].journal_id) !== journalId ||
      relationId(wizard[0].payment_method_line_id) !== methodId ||
      Math.round(Number(wizard[0].amount) * 100) !== expectedCents ||
      !Array.isArray(wizard[0].line_ids) ||
      wizard[0].line_ids.length !== 1 ||
      wizard[0].line_ids[0] !== lines[0].id) {
    throw httpError(409, "Assistant Odoo non conforme : aucun règlement de test créé.");
  }
  await odoo.call("account.payment.register", "action_create_payments",
      {ids: [wizardId]});
  invoice = await findInvoice(odoo, order);
  if (!invoice || !["in_payment", "paid"].includes(invoice.payment_state) ||
      !Array.isArray(invoice.matched_payment_ids) ||
      invoice.matched_payment_ids.length < 1) {
    throw httpError(409, "Le règlement manuel a été transmis mais Odoo ne confirme pas son état. Ne pas relancer avant vérification.");
  }
  return {alreadyExists: false, invoice: invoiceReceipt(invoice, order)};
}

function receipt(odooOrder, reference, quote) {
  if (!odooOrder || odooOrder.client_order_ref !== reference) {
    throw httpError(502, "Référence de commande Odoo incorrecte.");
  }
  const untaxedCents = Math.round(Number(odooOrder.amount_untaxed) * 100);
  if (!Number.isSafeInteger(untaxedCents) ||
      (quote && Math.abs(untaxedCents - quote.payableExclTaxCents) > 1)) {
    throw httpError(409, "Le total HT Odoo ne correspond pas au devis SPHOT.");
  }
  return {
    reference,
    odooOrderId: odooOrder.id,
    odooOrderName: odooOrder.name,
    odooState: odooOrder.state,
    odooInvoiceStatus: odooOrder.invoice_status,
    odooUntaxedCents: untaxedCents,
    odooTaxCents: Math.round(Number(odooOrder.amount_tax) * 100),
    odooTotalCents: Math.round(Number(odooOrder.amount_total) * 100),
    pricingReference: quote?.pricingReference || null,
    paymentStatus: "not_started",
    campaignActivationAllowed: false,
    testOnly: true,
  };
}

async function findOrCreatePartner(odoo, identity) {
  // This first integration is scoped to the French BLUE SURF SCHOOL test.
  // Never guess the fiscal country for another customer's future invoice.
  if (!["FR", "FRANCE"].includes(identity.country)) {
    throw httpError(409, "Pays de facturation non pris en charge par ce test local.");
  }
  const found = await odoo.call("res.partner", "search_read", {
    domain: [["email", "=", identity.email], ["name", "=", identity.name]],
    fields: ["id"], limit: 2,
  });
  if (!Array.isArray(found) || found.length > 1) {
    throw httpError(409, "Plusieurs clients Odoo correspondent à ce dossier.");
  }
  if (found.length === 1) return found[0].id;
  const values = {
    name: identity.name, email: identity.email, is_company: true,
    street: identity.street, street2: identity.street2, zip: identity.zip,
    city: identity.city, phone: identity.phone,
  };
  const country = await odoo.call("res.country", "search_read", {
    domain: [["code", "=", "FR"]], fields: ["id"], limit: 1,
  });
  if (!Array.isArray(country) || country.length !== 1) {
    throw httpError(409, "Pays France introuvable dans Odoo.");
  }
  values.country_id = country[0].id;
  return createdId(await odoo.call("res.partner", "create",
      {vals_list: [values]}));
}

function createdId(result) {
  const first = Array.isArray(result) ? result[0] : result;
  const id = first && typeof first === "object" ? first.id : first;
  if (!Number.isSafeInteger(id) || id < 1) {
    throw httpError(502, "Identifiant Odoo créé invalide.");
  }
  return id;
}

async function findOrCreateProduct(odoo) {
  const code = "SPHOT-PUB-LOCAL-TEST";
  const found = await odoo.call("product.product", "search_read", {
    domain: [["default_code", "=", code]],
    fields: ["id"], limit: 2,
  });
  if (!Array.isArray(found) || found.length > 1) {
    throw httpError(409, "Produit technique SPHOT Odoo dupliqué.");
  }
  if (found.length === 1) return found[0].id;
  return createdId(await odoo.call("product.product", "create", {
    vals_list: [{name: "SPHOT PUBLICITAIRE - CAMPAGNE TEST",
      default_code: code, type: "service", sale_ok: true,
      purchase_ok: false, list_price: 0}],
  }));
}

function quoteForBridge(quote, choice) {
  if (!quote || quote.previewOnly !== true ||
      quote.market !== "ADVERTISER_RADIUS" ||
      quote.currency !== "EUR" ||
      !Number.isSafeInteger(quote.amountExclTax) ||
      !Number.isSafeInteger(quote.payableExclTaxCents) ||
      !Number.isInteger(quote.discountPercent)) {
    throw httpError(502, "Devis commercial SPHOT invalide.");
  }
  return {...quote, territory: choice.territory,
    offer: choice.offer, duration: choice.duration};
}

function createLocalBridge({fetchImpl = fetch, verifyToken, apiKey,
  database = "sphot_publicitaire_test", odooClient} = {}) {
  if (typeof verifyToken !== "function") {
    throw new Error("Vérification Firebase requise.");
  }
  const send = makeTimeoutFetch(fetchImpl);
  const odoo = odooClient || createOdooClient({fetchImpl, apiKey, database});
  const pending = new Map();

  async function readDossier(token, requestId, user) {
    const url = "https://firestore.googleapis.com/v1/projects/" + PROJECT_ID +
        "/databases/(default)/documents/advertiserRequests/" +
        encodeURIComponent(requestId);
    const response = await send(url, {
      headers: {Authorization: "Bearer " + token},
    });
    if (response.status === 403 || response.status === 404) {
      throw httpError(403, "Dossier SPHOT inaccessible à cet annonceur.");
    }
    const document = await readResponse(response, "Lecture du dossier SPHOT");
    const data = firestoreValue({mapValue: {fields: document.fields || {}}});
    assertAdvertiser(data, user, requestId);
    return data;
  }

  async function getQuote(token, choice) {
    const response = await send(BASE + "/previewPublishedCommercialQuote", {
      method: "POST",
      headers: {Authorization: "Bearer " + token,
        "Content-Type": "application/json"},
      body: JSON.stringify({market: "ADVERTISER_RADIUS",
        territory: choice.territory, offer: choice.offer,
        duration: choice.duration}),
    });
    const value = await readResponse(response, "Devis SPHOT publié");
    if (value.success !== true) {
      throw httpError(409, "Le devis SPHOT publié est indisponible.");
    }
    return quoteForBridge(value.quote, choice);
  }

  async function handle({action, token, requestId, expected}) {
    let user;
    try {
      user = await verifyToken(token);
    } catch (_) {
      throw httpError(401, "Session annonceur invalide.");
    }
    if (!user || typeof user.uid !== "string") {
      throw httpError(401, "Session annonceur invalide.");
    }
    const data = await readDossier(token, requestId, user);
    const reference = referenceFor(requestId);
    if (["demo_status", "demo_confirm", "demo_invoice",
      "demo_checkout"].includes(action)) {
      const demoReference = demoReferenceFor(requestId);
      const found = await findOrder(odoo, demoReference);
      if (action === "demo_status") {
        if (!found) return {ok: true, found: false, testOnly: true};
        const invoice = await findInvoice(odoo, found);
        const transactions = invoice ?
          await findDemoTransactions(odoo, invoice) : [];
        return {ok: true, found: true, testOnly: true,
          order: receipt(found, demoReference),
          invoice: invoice ? invoiceReceipt(invoice, found) : null,
          transactions, campaignActivationAllowed: false};
      }
      if (action === "demo_confirm") {
        const key = demoReference + ":confirm";
        if (pending.has(key)) return pending.get(key);
        const operation = (async () => {
          const original = await findOrder(odoo, reference);
          if (!original || original.state !== "sale") {
            throw httpError(409,
                "La première commande SPHOT doit exister dans Odoo.");
          }
          const originalInvoice = await findInvoice(odoo, original);
          if (!originalInvoice || originalInvoice.state !== "posted" ||
              originalInvoice.payment_state !== "paid" ||
              Number(originalInvoice.amount_residual) !== 0) {
            throw httpError(409,
                "Le premier cycle Odoo doit être terminé avant la Démo.");
          }
          invoiceReceipt(originalInvoice, original);
          const snapshot = await demoDraftFromOriginal(odoo, original,
              demoReference);
          if (found) {
            verifyDemoReplica(original, found, demoReference);
            if (["draft", "sent"].includes(found.state)) {
              await odoo.call("sale.order", "action_confirm",
                  {ids: [found.id]});
            } else if (found.state !== "sale") {
              throw httpError(409,
                  "Deuxième commande existante dans un état incompatible.");
            }
            const reused = await findOrder(odoo, demoReference);
            if (!reused || reused.state !== "sale") {
              throw httpError(502, "Reprise de commande Démo impossible.");
            }
            return {ok: true, alreadyExists: true, testOnly: true,
              order: verifyDemoReplica(original, reused, demoReference)};
          }
          const id = createdId(await odoo.call("sale.order", "create",
              {vals_list: [snapshot.values]}));
          const created = await findOrder(odoo, demoReference);
          if (!created || created.id !== id || created.state !== "draft") {
            throw httpError(409, "Commande Démo créée incohérente.");
          }
          verifyDemoReplica(original, created, demoReference);
          await odoo.call("sale.order", "action_confirm", {ids: [id]});
          const confirmed = await findOrder(odoo, demoReference);
          if (!confirmed || confirmed.state !== "sale") {
            throw httpError(502, "Confirmation de commande Démo échouée.");
          }
          return {ok: true, alreadyExists: false, testOnly: true,
            order: verifyDemoReplica(original, confirmed, demoReference)};
        })();
        pending.set(key, operation);
        try {
          return await operation;
        } finally {
          pending.delete(key);
        }
      }
      if (!found || found.state !== "sale") {
        throw httpError(409, "Confirmer d'abord la deuxième commande Démo.");
      }
      if (action === "demo_invoice") {
        const key = demoReference + ":invoice";
        if (pending.has(key)) return pending.get(key);
        const operation = (async () => {
          const result = await confirmInvoice(odoo, found);
          return {ok: true, order: receipt(found, demoReference),
            testOnly: true, ...result};
        })();
        pending.set(key, operation);
        try {
          return await operation;
        } finally {
          pending.delete(key);
        }
      }
      const invoice = await findInvoice(odoo, found);
      if (!invoice) throw httpError(409, "Facture Démo non créée.");
      const transactions = await findDemoTransactions(odoo, invoice);
      if (transactions.some((tx) =>
        ["done", "pending", "authorized"].includes(tx.state))) {
        throw httpError(409,
            "Transaction Démo déjà en cours ou confirmée. Actualisez le statut.");
      }
      const portalUrl = await demoCheckoutUrl(odoo, invoice);
      return {ok: true, testOnly: true, portalUrl,
        invoice: invoiceReceipt(invoice, found),
        campaignActivationAllowed: false};
    }
    if (action === "status") {
      const found = await findOrder(odoo, reference);
      if (!found) return {ok: true, found: false};
      const invoice = await findInvoice(odoo, found);
      return {ok: true, found: true, order: {
        ...receipt(found, reference),
        paymentStatus: invoice ? invoice.payment_state : "not_started",
        odooInvoiceName: invoice ? invoice.name : null,
      }};
    }
    if (["invoice_status", "invoice", "payment"].includes(action)) {
      const order = await findOrder(odoo, reference);
      if (!order || order.state !== "sale") {
        throw httpError(409, "Confirmez d'abord la commande SPHOT dans Odoo.");
      }
      const orderResult = receipt(order, reference);
      if (action === "invoice_status") {
        const invoice = await findInvoice(odoo, order);
        return {ok: true, order: orderResult,
          invoice: invoice ? invoiceReceipt(invoice, order) : null};
      }
      if (action === "payment") {
        const key = reference + ":payment";
        if (pending.has(key)) return pending.get(key);
        const operation = (async () => {
          const result = await registerTestPayment(odoo, order);
          return {ok: true, order: orderResult, ...result};
        })();
        pending.set(key, operation);
        try {
          return await operation;
        } finally {
          pending.delete(key);
        }
      }
      const key = reference + ":invoice";
      if (pending.has(key)) return pending.get(key);
      const operation = (async () => {
        const result = await confirmInvoice(odoo, order);
        return {ok: true, order: orderResult, ...result};
      })();
      pending.set(key, operation);
      try {
        return await operation;
      } finally {
        pending.delete(key);
      }
    }
    if (action !== "confirm") throw httpError(400, "Action inconnue.");
    if (pending.has(reference)) return pending.get(reference);
    const operation = (async () => {
      const choice = savedChoices(data);
      // An order confirmed before this local test must remain frozen.
      // No new Odoo order is created if Firestore contains another order.
      const stored = map(data.order);
      const quote = stored.origin === "sphot_advertiser_initial_v1" &&
          data.quoteOrderCompleted === true ?
        quoteForBridge({market: "ADVERTISER_RADIUS", previewOnly: true,
          version: stored.publishedVersion,
          pricingReference: stored.pricingReference,
          currency: stored.currency,
          amountExclTax: stored.baseAmountExclTaxCents / 100,
          discountPercent: stored.discountPercent,
          payableExclTaxCents: stored.payableExclTaxCents}, choice) :
        await getQuote(token, choice);
      assertExpected(expected, choice, quote);
      const exists = await findOrder(odoo, reference);
      if (exists && exists.state === "sale") {
        return {ok: true, alreadyExists: true,
          order: receipt(exists, reference, quote)};
      }
      let id;
      if (exists) {
        id = exists.id;
      } else {
        const identity = readIdentity(data, user.email || "");
        const partnerId = await findOrCreatePartner(odoo, identity);
        const productId = await findOrCreateProduct(odoo);
        const draft = buildOdooDraft({quote, partnerId,
          productIds: {advertiser: productId}, sphotReference: reference});
        id = createdId(await odoo.call("sale.order", "create",
            {vals_list: [draft.values]}));
      }
      const before = await findOrder(odoo, reference);
      if (!before || before.id !== id) {
        throw httpError(502, "Commande créée introuvable dans Odoo.");
      }
      receipt(before, reference, quote); // Verify the HT before confirmation.
      if (before.state === "draft" || before.state === "sent") {
        await odoo.call("sale.order", "action_confirm", {ids: [id]});
      }
      const after = await findOrder(odoo, reference);
      if (!after || after.state !== "sale") {
        throw httpError(502, "La commande n'est pas confirmée dans Odoo.");
      }
      return {ok: true, alreadyExists: Boolean(exists),
        order: receipt(after, reference, quote)};
    })();
    pending.set(reference, operation);
    try {
      return await operation;
    } finally {
      pending.delete(reference);
    }
  }

  return {handle};
}

function createServer(bridge) {
  return http.createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && !LOCAL_ORIGIN.test(origin)) {
      res.writeHead(403); res.end(); return;
    }
    if (origin) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      res.setHeader("Vary", "Origin");
    }
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    if (req.method === "OPTIONS") {
      res.writeHead(204); res.end(); return;
    }
    try {
      if (req.method === "GET" && req.url === "/health") {
        res.writeHead(200, {"Content-Type": "application/json"});
        res.end(JSON.stringify({ok: true, mode: "ODOO_COMMUNITY_LOCAL_TEST",
          paymentsEnabled: false, manualTestPaymentEnabled: true,
          nativeOdooDemoCheckoutEnabled: true,
          firebaseWritesEnabled: false}));
        return;
      }
      if (req.method !== "POST" || req.url !== "/order") {
        throw httpError(404, "Route locale introuvable.");
      }
      const header = string(req.headers.authorization);
      if (!header.startsWith("Bearer ")) {
        throw httpError(401, "Session annonceur requise.");
      }
      const buffers = [];
      let length = 0;
      for await (const chunk of req) {
        length += chunk.length;
        if (length > MAX_BODY) throw httpError(413, "Requête trop volumineuse.");
        buffers.push(chunk);
      }
      let body;
      try {
        body = JSON.parse(Buffer.concat(buffers).toString("utf8"));
      } catch (_) {
        throw httpError(400, "JSON invalide.");
      }
      if (!body || typeof body !== "object" || Array.isArray(body) ||
          Object.keys(body).some((key) =>
            !["action", "requestId", "expected"].includes(key)) ||
          !["status", "confirm", "invoice", "invoice_status", "payment",
            "demo_status", "demo_confirm", "demo_invoice",
            "demo_checkout"].includes(body.action) ||
          (body.action !== "confirm" && body.expected !== undefined)) {
        throw httpError(400, "Paramètres de commande inconnus.");
      }
      referenceFor(body.requestId);
      const result = await bridge.handle({action: body.action,
        token: header.slice(7), requestId: body.requestId,
        expected: body.expected});
      res.writeHead(200, {"Content-Type": "application/json; charset=utf-8"});
      res.end(JSON.stringify(result));
    } catch (error) {
      const code = error.httpStatus || 502;
      if (!error.httpStatus) {
        // No token, API key, personal details, or upstream stack trace.
        console.error("Passerelle SPHOT/Odoo :", error.message);
      }
      res.writeHead(code, {"Content-Type": "application/json; charset=utf-8"});
      res.end(JSON.stringify({ok: false,
        error: error.httpStatus ? error.message :
          "Passerelle SPHOT/Odoo locale indisponible."}));
    }
  });
}

if (require.main === module) {
  if (!process.env.SPHOT_ODOO_LOCAL_API_KEY) {
    console.error("Clé Odoo absente. Définissez SPHOT_ODOO_LOCAL_API_KEY dans ce terminal.");
    process.exitCode = 1;
  } else {
    const admin = require("firebase-admin");
    const app = admin.initializeApp({projectId: PROJECT_ID}, "sphot-local-odoo");
    const bridge = createLocalBridge({
      apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
      verifyToken: async (token) => admin.auth(app).verifyIdToken(token),
    });
    createServer(bridge).listen(PORT, HOST, () => console.log(
        "SPHOT -> Odoo LOCAL sur http://" + HOST + ":" + PORT +
        " (paiement manuel et prestataire Démo TEST, aucune écriture Firebase)"));
  }
}

module.exports = {createOdooClient, createLocalBridge, createServer,
  firestoreValue, savedChoices, assertExpected, readIdentity, receipt,
  findOrder, findInvoice, invoiceReceipt, confirmInvoice,
  findManualCashMethod, registerTestPayment,
  findOrCreatePartner, findOrCreateProduct, createdId,
  demoReferenceFor, demoDraftFromOriginal, verifyDemoReplica,
  findDemoTransactions, demoCheckoutUrl};
