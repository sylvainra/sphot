"use strict";

// Tests Firestore en memoire. Aucun appel Odoo, Firebase ni reseau.
const test = require("node:test");
const assert = require("node:assert/strict");
const {enregistrerLienFactureVerifie, lierFactureTestDepuisServeur} =
    require("../odoo_verified_billing_link");

const UID = "admin_1234567890";
const AID = "advert_1234567890";
const CYCLE = "INITIAL_2026";

function scenario(market = "ADMIN") {
  const admin = market === "ADMIN";
  const requestId = admin ? UID : AID;
  const reference = "SPHOT-" + (admin ? "ADM" : "PUB") + "-" +
      (admin ? "A" : "B").repeat(24);
  const pricingReference = admin ?
    "FR_ADMIN-V2" : "FR_ADVERTISER_RADIUS-V2";
  const ht = admin ? 49900 : 14900;
  const ttc = Math.round(ht * 1.2);
  const orderId = admin ? 11 : 12;
  const invoiceId = admin ? 18 : 19;
  const fingerprint = "a".repeat(64);
  const identity = {uid: UID, market, requestId};
  const prepared = {
    market, ownerUid: UID, requestId,
    cycleKey: CYCLE, testOnly: false, verified: true,
    source: "SPHOT_SERVER_VERIFIED_CHECKOUT_V1",
    reference, fingerprint, expectedUntaxedCents: ht,
    expectedTotalCents: ttc,
    verification: {
      source: "sphot_server_firestore_verified",
      cgvVersion: "1.0",
      cgvAcceptedAt: "2026-11-19T10:00:00.000Z",
      buyerEvidenceId: "BUYER_VERIFIED_TEST",
      taxEvidenceId: "TAX_VERIFIED_TEST",
      pricingReference,
    },
    orderValues: {
      partner_id: admin ? 9 : 8,
      client_order_ref: reference,
      origin: "SPHOT " + pricingReference,
      order_line: [[0, 0, {
        name: admin ?
          "SPHOT ADMIN / Tranche 1 / Tarif " + pricingReference :
          "SPHOT PUBLICITAIRE / radius_5km / map / 1 mois / Tarif " +
            pricingReference,
        product_id: admin ? 2 : 1,
        product_uom_qty: 1,
        price_unit: ht / 100,
        discount: 0,
      }]],
    },
  };
  const recu = {
    outcome: "created", market, reference, cycleKey: CYCLE,
    orderId, orderNumber: "S000" + orderId,
    invoiceId, invoiceNumber: "INV/TEST/" + invoiceId,
    invoiceState: "posted", amountUntaxedCents: ht,
    amountTotalCents: ttc, paymentStatus: "unverified",
    activatesCommercialRights: false,
    requiresSeparatePaymentEvidence: true,
  };
  const saved = new Map();
  const key = (collection, id) => collection + "/" + id;
  const put = (collection, id, value) =>
    saved.set(key(collection, id), structuredClone(value));
  const intentId = market + "_" + requestId + "_" + CYCLE;
  put("odooCheckoutIntents", intentId, {
    uid: UID, market, requestId, cycleKey: CYCLE,
    reference, fingerprint, expectedUntaxedCents: ht,
    expectedTotalCents: ttc,
    pricingReference, cgvVersion: "1.0",
    testOnly: false, status: "draft_created",
    orderNumber: recu.orderNumber, orderState: "draft",
    paymentStatus: "unverified", activatesCommercialRights: false,
  });
  if (admin) {
    put("subscriptions", UID, {
      adminUid: UID, status: "trial",
      numberOfRescueStations: 1,
      commercialCycleKey: CYCLE,
    });
  } else {
    put("advertiserRequests", AID, {
      firebaseUid: UID, status: "approved",
      campaignActivated: false,
      advertisingSpotCompleted: true,
    });
  }
  let writeCount = 0;
  const db = {
    collection(collection) {
      return {doc(id) {
        return {collection, id};
      }};
    },
    async runTransaction(callback) {
      const updates = [];
      const tx = {
        async get(ref) {
          const item = saved.get(key(ref.collection, ref.id));
          return {exists: item !== undefined,
            data: () => item === undefined ? undefined :
              structuredClone(item)};
        },
        create(ref, data) {
          updates.push(() => {
            const k = key(ref.collection, ref.id);
            assert.equal(saved.has(k), false);
            saved.set(k, structuredClone(data));
          });
        },
        update(ref, values) {
          updates.push(() => {
            const k = key(ref.collection, ref.id);
            assert.equal(saved.has(k), true);
            saved.set(k, {...saved.get(k), ...structuredClone(values)});
          });
        },
      };
      const result = await callback(tx);
      for (const update of updates) {
        update();
        writeCount++;
      }
      return result;
    },
  };
  const execute = () => enregistrerLienFactureVerifie({
    db, identity, prepared, recu,
    horodatage: () => "SERVER_TIMESTAMP_TEST",
  });
  return {
    db, saved, put, identity, prepared, recu, execute, intentId,
    getWrites: () => writeCount,
  };
}

test("ADMIN : lien dans adminOdooCycles, reference dans subscription", async () => {
  const s = scenario("ADMIN");
  const response = await s.execute();
  assert.equal(response.outcome, "linked");
  const link = s.saved.get(
      "adminOdooCycles/" + s.prepared.reference);
  const subscription = s.saved.get("subscriptions/" + UID);
  const intent = s.saved.get(
      "odooCheckoutIntents/" + s.intentId);
  assert.equal(link.adminUid, UID);
  assert.equal(link.ownerUid, UID);
  assert.equal(link.invoiceId, 18);
  assert.equal(link.orderFingerprint, s.prepared.fingerprint);
  assert.equal(link.invoiceState, "posted");
  assert.equal(link.paymentStatus, "unverified");
  assert.equal(link.activatesCommercialRights, false);
  assert.equal(link.amountTotalCents, s.prepared.expectedTotalCents);
  assert.equal(subscription.odooAdminCycleRef, s.prepared.reference);
  assert.equal(subscription.status, "trial");
  assert.equal(intent.invoiceId, 18);
  assert.equal(intent.status, "draft_created");
  assert.equal(intent.paymentStatus, "unverified");
  assert.equal(intent.activatesCommercialRights, false);
  assert.equal(s.getWrites(), 3);
});

test("PUBLICITAIRE : facture rattachee sans activer campagne", async () => {
  const s = scenario("ADVERTISER");
  const result = await s.execute();
  assert.equal(result.outcome, "linked");
  const data = s.saved.get("advertiserRequests/" + AID);
  assert.equal(data.status, "approved");
  assert.equal(data.campaignActivated, false);
  assert.equal(data.odooBilling.market, "ADVERTISER");
  assert.equal(data.odooBilling.ownerUid, UID);
  assert.equal(data.odooBilling.invoiceId, 19);
  assert.equal(data.odooBilling.amountTotalCents, 17880);
  assert.equal(data.odooBilling.paymentStatus, "unverified");
  assert.equal(data.odooBilling.activatesCommercialRights, false);
  assert.equal(s.getWrites(), 2);
});

for (const market of ["ADMIN", "ADVERTISER"]) {
  test(market + " : seconde demande idempotente, zero nouvelle ecriture",
      async () => {
        const s = scenario(market);
        await s.execute();
        const count = s.getWrites();
        s.recu.outcome = "existing";
        const response = await s.execute();
        assert.equal(response.outcome, "existing");
        assert.equal(s.getWrites(), count);
      });
}

test("ADMIN : une autre reference deja rattachee est refusee", async () => {
  const s = scenario("ADMIN");
  s.put("subscriptions", UID, {
    adminUid: UID, status: "trial",
    odooAdminCycleRef: "SPHOT-ADM-ANCIEN_CYCLE",
  });
  await assert.rejects(s.execute(), /Autre cycle/);
  assert.equal(s.getWrites(), 0);
});

test("ADMIN : lien historique incompatible non ecrase", async () => {
  const s = scenario("ADMIN");
  s.put("adminOdooCycles", s.prepared.reference, {
    adminUid: UID, ownerUid: UID,
    invoiceId: 999,
  });
  await assert.rejects(s.execute(), /autre rattachement/);
  assert.equal(s.getWrites(), 0);
});

test("PUBLICITAIRE : ancienne facture conflictuelle refusee", async () => {
  const s = scenario("ADVERTISER");
  s.put("advertiserRequests", AID, {
    firebaseUid: UID, status: "approved",
    campaignActivated: false,
    odooBilling: {invoiceId: 999},
  });
  await assert.rejects(s.execute(), /autre rattachement/);
  assert.equal(s.getWrites(), 0);
});

test("Aucune reservation Firestore : aucune projection comptable", async () => {
  const s = scenario("ADMIN");
  s.saved.delete("odooCheckoutIntents/" + s.intentId);
  await assert.rejects(s.execute(), /Reservation.*absente/);
  assert.equal(s.getWrites(), 0);
});

test("Facture non comptabilisee ou montant different : refus", async () => {
  const s = scenario("ADVERTISER");
  s.recu.invoiceState = "draft";
  await assert.rejects(s.execute(), /non verifiee/);
  s.recu.invoiceState = "posted";
  s.recu.amountTotalCents = 100;
  await assert.rejects(s.execute(), /non verifiee/);
  assert.equal(s.getWrites(), 0);
});

test("Fausse preuve de paiement ou droits actifs : refus", async () => {
  const s = scenario("ADMIN");
  s.recu.paymentStatus = "paid";
  await assert.rejects(s.execute(), /non verifiee/);
  s.recu.paymentStatus = "unverified";
  s.recu.activatesCommercialRights = true;
  await assert.rejects(s.execute(), /non verifiee/);
  assert.equal(s.getWrites(), 0);
});

test("Changement de compte PUBLICITAIRE ou activation concurrente refuse", async () => {
  const s = scenario("ADVERTISER");
  s.put("advertiserRequests", AID, {
    firebaseUid: "autre_UID", status: "approved",
    campaignActivated: false,
  });
  await assert.rejects(s.execute(), /autre compte/);
  s.put("advertiserRequests", AID, {
    firebaseUid: UID, status: "approved",
    campaignActivated: true,
  });
  await assert.rejects(s.execute(), /modifie/);
  assert.equal(s.getWrites(), 0);
});

test("Rattachement serveur bloque sans emulation Firestore explicite", async () => {
  await assert.rejects(lierFactureTestDepuisServeur({
    environment: {},
  }), /desactive/);
  await assert.rejects(lierFactureTestDepuisServeur({
    environment: {
      SPHOT_ENABLE_ODOO_FIRESTORE_LINK_TEST: "true",
      SPHOT_ODOO_DATABASE: "sphot_checkout_clone_neutral_20261118",
    },
  }), /desactive/);
  await assert.rejects(lierFactureTestDepuisServeur({
    environment: {
      SPHOT_ENABLE_ODOO_FIRESTORE_LINK_TEST: "true",
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
      SPHOT_ODOO_DATABASE: "sphot_publicitaire_checkout_test",
    },
  }), /desactive/);
});
