"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {etatPublic, resultatExamen, inspecterPrestataires} =
    require("../local/sphot_odoo_stripe_provider_state");

const REF = "SPHOT-PUB-AD7D6478DECA71715DCD2321";
const FP = "a".repeat(64);
function fixture({stripe = [{id: 3, state: "test", is_published: true}],
  demo = [{id: 2, state: "test", is_published: false}],
  transactions = []} = {}) {
  return {
    contract: "sphot_advertiser_stripe_evidence_v1",
    reference: REF, fingerprint: FP, invoice_id: 19,
    stripe_providers: stripe,
    demo_providers: demo,
    transactions,
  };
}
test("Stripe TEST publie, Demo non publie : configuration candidate",
    () => {
      const result = resultatExamen(fixture(), FP);
      assert.equal(result.conclusion,
          "CONFIGURATION TEST COMPATIBLE (sans paiement)");
      assert.equal(result.stripe[0].state, "test");
      assert.equal(result.demo[0].published, false);
    });

test("Demo publie : bloque, meme si Stripe est en TEST", () => {
  const r = resultatExamen(fixture({
    demo: [{id: 2, state: "test", is_published: true}],
  }), FP);
  assert.equal(r.conclusion, "BLOQUE");
});

test("Stripe LIVE/enabled : refuse l'experimentation", () => {
  const r = resultatExamen(fixture({
    stripe: [{id: 3, state: "enabled", is_published: true}],
  }), FP);
  assert.equal(r.conclusion, "BLOQUE");
});

test("etat de publication manquant : aucune fausse certitude", () => {
  const r = resultatExamen(fixture({
    stripe: [{id: 3, state: "test"}],
    demo: [{id: 2, state: "disabled"}],
  }), FP);
  assert.match(r.conclusion, /A VERIFIER/);
});

test("l'audit ne divulgue jamais de cle secrete du prestataire", () => {
  const info = etatPublic({
    id: 99, state: "test", is_published: true,
    stripe_secret_key: "sk_test_ne_jamais_afficher",
    private_key: "cle_confidentielle",
    merchant_account: "compte_confidentiel",
  });
  assert.deepEqual(Object.keys(info), ["id", "state", "published"]);
  assert.doesNotMatch(JSON.stringify(info), /sk_test|confidentiel/);
});

test("une transaction existante n'est pas preuve de reglement", () => {
  const r = resultatExamen(fixture({
    transactions: [{state: "pending"}],
  }), FP);
  assert.match(r.conclusion, /A VERIFIER/);
});

test("contrat et reference Odoo doivent concorder", () => {
  assert.throws(() => resultatExamen({
    ...fixture(), invoice_id: 999,
  }, FP), /non conforme/);
  assert.throws(() => resultatExamen(fixture(), "b".repeat(64)),
      /non conforme/);
});

test("lecture uniquement par la methode metier et sans ecriture",
    async () => {
      const calls = [];
      const client = {async call(model, method, body) {
        calls.push([model, method, body]);
        if (model === "sale.order" && method === "search_read") {
          return [{
            id: 12, invoice_ids: [19], x_sphot_reference: REF,
            x_sphot_fingerprint: FP,
          }];
        }
        assert.equal(model, "sphot.advertiser.checkout");
        assert.equal(method, "read_stripe_checkout_evidence");
        assert.equal(body.invoice_id, 19);
        return fixture();
      }};
      const r = await inspecterPrestataires({odooClient: client});
      assert.equal(r.transactions, 0);
      assert.deepEqual(calls.map(c => c[1]),
          ["search_read", "read_stripe_checkout_evidence"]);
    });
