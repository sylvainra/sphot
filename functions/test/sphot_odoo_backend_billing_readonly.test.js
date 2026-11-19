"use strict";

// Lecture Odoo -> lecteur backend SPHOT avec objets fictifs (aucun reseau).
const test = require("node:test");
const assert = require("node:assert/strict");
const {clientLectureOdoo, verifierRetourBackend, CAS, CLONE} =
    require("../local/sphot_odoo_backend_billing_readonly");

function donnees(scenario) {
  const fingerprint = "a".repeat(64);
  const order = {
    id: scenario.orderId,
    name: "S" + String(scenario.orderId).padStart(5, "0"),
    state: "sale", client_order_ref: scenario.reference,
    x_sphot_reference: scenario.reference,
    x_sphot_fingerprint: fingerprint,
    invoice_ids: [scenario.invoiceId],
  };
  const invoice = {
    id: scenario.invoiceId,
    name: "INV/TEST/" + scenario.invoiceId,
    invoice_origin: order.name,
    state: "posted", move_type: "out_invoice",
    payment_state: "not_paid",
    currency_id: [1, "EUR"],
    amount_total: scenario.totalCents / 100,
    amount_residual: scenario.totalCents / 100,
    x_sphot_reference: scenario.reference,
    x_sphot_fingerprint: fingerprint,
    x_sphot_sale_order_id: [scenario.orderId, order.name],
  };
  return {order, invoice};
}

function fixture(modification = () => {}) {
  const records = CAS.map(donnees);
  modification(records);
  let reads = 0;
  return {
    getReads: () => reads,
    client: {
      async call(model, method, body) {
        reads++;
        if (model === "sale.order") {
          assert.equal(method, "search_read");
          const ref = body.domain[0][2];
          const matches = records.filter(
              r => r.order.x_sphot_reference === ref);
          return matches.map(r => r.order);
        }
        if (model === "account.move") {
          assert.equal(method, "read");
          return records.filter(
              r => body.ids.includes(r.invoice.id)).map(r => r.invoice);
        }
        throw Error("Requete inattendue dans un test hors ligne");
      },
    },
  };
}

test("ADMIN et PUBLICITAIRE : les deux factures sont relues par le backend",
    async () => {
      const f = fixture();
      const resultats = await verifierRetourBackend({odooClient: f.client});
      assert.equal(resultats.length, 2);
      assert.deepEqual(resultats.map(r => r.commande), [11, 12]);
      assert.deepEqual(resultats.map(r => r.facture), [18, 19]);
      assert.deepEqual(resultats.map(r => r.totalTtc),
          ["600.00", "178.80"]);
      assert.ok(resultats.every(r => r.statut === "not_paid"));
      assert.equal(f.getReads(), 6);
    });

test("ne valide jamais une facture payee par erreur", async () => {
  const f = fixture(records => {
    records[0].invoice.payment_state = "paid";
    records[0].invoice.amount_residual = 0;
  });
  await assert.rejects(verifierRetourBackend({odooClient: f.client}),
      /statut de facture/);
});

test("bloque une commande en doublon pour la meme reference", async () => {
  const f = fixture(records => {
    records.push(structuredClone(records[0]));
  });
  await assert.rejects(verifierRetourBackend({odooClient: f.client}),
      /non conformes/);
});

test("bloque une facture qui n'appartient pas a la commande", async () => {
  const f = fixture(records => {
    records[0].invoice.x_sphot_sale_order_id = [999, "autre"];
  });
  await assert.rejects(verifierRetourBackend({odooClient: f.client}),
      /Facture Odoo non conforme|incoh/);
});

test("transport local : seule la copie et deux operations de lecture", async () => {
  const calls = [];
  const client = clientLectureOdoo({
    apiKey: "CLE_TEST_FACTICE_12345",
    fetchImpl: async (url, options) => {
      calls.push({url, options});
      return {ok: true, json: async () => []};
    },
  });
  await client.call("sale.order", "search_read", {domain: []});
  await client.call("account.move", "read", {ids: [18]});
  assert.equal(calls.length, 2);
  for (const call of calls) {
    assert.match(call.url, /^http:\/\/127\.0\.0\.1:8069\/json\/2\//);
    assert.equal(call.options.headers["X-Odoo-Database"], CLONE);
    assert.equal(call.options.method, "POST");
  }
  await assert.rejects(
      client.call("sale.order", "create", {partner_id: 8}),
      /lecture/);
  await assert.rejects(
      client.call("account.move", "write", {ids: [18]}),
      /lecture/);
  await assert.rejects(
      client.call("sphot.admin.checkout",
          "confirm_and_post_one_invoice", {}),
      /lecture/);
  assert.equal(calls.length, 2);
});

test("aucune cle Odoo TEST : aucune connexion", () => {
  assert.throws(() => clientLectureOdoo({apiKey: ""}), /Cle/);
});
