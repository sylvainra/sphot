"use strict";

// Diagnostic du schema Stripe : pas de secret ni de requete reelle.
const test = require("node:test");
const assert = require("node:assert/strict");
const {publicSchema, inspectSchema} =
    require("../local/sphot_odoo_stripe_mode_schema");
const REF = "SPHOT-PUB-AD7D6478DECA71715DCD2321";
const FINGERPRINT = "b".repeat(64);
function providerData() {
  return {
    id: 21, code: "stripe", mode: "test", is_published: true,
    stripe_secret_key: "sk_test_DO_NOT_DISPLAY",
    api_token: "TOKEN_TO_HIDE", webhook_secret: "WH_SECRET_TO_HIDE",
    provider_state: "test", something_else: "private note",
  };
}
function evidence() {
  return {
    contract: "sphot_advertiser_stripe_evidence_v1",
    reference: REF, fingerprint: FINGERPRINT, invoice_id: 19,
    stripe_providers: [providerData()],
    demo_providers: [{id: 6, state: "test",
      is_published: false}],
    transactions: [],
  };
}
test("mode Stripe TEST est affiche uniquement comme enum public", () => {
  const info = publicSchema(providerData());
  assert.equal(info.fields.id, 21);
  assert.equal(info.fields.code, "stripe");
  assert.equal(info.fields.mode, "test");
  assert.equal(info.fields.is_published, true);
  assert.equal(info.fields.provider_state, "test");
});
test("les valeurs secretes et leurs noms sensibles restent exclus",
    () => {
      const info = publicSchema(providerData());
      const shown = JSON.stringify(info);
      assert.doesNotMatch(shown, /sk_test_DO_NOT_DISPLAY|TOKEN_TO_HIDE/);
      assert.doesNotMatch(shown, /WH_SECRET_TO_HIDE|secret_key|api_token|webhook_secret/);
      assert.ok(info.otherFieldNames.includes("something_else"));
      assert.doesNotMatch(shown, /private note/);
    });
test("une valeur de mode libre ne doit jamais etre affichee", () => {
  const info = publicSchema({
    id: 21, mode: "secret-mode-unknown-secret",
  });
  assert.equal(info.fields.mode, "valeur non affichee");
  assert.doesNotMatch(JSON.stringify(info), /secret-mode/);
});
test("lecture utilise seulement la commande et la methode evidence", async () => {
  const calls = [];
  const client = {
    async call(model, method, body) {
      calls.push([model, method, body]);
      if (model === "sale.order") {
        assert.equal(method, "search_read");
        return [{
          id: 12, invoice_ids: [19],
          x_sphot_reference: REF,
          x_sphot_fingerprint: FINGERPRINT,
        }];
      }
      assert.equal(model, "sphot.advertiser.checkout");
      assert.equal(method, "read_stripe_checkout_evidence");
      assert.equal(body.invoice_id, 19);
      return evidence();
    },
  };
  const r = await inspectSchema({odooClient: client});
  assert.equal(r.stripe.length, 1);
  assert.equal(r.demo.length, 1);
  assert.equal(r.transactionCount, 0);
  assert.deepEqual(calls.map(c => c[1]), [
    "search_read", "read_stripe_checkout_evidence"]);
});
test("preuve non conforme : refuse sans donner de conclusion", async () => {
  const client = {async call(model) {
    return model === "sale.order" ? [{
      id: 12, invoice_ids: [19],
      x_sphot_reference: REF,
      x_sphot_fingerprint: FINGERPRINT,
    }] : {...evidence(), invoice_id: 999};
  }};
  await assert.rejects(inspectSchema({odooClient: client}),
      /Preuve de prestataire/);
});
