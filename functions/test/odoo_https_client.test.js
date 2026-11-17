"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createOdooHttpsClient} = require("../odoo_https_client");

const config = {
  baseUrl: "https://odoo.example.org",
  database: "sphot",
  apiKey: "private-backend-key",
};

test("Transport Odoo: pas d'adresse locale ou HTTP", () => {
  for (const baseUrl of ["http://odoo.example.org",
    "https://localhost", "https://127.0.0.1",
    "https://odoo.local", "https://odoo.example.org/private",
    "https://user:pass@odoo.example.org"]) {
    assert.throws(() => createOdooHttpsClient({...config, baseUrl}));
  }
});

test("Transport Odoo: secret et nom de base requis", () => {
  assert.throws(() => createOdooHttpsClient({...config, apiKey: ""}));
  assert.throws(() => createOdooHttpsClient({
    ...config, database: "other database",
  }));
});

test("Transport Odoo: requête JSON-2 autorisée, identifiant serveur seulement",
    async () => {
      let requests = 0;
      const client = createOdooHttpsClient({
        ...config,
        fetchImpl: async (url, options) => {
          requests++;
          assert.equal(url, "https://odoo.example.org/json/2/sale.order/search_read");
          assert.equal(options.method, "POST");
          assert.equal(options.headers.Authorization, "bearer private-backend-key");
          assert.equal(options.headers["X-Odoo-Database"], "sphot");
          assert.equal(options.redirect, "error");
          assert.deepEqual(JSON.parse(options.body), {domain: []});
          return {ok: true, headers: {get: () => null},
            text: async () => "[]"};
        },
      });
      assert.deepEqual(await client.call("sale.order", "search_read",
          {domain: []}), []);
      assert.equal(requests, 1);
    });

test("Transport Odoo: blocage de tout accès générique au modèle", async () => {
  const client = createOdooHttpsClient({...config,
    fetchImpl: () => {throw new Error("ne doit pas appeler");}});
  await assert.rejects(client.call("res.users", "search_read", {}));
  await assert.rejects(client.call("sale.order", "unlink", {ids: [1]}));
  await assert.rejects(client.call("account.move", "create", {}));
});

test("Transport Odoo: aucune donnée sensible dans les erreurs et aucun retry",
    async () => {
      let requests = 0;
      const client = createOdooHttpsClient({...config,
        fetchImpl: async () => {
          requests++;
          throw new Error("private-backend-key Odoo exception");
        },
      });
      await assert.rejects(
          client.call("sale.order", "search_read", {}),
          (error) => !error.message.includes(config.apiKey),
      );
      assert.equal(requests, 1);
    });
