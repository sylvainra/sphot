"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {assertPrepared, createOrGetOdooDraft} = require("../odoo_order_draft");

function fixture(market = "ADMIN") {
  const admin = market === "ADMIN";
  const reference = admin ? "SPHOT-ADM-2026-ABCDEF012345" :
    "SPHOT-PUB-PROD-ABCDEF012345";
  const tariff = admin ? "FR_ADMIN-V4" : "FR_ADVERTISER_RADIUS-V3";
  const lines = admin ? [
    [0, 0, {name: `SPHOT ADMIN / Tranche 1 / Tarif ${tariff}`,
      product_id: 11, product_uom_qty: 2, price_unit: 400, discount: 10}],
    [0, 0, {name: `SPHOT ADMIN / Tranche 2 / Tarif ${tariff}`,
      product_id: 12, product_uom_qty: 1, price_unit: 200, discount: 10}],
  ] : [[0, 0, {
    name: `SPHOT PUBLICITAIRE / radius_5km / map / 1 mois / Tarif ${tariff}`,
    product_id: 21, product_uom_qty: 1, price_unit: 149,
    discount: 0,
  }]];
  const untaxed = admin ? 90000 : 14900;
  return {market, testOnly: false, verified: true,
    source: "SPHOT_SERVER_VERIFIED_CHECKOUT_V1",
    reference, fingerprint: "a".repeat(64),
    expectedUntaxedCents: untaxed,
    expectedTotalCents: Math.round(untaxed * 1.2),
    orderValues: {partner_id: 99, client_order_ref: reference,
      origin: `SPHOT ${tariff}`, order_line: lines}};
}
function gateway(prepared, outcome = "created") {
  const rows = prepared.orderValues.order_line;
  return {contract: prepared.market === "ADMIN" ?
    "sphot_admin_atomic_order_v1" : "sphot_advertiser_atomic_order_v1",
  outcome, reference: prepared.reference, fingerprint: prepared.fingerprint,
  order: {id: 12, name: "S00012", client_order_ref: prepared.reference,
    x_sphot_reference: prepared.reference,
    x_sphot_fingerprint: prepared.fingerprint,
    partner_id: [99, "Professionnel"], currency_id: [1, "EUR"],
    state: "draft", order_line: rows.map((_, i) => i+30), invoice_ids: [],
    amount_untaxed: prepared.expectedUntaxedCents/100,
    amount_tax: (prepared.expectedTotalCents-prepared.expectedUntaxedCents)/100,
    amount_total: prepared.expectedTotalCents/100}};
}

test("ADMIN : commande brouillon construite avec le contrat atomique existant", async () => {
  const p = fixture(); let called = 0;
  const r = await createOrGetOdooDraft({market: "ADMIN", prepared: p,
    odooClient: {call: async (model, method, args) => {
      called++; assert.equal(model, "sphot.admin.checkout");
      assert.equal(method, "create_or_get_draft_order");
      assert.equal(args.sphot_reference, p.reference);
      assert.equal(args.expected_total_cents, 108000);
      return gateway(p);
    }}});
  assert.equal(called, 1);
  assert.equal(r.orderNumber, "S00012");
  assert.equal(r.activatesCommercialRights, false);
  assert.equal(r.paymentStatus, "unverified");
});

test("PUBLICITAIRE : méthode existante réutilisée sans Stripe", async () => {
  const p = fixture("ADVERTISER");
  const r = await createOrGetOdooDraft({market: "ADVERTISER", prepared: p,
    odooClient: {call: async (model, method) => {
      assert.equal(model, "sphot.advertiser.checkout");
      assert.equal(method, "create_or_get_draft_order");
      return gateway(p);
    }}});
  assert.equal(r.amountTotalCents, 17880);
});

test("Deux appels identiques rendent le même numéro : Odoo est responsable de l'unicité", async () => {
  const p = fixture();let calls = 0;
  const client = {call: async () => gateway(p, ++calls === 1 ? "created" : "existing")};
  const first = await createOrGetOdooDraft({market: "ADMIN", prepared: p, odooClient: client});
  const second = await createOrGetOdooDraft({market: "ADMIN", prepared: p, odooClient: client});
  assert.equal(first.orderNumber, second.orderNumber);
  assert.equal(second.outcome, "existing");
  assert.equal(calls, 2);
});

test("Sans préparation serveur et avec commande TEST : aucun appel Odoo", async () => {
  const p = fixture();p.testOnly = true;
  let calls = 0;
  await assert.rejects(createOrGetOdooDraft({market: "ADMIN",prepared:p,
    odooClient:{call:async()=>{calls++;}}}), /Devis commercial/);
  p.testOnly = false;p.reference="SPHOT-ADM-TEST-ABCDEF012345";
  await assert.rejects(createOrGetOdooDraft({market: "ADMIN",prepared:p,
    odooClient:{call:async()=>{calls++;}}}), /Devis commercial/);
  assert.equal(calls,0);
});

test("Une préparation avec prix, remise ou produit altéré est rejetée", () => {
  const checks = [
    p=>{p.expectedUntaxedCents += 1;},
    p=>{p.orderValues.order_line[0][2].discount=60;},
    p=>{p.orderValues.order_line[1][2].product_id=11;},
    p=>{p.orderValues.order_line[0][2].price_unit=-2;},
    p=>{p.orderValues.partner_id=0;},
    p=>{p.orderValues.order_line[0][2].name="Injection";},
    p=>{p.orderValues.origin="SPHOT TEST";},
    p=>{p.orderValues.admin=true;},
  ];
  for(const mutate of checks){const p=fixture();mutate(p);
    assert.throws(()=>assertPrepared("ADMIN",p));}
});

test("Refuse un mauvais marché, un mauvais acteur et l'absence de passerelle", async () => {
  const p=fixture();
  await assert.rejects(createOrGetOdooDraft({market:"ADVERTISER",prepared:p,
    odooClient:{call:async()=>{throw new Error("Unreachable");}}}));
  await assert.rejects(createOrGetOdooDraft({market:"ADMIN",prepared:p}),
      /Passerelle HTTPS/);
});

test("Une réponse Odoo modifiée ou un total TTC différent sont bloqués", async () => {
  for(const mutate of [
    r=>{r.reference="autre";},
    r=>{r.contract="inconnu";},
    r=>{r.order.amount_total+=1;},
    r=>{r.order.x_sphot_fingerprint="b".repeat(64);},
    r=>{r.order.partner_id=[42,"Autre"];},
    r=>{r.order.currency_id=[2,"USD"];},
    r=>{r.order.invoice_ids=[88];},
  ]) {const p=fixture();const r=gateway(p);mutate(r);
    await assert.rejects(createOrGetOdooDraft({market:"ADMIN",prepared:p,
      odooClient:{call:async()=>r}}));}
});

test("Une réponse existante peut être confirmée mais ne confère aucun droit", async () => {
  const p=fixture();const r=gateway(p,"existing");
  r.order.state="sale";r.order.invoice_ids=[33];
  const out=await createOrGetOdooDraft({market:"ADMIN",prepared:p,
    odooClient:{call:async()=>r}});
  assert.equal(out.orderState,"sale");
  assert.equal(out.activatesCommercialRights,false);
});
