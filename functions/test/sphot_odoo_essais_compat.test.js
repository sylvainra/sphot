"use strict";

// Tests locaux Node.js : aucune connexion Odoo, aucune facture, aucun paiement.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");

const programme = path.join(__dirname, "..", "local",
    "sphot_odoo_essais_compat.js");
const temporaire = fs.mkdtempSync(path.join(os.tmpdir(), "sphot-odoo-test-"));
const fixture = path.join(temporaire, "fixture.cjs");

const mock = [
  '"use strict";',
  'const scenario = process.env.SPHOT_MOCK_SCENARIO || "ok";',
  'const noms = ["sphot_admin_checkout", "sphot_advertiser_checkout", "sphot_billing_preview", "sphot_checkout_compat"];',
  'globalThis.fetch = async (url, options) => {',
  '  const parts = url.split("/json/2/")[1].split("/");',
  '  const modele = decodeURIComponent(parts[0]);',
  '  const methode = decodeURIComponent(parts[1]);',
  '  if (!["search_read", "search_count", "read", "preview_billing_context"].includes(methode)) throw Error("ECRITURE INTERDITE");',
  '  const db = options.headers["X-Odoo-Database"];',
  '  const valeurs = JSON.parse(options.body);',
  '  const ok = resultat => ({ok: true, json: async () => resultat});',
  '  if (modele === "ir.module.module") return ok(db === "sphot_publicitaire_checkout_test" ? (scenario === "origine" ? [{name:"sphot_checkout_compat",state:"installed"}] : []) : noms.map(name => ({name,state:"installed"})));',
  '  if (methode === "search_count") return ok(scenario === "live" && modele === "payment.provider" ? 1 : 0);',
  '  if (modele === "ir.cron") return ok([{cron_name:"Auto-vacuum internal data"}]);',
  '  if (modele === "res.partner") return ok(valeurs.ids.map(id => ({id,name:"SPHOT TEST",active:true,is_company:true,ref:id===9?"SPHOT-TEST-ADMIN-SIRET-20261118":"",country_id:[75,"France"],street:"TEST",zip:"00000",city:"TEST",vat:"FR11999999998",l10n_fr_siret:id===9?"99999999800019":false})));',
  '  if (modele === "product.product") return ok(valeurs.ids.map(id => ({id,name:"SPHOT TEST",active:true,type:"service",invoice_policy:"order",taxes_id:[1]})));',
  '  if (methode === "preview_billing_context") {',
  '    const admin = modele === "sphot.admin.checkout";',
  '    const ht = admin ? 50000 : 14900;',
  '    const taxe = admin ? 10000 : 2980;',
  '    return ok({contract:"sphot_odoo_billing_preview_v1",testOnly:true,market:admin?"ADMIN":"ADVERTISER",reference:valeurs.sphot_reference,partnerId:valeurs.order_values.partner_id,buyerActive:true,buyerCompany:true,billingAddressComplete:true,buyerCountry:"FR",currency:"EUR",buyerSiret:"99999999800019",buyerLegalId:"99999999800019",productIds:valeurs.order_values.order_line.map(l=>l[2].product_id),amountUntaxedCents:ht,amountTaxCents:scenario==="taxe"?taxe-1:taxe,amountTotalCents:ht+taxe});',
  '  }',
  '  if (modele === "sale.order" && methode === "search_read") return ok([]);',
  '  throw Error("Appel inattendu : " + modele + "." + methode);',
  '};',
].join("\n");
fs.writeFileSync(fixture, mock, "utf8");
process.on("exit", () =>
  fs.rmSync(temporaire, {recursive: true, force: true}));

function lancer(mode) {
  const env = {...process.env, SPHOT_ODOO_LOCAL_API_KEY: "TEST_MOCK_KEY_123456",
    SPHOT_MOCK_SCENARIO: mode};
  return spawnSync(process.execPath, ["--require", fixture, programme,
    "--preparer"], {env, encoding: "utf8", timeout: 15000});
}

test("preparation ADMIN et PUBLICITAIRE : deux montants, zero ecriture", () => {
  const res = lancer("ok");
  assert.equal(res.status, 0, res.stderr);
  assert.match(res.stdout, /ADMIN : PRET - 500\.00 EUR HT/);
  assert.match(res.stdout, /PUBLICITAIRE : PRET - 149\.00 EUR HT/);
  assert.match(res.stdout, /PREPARATION OK : 2\/2/);
  assert.match(res.stdout, /AUCUNE COMMANDE NI FACTURE CREEE/);
});

test("refus si le module compatibilite est dans la base d'origine", () => {
  const res = lancer("origine");
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /STOP/);
  assert.doesNotMatch(res.stdout, /PREPARATION OK/);
});

test("refus si un paiement LIVE est actif", () => {
  const res = lancer("live");
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /STOP/);
  assert.doesNotMatch(res.stdout, /PREPARATION OK/);
});

test("refus si la TVA Odoo diverge des montants deja valides", () => {
  const res = lancer("taxe");
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /STOP/);
  assert.doesNotMatch(res.stdout, /PREPARATION OK/);
});

test("cle uniquement par variable d'environnement et consentement explicite", () => {
  const source = fs.readFileSync(programme, "utf8");
  assert.match(source, /process\.env\.SPHOT_ODOO_LOCAL_API_KEY/);
  assert.match(source, /FACTURES_TEST/);
  assert.match(source, /ecritureAutorisee/);
  assert.doesNotMatch(source, /https?:\/\/(?!127\.0\.0\.1)/);
});
