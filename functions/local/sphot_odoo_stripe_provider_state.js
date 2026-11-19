"use strict";

// SPHOT / Odoo : etat des prestataires pour la facture PUBLICITAIRE TEST.
// Consultation strictement en lecture seule via la methode metier Odoo.
// Aucun acces direct aux secrets, a payment.provider ou a Stripe API.
// Aucun paiement, aucune ecriture Firebase, aucune activation SPHOT.

const {createReadOnlyClient, SCENARIOS, CLONE} =
    require("./sphot_odoo_payment_evidence_audit");
const PUBLICITAIRE = SCENARIOS.find(x => x.market === "PUBLICITAIRE");

function exigence(ok, message) {
  if (!ok) throw new Error(message);
}
function etatPublic(provider) {
  const p = provider && typeof provider === "object" &&
      !Array.isArray(provider) ? provider : {};
  const id = Number.isSafeInteger(p.id) && p.id > 0 ? p.id : null;
  const state = ["disabled", "test", "enabled"].includes(p.state) ?
    p.state : "inconnu";
  const published = typeof p.is_published === "boolean" ?
    p.is_published : null;
  // Ne JAMAIS afficher des champs non listes, potentiellement secrets.
  return Object.freeze({id, state, published});
}
function resultatExamen(evidence, fingerprint) {
  exigence(evidence && typeof evidence === "object" &&
      !Array.isArray(evidence) &&
      evidence.contract === "sphot_advertiser_stripe_evidence_v1" &&
      evidence.reference === PUBLICITAIRE.reference &&
      evidence.fingerprint === fingerprint &&
      evidence.invoice_id === PUBLICITAIRE.invoiceId &&
      Array.isArray(evidence.stripe_providers) &&
      Array.isArray(evidence.demo_providers) &&
      Array.isArray(evidence.transactions) &&
      evidence.transactions.length < 20,
  "Preuve prestataire Odoo non conforme");

  const stripe = evidence.stripe_providers.map(etatPublic);
  const demo = evidence.demo_providers.map(etatPublic);
  // La presence du fournisseur Stripe ne prouve pas son mode TEST.
  // De meme, l'existence d'un fournisseur Demo ne dit pas s'il est publie.
  const bloque = stripe.some(p => p.state === "enabled") ||
      demo.some(p => p.published === true ||
        (p.state === "enabled" && p.published !== false));
  const pret = !bloque && stripe.length === 1 &&
      stripe[0].state === "test" && stripe[0].published === true &&
      demo.every(p => p.published === false) &&
      evidence.transactions.length === 0;

  return Object.freeze({
    stripe, demo, transactions: evidence.transactions.length,
    conclusion: bloque ? "BLOQUE" : pret ?
      "CONFIGURATION TEST COMPATIBLE (sans paiement)" :
      "A VERIFIER : informations insuffisantes ou fournisseur non publie",
  });
}
async function inspecterPrestataires({odooClient} = {}) {
  exigence(odooClient && typeof odooClient.call === "function",
      "Client Odoo en lecture seule indisponible");
  const orders = await odooClient.call("sale.order", "search_read", {
    domain: [["x_sphot_reference", "=", PUBLICITAIRE.reference]],
    fields: ["id", "invoice_ids", "x_sphot_reference",
      "x_sphot_fingerprint"],
    limit: 2,
  });
  exigence(Array.isArray(orders) && orders.length === 1 &&
      orders[0].id === PUBLICITAIRE.orderId &&
      orders[0].x_sphot_reference === PUBLICITAIRE.reference &&
      /^[a-f0-9]{64}$/.test(orders[0].x_sphot_fingerprint || "") &&
      Array.isArray(orders[0].invoice_ids) &&
      orders[0].invoice_ids.length === 1 &&
      orders[0].invoice_ids[0] === PUBLICITAIRE.invoiceId,
  "Commande PUBLICITAIRE TEST non reconnue");
  const fp = orders[0].x_sphot_fingerprint;
  const evidence = await odooClient.call(
      "sphot.advertiser.checkout", "read_stripe_checkout_evidence", {
        sphot_reference: PUBLICITAIRE.reference,
        sphot_fingerprint: fp,
        invoice_id: PUBLICITAIRE.invoiceId,
      });
  return resultatExamen(evidence, fp);
}
async function main() {
  exigence(process.argv.length === 2 ||
      (process.argv.length === 3 && process.argv[2] === "--lecture"),
  "Seul le mode lecture est accepte");
  console.log("=== SPHOT / PRESTATAIRES ODOO (LECTURE SEULE) ===");
  console.log("Base : " + CLONE);
  const result = await inspecterPrestataires({
    odooClient: createReadOnlyClient({
      apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
    }),
  });
  for (const [nom, providers] of [
    ["Stripe", result.stripe], ["Demo", result.demo]]) {
    console.log(nom + " : " + providers.length + " prestataire(s)");
    for (const p of providers) {
      const pub = p.published === null ? "inconnu" :
        p.published ? "oui" : "non";
      console.log("  id=" + (p.id ?? "inconnu") +
        " ; etat=" + p.state + " ; publie=" + pub);
    }
  }
  console.log("Transactions : " + result.transactions);
  console.log("Conclusion : " + result.conclusion);
  console.log("AUCUN PAIEMENT NI ECRITURE REALISE");
}
if (require.main === module) {
  main().catch(error => {
    console.error("STOP : " +
        String(error?.message || "Controle indisponible").slice(0, 180));
    console.error("NE PAS DEMARRER DE PAIEMENT");
    process.exitCode = 1;
  });
}
module.exports = {etatPublic, resultatExamen, inspecterPrestataires};
