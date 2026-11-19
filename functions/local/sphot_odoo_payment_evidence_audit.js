"use strict";

// Audit Odoo -> SPHOT des PREUVES DE REGLEMENT, lecture seule.
// Ne cree ni commande, ni facture, ni paiement, ni ecriture Firebase.
// Cible fixe : clone Odoo neutralise ; 2 factures TEST deja creees.
// Controle de compatibilite de la methode Stripe PUBLICITAIRE, sans jamais
// conclure qu'une facture est payee sur la seule presence d'une transaction.

const CLONE = "sphot_checkout_clone_neutral_20261118";
const SCENARIOS = Object.freeze([
  Object.freeze({
    market: "ADMIN", orderId: 11, invoiceId: 18, totalCents: 60000,
    reference: "SPHOT-ADM-0F3EDE8D43580D75C2D66D3C",
  }),
  Object.freeze({
    market: "PUBLICITAIRE", orderId: 12, invoiceId: 19,
    totalCents: 17880,
    reference: "SPHOT-PUB-AD7D6478DECA71715DCD2321",
  }),
]);
const METHODS = Object.freeze({
  "sale.order": "search_read",
  "account.move": "read",
  "sphot.advertiser.checkout": "read_stripe_checkout_evidence",
});

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function cents(value) {
  assert(typeof value === "number" && Number.isFinite(value) &&
    value >= 0 && Number.isSafeInteger(Math.round(value * 100)),
  "Montant Odoo invalide");
  return Math.round(value * 100);
}
function relationId(value) {
  return Array.isArray(value) ? value[0] : value;
}
function createReadOnlyClient({apiKey, fetchImpl = globalThis.fetch} = {}) {
  assert(typeof apiKey === "string" && apiKey.length > 12,
  "Cle API du clone Odoo TEST absente");
  assert(typeof fetchImpl === "function", "Transport indisponible");
  return Object.freeze({
    async call(model, method, body) {
      assert(METHODS[model] === method && body &&
        typeof body === "object" && !Array.isArray(body),
      "Operation non autorisee : lecture seule uniquement");
      const response = await fetchImpl(
          "http://127.0.0.1:8069/json/2/" +
          encodeURIComponent(model) + "/" + method, {
            method: "POST",
            headers: {
              Authorization: "bearer " + apiKey,
              "X-Odoo-Database": CLONE,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(20000),
            redirect: "error",
          });
      assert(response?.ok === true,
      "Lecture Odoo refusee pour " + model + "." + method);
      const result = await response.json();
      assert(result !== null && typeof result === "object" &&
        !Object.hasOwn(result, "error"),
      "Reponse Odoo invalide");
      return result;
    },
  });
}

async function inspectPaymentEvidence({odooClient} = {}) {
  assert(odooClient && typeof odooClient.call === "function",
  "Client Odoo en lecture seule requis");
  const results = [];
  for (const scenario of SCENARIOS) {
    const orders = await odooClient.call("sale.order", "search_read", {
      domain: [["x_sphot_reference", "=", scenario.reference]],
      fields: ["id", "name", "state", "invoice_ids",
        "x_sphot_reference", "x_sphot_fingerprint"],
      limit: 2,
    });
    assert(Array.isArray(orders) && orders.length === 1,
        scenario.market + " : commande unique introuvable");
    const order = orders[0];
    assert(order.id === scenario.orderId && order.state === "sale" &&
      order.x_sphot_reference === scenario.reference &&
      /^[a-f0-9]{64}$/.test(order.x_sphot_fingerprint || "") &&
      Array.isArray(order.invoice_ids) &&
      order.invoice_ids.length === 1 &&
      order.invoice_ids[0] === scenario.invoiceId,
    scenario.market + " : rattachement commande/facture incoherent");

    const invoices = await odooClient.call("account.move", "read", {
      ids: [scenario.invoiceId],
      fields: ["id", "name", "state", "move_type", "partner_id",
        "payment_state", "amount_untaxed", "amount_tax",
        "amount_total", "amount_residual", "currency_id",
        "x_sphot_reference", "x_sphot_fingerprint",
        "x_sphot_sale_order_id"],
    });
    assert(Array.isArray(invoices) && invoices.length === 1,
    scenario.market + " : facture introuvable");
    const inv = invoices[0];
    assert(inv.id === scenario.invoiceId &&
      inv.state === "posted" && inv.move_type === "out_invoice" &&
      inv.x_sphot_reference === scenario.reference &&
      inv.x_sphot_fingerprint === order.x_sphot_fingerprint &&
      relationId(inv.x_sphot_sale_order_id) === scenario.orderId &&
      Array.isArray(inv.currency_id) && inv.currency_id[1] === "EUR" &&
      cents(inv.amount_total) === scenario.totalCents &&
      cents(inv.amount_untaxed) + cents(inv.amount_tax) ===
        scenario.totalCents &&
      inv.payment_state === "not_paid" &&
      cents(inv.amount_residual) === scenario.totalCents,
    scenario.market + " : facture non neutralisee ou montant incoherent");

    const record = {market: scenario.market,
      invoiceId: inv.id, paymentState: inv.payment_state,
      amountTotalCents: scenario.totalCents};
    if (scenario.market === "PUBLICITAIRE") {
      const evidence = await odooClient.call(
          "sphot.advertiser.checkout", "read_stripe_checkout_evidence", {
            sphot_reference: scenario.reference,
            sphot_fingerprint: order.x_sphot_fingerprint,
            invoice_id: scenario.invoiceId,
          });
      assert(evidence && !Array.isArray(evidence) &&
        evidence.contract === "sphot_advertiser_stripe_evidence_v1" &&
        evidence.reference === scenario.reference &&
        evidence.fingerprint === order.x_sphot_fingerprint &&
        evidence.invoice_id === scenario.invoiceId &&
        Array.isArray(evidence.stripe_providers) &&
        Array.isArray(evidence.demo_providers) &&
        Array.isArray(evidence.transactions) &&
        evidence.transactions.length < 20,
      "Contrat de lecture des preuves Stripe incompatible");
      record.stripeProviders = evidence.stripe_providers.length;
      record.demoProviders = evidence.demo_providers.length;
      record.transactions = evidence.transactions.length;
    }
    results.push(record);
  }
  return results;
}

async function main() {
  assert(process.argv.length === 2 ||
    (process.argv.length === 3 && process.argv[2] === "--lecture"),
  "Seul le mode lecture est autorise");
  console.log("=== SPHOT / AUDIT PREUVES DE PAIEMENT ODOO (LECTURE SEULE) ===");
  console.log("Base : " + CLONE);
  const results = await inspectPaymentEvidence({
    odooClient: createReadOnlyClient({
      apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
    }),
  });
  for (const record of results) {
    console.log(record.market + " : facture " + record.invoiceId +
      ", " + (record.amountTotalCents / 100).toFixed(2) +
      " EUR TTC, " + record.paymentState);
    if (record.market === "PUBLICITAIRE") {
      console.log("Stripe : fournisseurs=" + record.stripeProviders +
        ", demo=" + record.demoProviders +
        ", transactions=" + record.transactions);
    }
  }
  console.log("=== AUDIT ODOO ET METHODE STRIPE : OK ===");
  console.log("AUCUN REGLEMENT CERTIFIE ; AUCUN DROIT SPHOT ACTIVE");
}

if (require.main === module) {
  main().catch(error => {
    console.error("STOP : " +
      String(error?.message || "Controle impossible").slice(0, 180));
    console.error("Ne pas relancer automatiquement");
    process.exitCode = 1;
  });
}

module.exports = {createReadOnlyClient, inspectPaymentEvidence,
  CLONE, SCENARIOS};
