"use strict";

// SPHOT / Odoo 20 - Essais ADMIN et PUBLICITAIRE sur clone neutralise.
// Par defaut : --preparer (lecture et simulation fiscale uniquement).
// --executer requiert une autorisation explicite FACTURES_TEST.
// Jamais de paiement, d'email, de modification Firebase ou de droits SPHOT.

const crypto = require("node:crypto");
const {buildOdooDraft} = require("../odoo_commercial_bridge");

const CLONE = "sphot_checkout_clone_neutral_20261118";
const ORIGINE = "sphot_publicitaire_checkout_test";
const MODE = process.argv[2] || "--preparer";
const CLE = process.env.SPHOT_ODOO_LOCAL_API_KEY;
const MODULES = ["sphot_admin_checkout", "sphot_advertiser_checkout",
  "sphot_billing_preview", "sphot_checkout_compat"];
let ecritureAutorisee = false;

function exiger(condition, message) {
  if (!condition) throw new Error(message);
}
function hash(valeur) {
  return crypto.createHash("sha256").update(valeur).digest("hex");
}
function montant(centimes) {
  return (centimes / 100).toFixed(2) + " EUR";
}
function centimes(valeur) {
  exiger(typeof valeur === "number" && Number.isFinite(valeur),
      "Montant Odoo invalide");
  return Math.round(valeur * 100);
}
function identifiantRelation(valeur) {
  return Array.isArray(valeur) ? valeur[0] : valeur;
}
function reference(marche) {
  const prefixe = marche === "ADMIN" ? "ADM" : "PUB";
  return "SPHOT-" + prefixe + "-" +
      hash("SPHOT-COMPAT-ESSAI-20261119-V1-" + marche)
          .slice(0, 24).toUpperCase();
}
async function appel(base, modele, methode, valeurs = {}) {
  exiger(typeof CLE === "string" && CLE.length > 12,
      "Cle API Odoo TEST absente");
  exiger([CLONE, ORIGINE].includes(base), "Base Odoo non autorisee");
  const lecture = ["search_read", "search_count", "read",
    "preview_billing_context"].includes(methode);
  const ecriture = ["create_or_get_draft_order",
    "confirm_and_post_one_invoice"].includes(methode);
  exiger(lecture || (ecriture && ecritureAutorisee && base === CLONE),
      "Appel Odoo interdit dans le mode actuel");
  if (base === ORIGINE) {
    exiger(modele === "ir.module.module" && methode === "search_read",
        "Base d'origine : seul le controle d'installation est autorise");
  }
  const url = "http://127.0.0.1:8069/json/2/" +
      encodeURIComponent(modele) + "/" + encodeURIComponent(methode);
  const reponse = await fetch(url, {
    method: "POST",
    headers: {Authorization: "bearer " + CLE,
      "X-Odoo-Database": base, "Content-Type": "application/json"},
    body: JSON.stringify(valeurs),
    signal: AbortSignal.timeout(120000),
  });
  if (!reponse.ok) {
    // Le corps d'erreur peut contenir des informations confidentielles.
    throw new Error("Odoo " + modele + "." + methode +
        " : HTTP " + reponse.status);
  }
  return reponse.json();
}
const lire = (modele, methode, valeurs) =>
  appel(CLONE, modele, methode, valeurs);
const compter = (modele, domaine) =>
  lire(modele, "search_count", {domain: domaine});

async function controleClone() {
  const modules = await lire("ir.module.module", "search_read", {
    domain: [["name", "in", MODULES]],
    fields: ["name", "state"], limit: 8,
  });
  exiger(MODULES.every(nom => modules.filter(m =>
    m.name === nom && m.state === "installed").length === 1),
  "Module SPHOT requis absent du clone");
  const source = await appel(ORIGINE, "ir.module.module", "search_read", {
    domain: [["name", "=", "sphot_checkout_compat"]],
    fields: ["name", "state"], limit: 2,
  });
  exiger(Array.isArray(source) &&
    !source.some(m => m.state === "installed"),
  "Compatibilite deja installee dans la base d'origine");
  for (const [description, modele, domaine] of [
    ["paiement LIVE", "payment.provider", [["is_live", "=", true]]],
    ["SMTP actif", "ir.mail_server", [["active", "=", true]]],
    ["emails en attente", "mail.mail", [["state", "=", "outgoing"]]],
    ["reception emails", "fetchmail.server", [["active", "=", true]]],
  ]) {
    exiger(await compter(modele, domaine) === 0,
        "Protection clone non satisfaite : " + description);
  }
  const taches = await lire("ir.cron", "search_read", {
    domain: [["active", "=", true]], fields: ["cron_name"], limit: 5,
  });
  exiger(taches.length <= 1 &&
      taches.every(t => /auto.vacuum internal data/i.test(t.cron_name || "")),
  "Tache Odoo inattendue dans le clone");
  console.log("MODULES ET PROTECTIONS DU CLONE : OK");
}

function devis(marche) {
  if (marche === "ADMIN") {
    return {
      market: "ADMIN", version: 1, pricingReference: "FR_ADMIN-V1",
      currency: "EUR", amountExclTax: 500, discountPercent: 0,
      payableExclTaxCents: 50000,
      lines: [
        {count: 1, unitExclTax: 500, amountExclTax: 500},
        {count: 0, unitExclTax: 750, amountExclTax: 0},
        {count: 0, unitExclTax: 900, amountExclTax: 0},
        {count: 0, unitExclTax: 1000, amountExclTax: 0},
      ],
    };
  }
  return {
    market: "ADVERTISER_RADIUS", version: 1,
    pricingReference: "FR_ADVERTISER_RADIUS-V1", currency: "EUR",
    amountExclTax: 149, discountPercent: 0,
    payableExclTaxCents: 14900, territory: "TEST",
    offer: "Carte SPHOT", duration: "1 mois",
  };
}

async function preparer(marche) {
  const admin = marche === "ADMIN";
  const partenaireId = admin ? 9 : 8;
  const produitId = admin ? 2 : 1;
  const modele = admin ?
    "sphot.admin.checkout" : "sphot.advertiser.checkout";
  const ref = reference(marche);
  const partenaires = await lire("res.partner", "read", {
    ids: [partenaireId],
    fields: ["id", "name", "ref", "is_company", "active", "country_id",
      "street", "zip", "city", "vat", "l10n_fr_siret"],
  });
  exiger(partenaireId === partenaires[0]?.id &&
      partenaires.length === 1 && partenaires[0].active &&
      partenaires[0].is_company && partenaires[0].country_id &&
      partenaires[0].street && partenaires[0].zip &&
      partenaires[0].city && (partenaires[0].vat ||
      partenaires[0].l10n_fr_siret),
  "Client TEST incomplet ou inattendu");
  if (admin) {
    exiger(partenaireId === 9 &&
      partenaires[0].ref === "SPHOT-TEST-ADMIN-SIRET-20261118" &&
      partenaires[0].l10n_fr_siret === "99999999800019",
    "Client fictif ADMIN different du test valide");
  } else {
    exiger(/SPHOT|TEST/i.test(partenaires[0].name),
        "Client PUBLICITAIRE non reconnu comme TEST");
  }

  const idsProduits = admin ? [2, 3, 4, 5] : [1];
  const produits = await lire("product.product", "read", {
    ids: idsProduits,
    fields: ["id", "name", "active", "type", "invoice_policy",
      "taxes_id"],
  });
  exiger(produits.length === idsProduits.length &&
    idsProduits.every(id => produits.some(p => p.id === id &&
      p.active && p.type === "service" &&
      p.invoice_policy === "order" &&
      Array.isArray(p.taxes_id) && p.taxes_id.length &&
      /SPHOT/i.test(p.name))),
  "Produits ou taxes TEST non conformes");

  const brouillon = buildOdooDraft({
    quote: devis(marche), partnerId: partenaireId,
    productIds: admin ? {adminTiers: [2, 3, 4, 5]} :
      {advertiser: produitId},
    sphotReference: ref,
  });
  const fiscal = await lire(modele, "preview_billing_context", {
    sphot_reference: ref, order_values: brouillon.values,
  });
  const ht = admin ? 50000 : 14900;
  const taxe = admin ? 10000 : 2980;
  const ttc = ht + taxe;
  exiger(fiscal.contract === "sphot_odoo_billing_preview_v1" &&
      fiscal.testOnly === true &&
      fiscal.market === (admin ? "ADMIN" : "ADVERTISER") &&
      fiscal.reference === ref && fiscal.partnerId === partenaireId &&
      fiscal.buyerActive === true && fiscal.buyerCompany === true &&
      fiscal.billingAddressComplete === true &&
      fiscal.buyerCountry === "FR" &&
      fiscal.currency === "EUR" &&
      fiscal.amountUntaxedCents === ht &&
      fiscal.amountTaxCents === taxe &&
      fiscal.amountTotalCents === ttc &&
      brouillon.expectedUntaxedCents === ht &&
      Array.isArray(fiscal.productIds) &&
      fiscal.productIds.length === 1 &&
      fiscal.productIds[0] === produitId,
  "Precontrole fiscal incoherent (HT/TVA/TTC)");
  if (admin) exiger(fiscal.buyerSiret === "99999999800019" &&
    fiscal.buyerLegalId === fiscal.buyerSiret,
  "Payeur ADMIN et SIRET non rapproches");

  const commandes = await lire("sale.order", "search_read", {
    domain: [["x_sphot_reference", "=", ref]],
    fields: ["id", "state", "invoice_ids"], limit: 2,
  });
  const factures = await compter("account.move", [
    ["x_sphot_reference", "=", ref],
  ]);
  exiger(commandes.length === 0 && factures === 0,
  "Reference deja utilisee : ne pas relancer automatiquement");

  const empreinte = hash(JSON.stringify({
    reference: ref, values: brouillon.values, ht, ttc,
  }));
  console.log(marche + " : PRET - " + montant(ht) + " HT + " +
    montant(taxe) + " TVA = " + montant(ttc) + " TTC");
  console.log(marche + " : reference " + ref +
    " ; aucune commande/facture existante");
  return {marche, modele, ref, empreinte, brouillon, ht, ttc};
}

async function verifierDocuments(s, idCommande, idFacture) {
  const commandes = await lire("sale.order", "search_read", {
    domain: [["x_sphot_reference", "=", s.ref]],
    fields: ["id", "state", "partner_id", "amount_untaxed", "amount_tax",
      "amount_total", "invoice_ids", "x_sphot_fingerprint"], limit: 2,
  });
  const c = commandes[0];
  exiger(commandes.length === 1 && c.id === idCommande &&
      c.x_sphot_fingerprint === s.empreinte &&
      identifiantRelation(c.partner_id) ===
        (s.marche === "ADMIN" ? 9 : 8) &&
      centimes(c.amount_untaxed) === s.ht &&
      centimes(c.amount_total) === s.ttc &&
      centimes(c.amount_tax) === s.ttc - s.ht,
  "Commande Odoo ou montants non conformes");

  if (!idFacture) {
    exiger(c.state === "draft" && c.invoice_ids.length === 0,
    "Commande deja confirmee ou facturee");
    return;
  }
  exiger(c.state === "sale" && c.invoice_ids.length === 1 &&
      c.invoice_ids[0] === idFacture,
  "Lien commande/facture non conforme");
  const factures = await lire("account.move", "search_read", {
    domain: [["x_sphot_reference", "=", s.ref]],
    fields: ["id", "state", "payment_state", "move_type",
      "partner_id", "amount_untaxed", "amount_tax", "amount_total",
      "amount_residual", "x_sphot_sale_order_id", "x_sphot_fingerprint"],
    limit: 2,
  });
  const f = factures[0];
  exiger(factures.length === 1 && f.id === idFacture &&
      f.state === "posted" && f.payment_state === "not_paid" &&
      f.move_type === "out_invoice" &&
      identifiantRelation(f.partner_id) ===
        (s.marche === "ADMIN" ? 9 : 8) &&
      identifiantRelation(f.x_sphot_sale_order_id) === idCommande &&
      f.x_sphot_fingerprint === s.empreinte &&
      centimes(f.amount_untaxed) === s.ht &&
      centimes(f.amount_tax) === s.ttc - s.ht &&
      centimes(f.amount_total) === s.ttc &&
      centimes(f.amount_residual) === s.ttc,
  "Facture Odoo ou montants non conformes");
}

function verifierRetour(retour, type, scenario, statut) {
  const attendu = type === "commande" ?
    (scenario.marche === "ADMIN" ? "sphot_admin_atomic_order_v1" :
      "sphot_advertiser_atomic_order_v1") :
    (scenario.marche === "ADMIN" ? "sphot_admin_atomic_invoice_v1" :
      "sphot_advertiser_atomic_invoice_v1");
  exiger(retour && retour.contract === attendu &&
    retour.reference === scenario.ref &&
    retour.fingerprint === scenario.empreinte &&
    retour.outcome === statut,
  "Contrat Odoo " + type + " ou etat " + statut + " incorrect");
  const id = type === "commande" ?
    retour.order?.id : retour.invoice?.id;
  exiger(Number.isSafeInteger(id) && id > 0,
  "Identifiant Odoo " + type + " absent");
  return id;
}
async function executer(s) {
  const donneesCommande = {
    sphot_reference: s.ref,
    sphot_fingerprint: s.empreinte,
    expected_untaxed_cents: s.ht,
    expected_total_cents: s.ttc,
    order_values: s.brouillon.values,
  };
  const creation = await lire(s.modele,
      "create_or_get_draft_order", donneesCommande);
  const idCommande = verifierRetour(creation, "commande", s, "created");
  await verifierDocuments(s, idCommande, null);
  const reprise = await lire(s.modele,
      "create_or_get_draft_order", donneesCommande);
  exiger(verifierRetour(reprise, "commande", s, "existing") === idCommande,
  "Commande en doublon");
  const donneesFacture = {
    sphot_reference: s.ref, sphot_fingerprint: s.empreinte,
    sale_order_id: idCommande, expected_total_cents: s.ttc,
  };
  const facturation = await lire(s.modele,
      "confirm_and_post_one_invoice", donneesFacture);
  const idFacture = verifierRetour(facturation, "facture", s, "created");
  await verifierDocuments(s, idCommande, idFacture);
  const repriseFacture = await lire(s.modele,
      "confirm_and_post_one_invoice", donneesFacture);
  exiger(verifierRetour(repriseFacture, "facture", s, "existing") === idFacture,
  "Facture en doublon");
  const repriseApresFacture = await lire(s.modele,
      "create_or_get_draft_order", donneesCommande);
  exiger(verifierRetour(repriseApresFacture, "commande", s, "existing") ===
    idCommande, "Commande facturee non idempotente");
  await verifierDocuments(s, idCommande, idFacture);
  console.log(s.marche + " : OK - commande " + idCommande +
      ", facture " + idFacture + ", aucun doublon, impayee");
}
async function autorisation() {
  const rl = require("node:readline/promises").createInterface({
    input: process.stdin, output: process.stdout,
  });
  try {
    const confirmation = await rl.question(
        "Pour creer 2 commandes et 2 factures TEST, taper FACTURES_TEST : ");
    exiger(confirmation.trim() === "FACTURES_TEST",
        "Creation non autorisee");
    ecritureAutorisee = true;
  } finally {
    rl.close();
  }
}
async function main() {
  exiger(["--preparer", "--executer"].includes(MODE),
      "Mode d'execution inconnu");
  console.log("=== SPHOT ODOO / DEUX ESSAIS COMMERCIAUX ===");
  console.log("Mode : " + (MODE === "--preparer" ?
    "LECTURE SEULE" : "EXECUTION TEST"));
  console.log("Base d'ecriture possible : " + CLONE);
  await controleClone();
  const scenarios = [];
  for (const marche of ["ADMIN", "PUBLICITAIRE"]) {
    scenarios.push(await preparer(marche));
  }
  if (MODE === "--preparer") {
    console.log("=== PREPARATION OK : 2/2 ===");
    console.log("AUCUNE COMMANDE NI FACTURE CREEE");
    return;
  }
  await autorisation();
  for (const s of scenarios) await executer(s);
  console.log("=== 2/2 ESSAIS REUSSIS ; AUCUN PAIEMENT NI DROIT SPHOT ===");
}
main().catch(err => {
  const texte = String(err?.message || "Erreur inconnue");
  const masque = /bearer|secret|password|api.?key|token|@|https?:/i
      .test(texte);
  console.error("STOP : " + (masque ?
    "Erreur detaillee masquee" : texte.slice(0, 240)));
  console.error("NE PAS RELANCER AUTOMATIQUEMENT");
  process.exitCode = 1;
});
