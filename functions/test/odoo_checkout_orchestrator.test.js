"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createOrResumeVerifiedCheckout} =
  require("../odoo_checkout_orchestrator");

const UID = "person_123456789";
const ADVERT_ID = "advert_987654321";

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
    product_id: 21, product_uom_qty: 1, price_unit: 149, discount: 0,
  }]];
  const untaxed = admin ? 90000 : 14900;
  return {
    market, ownerUid: UID, requestId: admin ? UID : ADVERT_ID,
    cycleKey: "INITIAL_2026",
    testOnly: false, verified: true,
    source: "SPHOT_SERVER_VERIFIED_CHECKOUT_V1",
    reference, fingerprint: "a".repeat(64),
    expectedUntaxedCents: untaxed,
    expectedTotalCents: Math.round(untaxed * 1.2),
    verification: {
      source: "sphot_server_firestore_verified",
      cgvVersion: "1.0", cgvAcceptedAt: "2026-11-05T10:00:00Z",
      buyerEvidenceId: "verified_partner_123",
      taxEvidenceId: "validated_odoo_tax_123",
      pricingReference: tariff,
    },
    orderValues: {partner_id: 99, client_order_ref: reference,
      origin: `SPHOT ${tariff}`, order_line: lines},
  };
}
function gateway(prepared, outcome = "created") {
  return {contract: prepared.market === "ADMIN" ?
    "sphot_admin_atomic_order_v1" : "sphot_advertiser_atomic_order_v1",
  outcome, reference: prepared.reference, fingerprint: prepared.fingerprint,
  order: {id: 12, name: "S00012", client_order_ref: prepared.reference,
    x_sphot_reference: prepared.reference,
    x_sphot_fingerprint: prepared.fingerprint,
    partner_id: [99, "Client"], currency_id: [1, "EUR"],
    state: "draft", order_line: prepared.orderValues.order_line.map((_, i) => 30 + i),
    invoice_ids: [], amount_untaxed: prepared.expectedUntaxedCents / 100,
    amount_tax: (prepared.expectedTotalCents - prepared.expectedUntaxedCents) / 100,
    amount_total: prepared.expectedTotalCents / 100}};
}

function harness(market = "ADMIN") {
  const store = new Map();
  const key = (a,b) => `${a}/${b}`;
  const put = (c,id,obj) => store.set(key(c,id), structuredClone(obj));
  if (market === "ADMIN") {
    put("admins", UID, {accessStatus: "approved", uid: UID,
      territoireId: "territory_123456"});
  } else {
    put("advertiserRequests", ADVERT_ID, {
      status: "approved", firebaseUid: UID});
  }
  const db = {
    collection(name) {return {doc(id) {return {
      collectionName: name, id,
      async get() {const d = store.get(key(name,id));
        return {exists: !!d, data: () => d && structuredClone(d)};},
    };}};},
    async runTransaction(callback) {
      const ops=[];
      const result = await callback({
        async get(ref) {return ref.get();},
        create(ref,data) {ops.push(() => {
          if (store.has(key(ref.collectionName,ref.id))) throw Error("already_exists");
          put(ref.collectionName,ref.id,data);
        });},
        update(ref,data) {ops.push(() => {
          const k=key(ref.collectionName,ref.id);
          const previous = store.get(k);
          if (!previous) throw Error("not_found");
          put(ref.collectionName,ref.id,{...previous,...data});
        });},
      });
      for(const op of ops) op();
      return result;
    },
  };
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "timestamp_server"};
  const claims = market === "ADMIN" ?
    {uid: UID, adminUid: UID, role: "ADMIN", territoireId: "territory_123456"} :
    {uid: UID, role: "ANNONCEUR", advertiserRequestId: ADVERT_ID};
  const admin = {auth: () => ({verifyIdToken: async (token, revoked) => {
    assert.equal(token, "valid-token");assert.equal(revoked,true);
    return claims;
  }}), firestore};
  return {admin, store, claims, put};
}

function intentKey(market = "ADMIN") {
  return `odooCheckoutIntents/${market}_${market === "ADMIN" ? UID : ADVERT_ID}_INITIAL_2026`;
}

function callOptions(market = "ADMIN") {
  const h=harness(market);const prepared=fixture(market);
  let calls=0;
  const odooClient={call: async () => {calls++;return gateway(prepared);}};
  const prepareFromServer = async ({identity,db}) => {
    assert.equal(identity.uid,UID);
    assert.ok(db);
    return prepared;
  };
  return {h,prepared,options:{admin:h.admin,
    authorization:"Bearer valid-token",market,
    requestId: market === "ADMIN" ? UID : ADVERT_ID,
    prepareFromServer,odooClient},
  getCalls:()=>calls};
}

test("ADMIN : référence réservée puis commande Odoo unique, aucun droit",async()=>{
  const {h,prepared,options,getCalls}=callOptions();
  const r=await createOrResumeVerifiedCheckout(options);
  assert.equal(r.receipt.orderNumber,"S00012");
  assert.equal(r.receipt.activatesCommercialRights,false);
  assert.equal(getCalls(),1);
  const stored=h.store.get(intentKey());
  assert.equal(stored.status,"draft_created");
  assert.equal(stored.paymentStatus,"unverified");
  assert.equal(stored.cgvVersion,"1.0");
  assert.equal(h.store.size,2);
});

test("Deuxième clic ADMIN : aucune nouvelle requête Odoo",async()=>{
  const {options,getCalls}=callOptions();
  await createOrResumeVerifiedCheckout(options);
  const second=await createOrResumeVerifiedCheckout(options);
  assert.equal(second.alreadyExists,true);
  assert.equal(second.receipt.orderNumber,"S00012");
  assert.equal(getCalls(),1);
});

test("Annonceur : seule sa référence est enregistrée",async()=>{
  const {h,prepared,options}=callOptions("ADVERTISER");
  const r=await createOrResumeVerifiedCheckout(options);
  assert.equal(r.receipt.amountUntaxedCents,14900);
  assert.equal(h.store.get(intentKey("ADVERTISER")).market,"ADVERTISER");
});

test("Une panne Odoo laisse une réservation récupérable sans seconde référence",async()=>{
  const {h,prepared,options}=callOptions();let first=true;let calls=0;
  options.odooClient={call:async()=>{calls++;
    if(first){first=false;throw Error("network_unknown_result");}
    return gateway(prepared,"existing");}};
  await assert.rejects(createOrResumeVerifiedCheckout(options),/network_unknown_result/);
  assert.equal(h.store.get(intentKey()).status,"draft_pending");
  const res=await createOrResumeVerifiedCheckout(options);
  assert.equal(calls,2);
  assert.equal(res.receipt.orderNumber,"S00012");
  assert.equal(h.store.get(intentKey()).status,"draft_created");
});

test("Changement de prix/contrat sous la même référence : conflit avant Odoo",async()=>{
  const {options,prepared,getCalls}=callOptions();
  await createOrResumeVerifiedCheckout(options);
  prepared.fingerprint="b".repeat(64);
  await assert.rejects(createOrResumeVerifiedCheckout(options),/commande différente/);
  assert.equal(getCalls(),1);
});


test("Même dossier et même cycle : nouvelle référence refusée avant Odoo",async()=>{
  const {options,prepared,getCalls}=callOptions();
  await createOrResumeVerifiedCheckout(options);
  prepared.reference="SPHOT-ADM-2026-FFFF12345678";
  prepared.orderValues.client_order_ref=prepared.reference;
  await assert.rejects(createOrResumeVerifiedCheckout(options),/commande différente/);
  assert.equal(getCalls(),1);
});

test("Cycle contractuel absent : aucune écriture commerciale",async()=>{
  const {h,options,prepared,getCalls}=callOptions();
  prepared.cycleKey="";
  await assert.rejects(createOrResumeVerifiedCheckout(options),/Justificatifs/);
  assert.equal(h.store.size,1);
  assert.equal(getCalls(),0);
});

test("CGV non acceptées : aucun intent ni Odoo",async()=>{
  const {h,options,prepared,getCalls}=callOptions();
  prepared.verification.cgvAcceptedAt="";
  await assert.rejects(createOrResumeVerifiedCheckout(options),/Justificatifs/);
  assert.equal(getCalls(),0);assert.equal(h.store.size,1);
});

test("Dossier différent : vérification Firebase refuse avant le moteur Odoo",async()=>{
  const {h,options,getCalls}=callOptions();
  h.claims.adminUid="someone_else";
  await assert.rejects(createOrResumeVerifiedCheckout(options),/non autorisé/);
  assert.equal(getCalls(),0);assert.equal(h.store.size,1);
});

test("Mode TEST : pas d'appel Odoo et pas de transaction",async()=>{
  const {h,options,prepared,getCalls}=callOptions();
  prepared.testOnly=true;
  await assert.rejects(createOrResumeVerifiedCheckout(options));
  assert.equal(getCalls(),0);assert.equal(h.store.size,1);
});

test("Commande Odoo incohérente : intent reste en attente",async()=>{
  const {h,options,prepared}=callOptions();
  options.odooClient={call:async()=>{
    const r=gateway(prepared);r.order.amount_total=99999;return r;
  }};
  await assert.rejects(createOrResumeVerifiedCheckout(options));
  assert.equal(h.store.get(intentKey()).status,"draft_pending");
});

test("Aucun préparateur serveur de prix et CGV : aucun appel Odoo",async()=>{
  const {h,options,getCalls}=callOptions();
  delete options.prepareFromServer;
  await assert.rejects(createOrResumeVerifiedCheckout(options),/Vérification commerciale/);
  assert.equal(getCalls(),0);assert.equal(h.store.size,1);
});

test("Intent annulé ou inconnu : reprise bloquée",async()=>{
  const {h,options,prepared,getCalls}=callOptions();
  h.put("odooCheckoutIntents",`ADMIN_${UID}_INITIAL_2026`,{
    uid:UID,market:"ADMIN",requestId:UID,cycleKey:"INITIAL_2026",reference:prepared.reference,
    fingerprint:prepared.fingerprint,expectedUntaxedCents:prepared.expectedUntaxedCents,
    expectedTotalCents:prepared.expectedTotalCents,
    cgvVersion:"1.0",pricingReference:"FR_ADMIN-V4",
    testOnly:false,status:"cancelled",
  });
  await assert.rejects(createOrResumeVerifiedCheckout(options),/état reprenable/);
  assert.equal(getCalls(),0);
});
