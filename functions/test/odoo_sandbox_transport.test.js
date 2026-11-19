"use strict";

// Tests hors ligne du raccordement Odoo TEST HTTPS.
// Aucune connexion reseau, aucun Firestore reel, aucun paiement, aucun deploy.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createOdooSandboxGateway, CLONE} =
    require("../odoo_sandbox_transport");

const base = Object.freeze({
  SPHOT_ENABLE_ODOO_CHECKOUT_SANDBOX: "true",
  SPHOT_ODOO_DATABASE: CLONE,
  SPHOT_ODOO_BASE_URL: "https://odoo-test.example.org",
  SPHOT_ODOO_API_KEY: "key-mock-only-not-real",
});

test("ecriture desactivee par defaut", () => {
  assert.throws(() => createOdooSandboxGateway({environment: {}}),
      /desactivee/);
});

test("base Odoo d'origine et autres bases interdites", () => {
  for (const database of ["sphot_publicitaire_checkout_test",
    "production", "", "sphot"]) {
    assert.throws(() => createOdooSandboxGateway({
      environment: {...base, SPHOT_ODOO_DATABASE: database},
    }), /neutralisee/);
  }
});

test("secret Odoo serveur absent refuse", () => {
  assert.throws(() => createOdooSandboxGateway({
    environment: {...base, SPHOT_ODOO_API_KEY: ""},
  }), /Secret/);
});

test("aucun acces HTTP/localhost/IP autorise en liaison serveur", () => {
  for (const url of ["http://127.0.0.1:8069",
    "https://127.0.0.1:8069", "https://localhost",
    "http://odoo-test.example.org", "https://user:secret@odoo-test.example.org"]) {
    assert.throws(() => createOdooSandboxGateway({
      environment: {...base, SPHOT_ODOO_BASE_URL: url},
    }));
  }
});

test("aucun appel reseau a la construction ; operation interne seulement",
    async () => {
      let networkCalls = 0;
      const gateway = createOdooSandboxGateway({
        environment: base,
        fetchImpl: async () => {
          networkCalls++;
          throw new Error("NE DOIT PAS ETRE APPELE");
        },
      });
      assert.deepEqual(Object.keys(gateway), ["createDraft"]);
      assert.equal(networkCalls, 0);
      assert.equal(Object.isFrozen(gateway), true);
      await assert.rejects(gateway.createDraft({}), /Dependances/);
      assert.equal(networkCalls, 0);
    });

test("absence d'export Firebase : aucune fonction publique ajoutee", () => {
  const index = fs.readFileSync(path.join(__dirname, "..", "index.js"),
      "utf8");
  assert.doesNotMatch(index, /odoo_sandbox_transport/);
});

test("aucun nom de base d'origine dans le client Odoo TEST", () => {
  const source = fs.readFileSync(path.join(__dirname, "..",
      "odoo_sandbox_transport.js"), "utf8");
  assert.match(source, /SPHOT_ODOO_DATABASE/);
  assert.match(source, /SPHOT_ENABLE_ODOO_CHECKOUT_SANDBOX/);
  assert.match(source, /createVerifiedOdooDraftFromServer/);
  assert.doesNotMatch(source, /sphot_publicitaire_checkout_test/);
});
