"use strict";

// Test 100 % hors ligne : aucun appel reel Odoo, Stripe ou Firebase.
const test = require("node:test");
const assert = require("node:assert/strict");
const {CLONE, analyseBaseUrl, localReadClient, verifierRetourStripe} =
    require("../local/sphot_odoo_stripe_callback_preflight");

test("localhost HTTP ne valide jamais un retour Stripe", () => {
  const r = analyseBaseUrl("http://localhost:8069");
  assert.equal(r.status, "BLOQUE");
});
test("loopback HTTPS ne valide pas non plus le webhook", () => {
  for (const url of ["https://127.0.0.1:8069",
    "https://localhost:8069", "https://[::1]:8069"]) {
    assert.equal(analyseBaseUrl(url).status, "BLOQUE");
  }
});
test("adresses de reseau prive et HTTP distant bloquees", () => {
  for (const url of ["http://odoo-test.example.org",
    "https://192.168.1.100:8069", "https://10.10.0.1",
    "https://172.16.4.2", "https://odoo.local"]) {
    assert.equal(analyseBaseUrl(url).status, "BLOQUE");
  }
});
test("aucune redirection vers SPHOT production", () => {
  for (const url of ["https://sphot.app",
    "https://admin.sphot.app"]) {
    assert.equal(analyseBaseUrl(url).status, "BLOQUE");
  }
});
test("URL HTTPS externe n'est qu'un candidat, jamais un feu vert", () => {
  const r = analyseBaseUrl("https://odoo-test.example.org");
  assert.equal(r.status, "A_VERIFIER");
  assert.match(r.reason, /webhook/);
});
test("URL malformee et identifiants dans URL refuses", () => {
  for (const url of [null, "", "not a URL", "ftp://odoo.test",
    "https://user:pass@odoo-test.example.org",
    "https://odoo-test.example.org/?secret=VALUE",
    "https://odoo-test.example.org/#secret"]) {
    assert.equal(analyseBaseUrl(url).status, "BLOQUE");
  }
});
test("aucune cle API Odoo : aucun acces", () => {
  assert.throws(() => localReadClient({apiKey: ""}), /Cle API/);
});
test("un seul appel local en lecture de web.base.url", async () => {
  const calls = [];
  const client = localReadClient({
    apiKey: "CLE_FACTICE_TEST_12345",
    fetchImpl: async (url, options) => {
      calls.push({url, options});
      return {ok: true, json: async () => "http://localhost:8069"};
    },
  });
  const result = await verifierRetourStripe({client});
  assert.equal(result.status, "BLOQUE");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url,
      "http://127.0.0.1:8069/json/2/ir.config_parameter/get_param");
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].options.headers["X-Odoo-Database"], CLONE);
  assert.equal(calls[0].options.redirect, "error");
  assert.deepEqual(JSON.parse(calls[0].options.body),
      {key: "web.base.url"});
});
test("erreur Odoo n'accorde aucun feu vert", async () => {
  const client = localReadClient({
    apiKey: "CLE_FACTICE_TEST_12345",
    fetchImpl: async () => ({ok: false, status: 403}),
  });
  await assert.rejects(verifierRetourStripe({client}), /refusee/);
});
test("aucun client de lecture : aucun precontrole", async () => {
  await assert.rejects(verifierRetourStripe({}), /manquant/);
});
