"use strict";

// Diagnostic des champs de la preuve Stripe Odoo en LECTURE SEULE.
// Affiche uniquement les cles de schema et les quelques valeurs publiques
// enumerees, jamais les secrets, identifiants bancaires ou tokens.
// Cible unique : facture PUBLICITAIRE deja creee dans le clone neutralise.

const {createReadOnlyClient, CLONE, SCENARIOS} =
    require("./sphot_odoo_payment_evidence_audit");
const PUBLICITAIRE = SCENARIOS.find(s => s.market === "PUBLICITAIRE");
const FIELDS = new Set(["id", "code", "state", "provider_state", "mode",
  "operating_mode", "environment", "status", "is_published", "published",
  "test_mode", "is_test", "is_test_mode", "enabled", "is_enabled",
  "payment_state", "is_active"]);
const SAFE_ENUMS = new Set(["stripe", "test", "test_mode", "testmode",
  "sandbox", "demo", "enabled", "disabled", "live", "production",
  "prod", "active", "inactive", "off", "on"]);
const PRIVATE_FIELD = /password|secret|key|token|credential|private|merchant|account|email|phone|url|webhook|auth|signature/i;
function check(ok, message) {
  if (!ok) throw new Error(message);
}
function publicSchema(provider) {
  check(provider && typeof provider === "object" &&
      !Array.isArray(provider), "Prestataire Odoo invalide");
  const fields = {};
  for (const [k, v] of Object.entries(provider)) {
    if (!FIELDS.has(k)) continue;
    if (k === "id") {
      fields[k] = Number.isSafeInteger(v) && v > 0 ? v : "inconnu";
    } else if (typeof v === "boolean") {
      fields[k] = v;
    } else if (typeof v === "string" &&
        SAFE_ENUMS.has(v.trim().toLowerCase())) {
      fields[k] = v.trim().toLowerCase();
    } else {
      fields[k] = "valeur non affichee";
    }
  }
  // Les champs additionnels ne sont affiches que par leur nom (sans valeur).
  const otherFieldNames = Object.keys(provider).filter(k =>
    !FIELDS.has(k) && !PRIVATE_FIELD.test(k)).slice(0, 30);
  return {fields, otherFieldNames};
}
async function inspectSchema({odooClient} = {}) {
  check(odooClient && typeof odooClient.call === "function",
      "Client Odoo lecture seule requis");
  const orders = await odooClient.call("sale.order", "search_read", {
    domain: [["x_sphot_reference", "=", PUBLICITAIRE.reference]],
    fields: ["id", "invoice_ids", "x_sphot_reference",
      "x_sphot_fingerprint"],
    limit: 2,
  });
  check(Array.isArray(orders) && orders.length === 1 &&
      orders[0].id === PUBLICITAIRE.orderId &&
      orders[0].x_sphot_reference === PUBLICITAIRE.reference &&
      /^[a-f0-9]{64}$/.test(orders[0].x_sphot_fingerprint || "") &&
      Array.isArray(orders[0].invoice_ids) &&
      orders[0].invoice_ids.length === 1 &&
      orders[0].invoice_ids[0] === PUBLICITAIRE.invoiceId,
  "Commande PUBLICITAIRE de test non conforme");
  const fingerprint = orders[0].x_sphot_fingerprint;
  const evidence = await odooClient.call(
      "sphot.advertiser.checkout", "read_stripe_checkout_evidence", {
        sphot_reference: PUBLICITAIRE.reference,
        sphot_fingerprint: fingerprint,
        invoice_id: PUBLICITAIRE.invoiceId,
      });
  check(evidence && typeof evidence === "object" &&
      evidence.contract === "sphot_advertiser_stripe_evidence_v1" &&
      evidence.reference === PUBLICITAIRE.reference &&
      evidence.fingerprint === fingerprint &&
      evidence.invoice_id === PUBLICITAIRE.invoiceId &&
      Array.isArray(evidence.stripe_providers) &&
      Array.isArray(evidence.demo_providers) &&
      Array.isArray(evidence.transactions) &&
      evidence.transactions.length < 20,
  "Preuve de prestataire Odoo invalide");
  return {
    stripe: evidence.stripe_providers.map(publicSchema),
    demo: evidence.demo_providers.map(publicSchema),
    transactionCount: evidence.transactions.length,
  };
}
async function main() {
  check(process.argv.length === 3 && process.argv[2] === "--lecture",
      "Seul --lecture est autorise");
  const r = await inspectSchema({
    odooClient: createReadOnlyClient({
      apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
    }),
  });
  console.log("=== SPHOT : CHAMPS DES PRESTATAIRES ODOO (LECTURE SEULE) ===");
  console.log("Base : " + CLONE);
  for (const name of ["stripe", "demo"]) {
    for (const item of r[name]) {
      console.log(name.toUpperCase() + " : etats publics : " +
        JSON.stringify(item.fields));
      console.log(name.toUpperCase() + " : autres noms de champs : " +
        (item.otherFieldNames.join(", ") || "aucun"));
    }
  }
  console.log("Transactions : " + r.transactionCount);
  console.log("AUCUN PAIEMENT, AUCUNE ECRITURE ODOO/FIRESTORE");
}
if (require.main === module) {
  main().catch(e => {
    console.error("STOP : " +
      String(e?.message || "Controle indisponible").slice(0, 180));
    process.exitCode = 1;
  });
}
module.exports = {publicSchema, inspectSchema};
