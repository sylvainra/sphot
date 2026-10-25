/* eslint-disable max-len, require-jsdoc, indent, comma-dangle, brace-style, object-curly-spacing */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {initialPrices} = require("../advertiser_radius_tariffs");
const {calculatePlanning} = require("../advertiser_phase_two_write");
const {preparedOrder, referenceFor, assertClientSawQuote,
  registerAdvertiserInitialOrder} = require("../advertiser_initial_order");

const requestId = "candidate123";
const uid = "advertiser_uid_123";
const now = new Date("2026-10-25T12:00:00Z");
const dates = calculatePlanning("2027-01-12", "1 mois", now);
const published = {
  type: "ADVERTISER_RADIUS", country: "FR", currency: "EUR",
  publishedVersion: 2, publishedPrices: initialPrices(),
};
const client = {
  status: "approved", firebaseUid: uid,
  advertisingSpotCompleted: true, diffusionCompleted: true,
  planningCompleted: true,
  advertisingTerritory: {level: "radius_5km", code: "WORLD_radius_5km"},
  diffusion: {visibilityType: "map"},
  planning: {
    durationLabel: "1 mois",
    campaignStartDate: dates.start,
    campaignEndDate: dates.end,
  },
  acceptedDocuments: {
    cgu: true, privacy: true, rgpd: true, advertiserCgv: true,
    version: "4.0", advertiserCgvVersion: "2.0",
  },
  legalAcceptance: {representativeDeclaration: true},
};

function expectedQuote({percent = 10} = {}) {
  return {
    territory: "radius_5km", offer: "map", duration: "1 mois",
    startDate: "2027-01-12", pricingReference: "FR_ADVERTISER_RADIUS-V2",
    payableExclTaxCents: 14900 * (100 - percent) / 100,
  };
}

test("internal test order uses the published tariff, individual discount and saved dates", () => {
  const order = preparedOrder(client, published, 10, requestId, uid, now);
  assert.equal(order.reference, referenceFor(requestId));
  assert.equal(order.baseAmountExclTaxCents, 14900);
  assert.equal(order.discountAmountCents, 1490);
  assert.equal(order.payableExclTaxCents, 13410);
  assert.equal(order.pricingReference, "FR_ADVERTISER_RADIUS-V2");
  assert.equal(order.tariffKey, "0:0:2");
  assert.equal(order.paymentStatus, "not_started");
  assert.equal(order.paymentProofVerified, false);
  assert.equal(order.campaignActivationAllowed, false);
  assert.equal(order.odooStatus, "not_connected");
  assert.equal(order.automaticRenewal, false);
  assert.equal(order.environment, "test");
  assert.equal(order.legalAcceptanceSnapshot.cgvVersion, "2.0");
});

test("rejects unpersisted planning and invalid legal acceptance", () => {
  assert.throws(() => preparedOrder({...client, planningCompleted: false},
      published, 0, requestId, uid, now), /Enregistrez/);
  assert.throws(() => preparedOrder({...client,
    acceptedDocuments: {...client.acceptedDocuments, advertiserCgv: false},
  }, published, 0, requestId, uid, now), /juridiques/);
});

test("rejects manipulated planning, elapsed start date and prior orders", () => {
  assert.throws(() => preparedOrder({...client, planning: {
    ...client.planning, campaignEndDate: new Date("2027-01-15T12:00:00Z"),
  }}, published, 0, requestId, uid, now), /cohérente/);
  assert.throws(() => preparedOrder(client, published, 0, requestId,
      uid, new Date("2027-02-01T12:00:00Z")), /dépassée/);
  assert.throws(() => preparedOrder({...client, order: {status: "paid"}},
      published, 0, requestId, uid, now), /déjà/);
});

test("price drift or changed choices require redisplay and reconfirmation", () => {
  const order = preparedOrder(client, published, 10, requestId, uid, now);
  assertClientSawQuote(order, {
    ...expectedQuote(), payableExclTaxCents: 13410,
  });
  for (const changed of [
    {payableExclTaxCents: 999},
    {offer: "pack"},
    {pricingReference: "FR_ADVERTISER_RADIUS-V1"},
    {startDate: "2027-01-13"},
  ]) {
    assert.throws(() => assertClientSawQuote(order, {
      ...expectedQuote(), payableExclTaxCents: 13410, ...changed,
    }), /changé/);
  }
});

function mockHandler({claims = {role: "ANNONCEUR", advertiserRequestId: requestId,
  uid}, data = client, percent = 10} = {}) {
  let stored = {...data};
  let updates = 0;
  const refs = {
    request: {path: `advertiserRequests/${requestId}`},
    pricing: {path: "commercialPricingMarkets/FR_ADVERTISER_RADIUS"},
    discount: {path: `commercialCustomerDiscounts/ADVERTISER_RADIUS__${uid}`},
  };
  const admin = {
    auth: () => ({verifyIdToken: async () => claims}),
    firestore: () => ({
      collection: (name) => ({doc: (id) =>
        ({path: `${name}/${id}`})}),
      runTransaction: async (work) => work({
        get: async (ref) => {
          if (ref.path === refs.request.path) {
            return {exists: true, data: () => stored};
          }
          if (ref.path === refs.pricing.path) {
            return {exists: true, data: () => published};
          }
          if (ref.path === refs.discount.path) {
            return {exists: true, data: () => ({percent})};
          }
          throw Error("Unexpected Firestore path " + ref.path);
        },
        update: (ref, patch) => {
          assert.equal(ref.path, refs.request.path);
          stored = {...stored, ...patch};
          updates++;
        },
      }),
    }),
  };
  admin.firestore.FieldValue = {serverTimestamp: () => "SERVER_TIME"};
  const handler = registerAdvertiserInitialOrder({
    admin, onRequest: (_, callback) => callback, testOrdersEnabled: true,
  });
  async function call(body = {requestId, expected: {
    ...expectedQuote(), payableExclTaxCents: 13410,
  }}) {
    const result = {status: null, json: null};
    const res = {
      set: () => res,
      status: (code) => {result.status = code; return res;},
      json: (json) => {result.json = json; return res;},
    };
    await handler({method: "POST", body,
      headers: {authorization: "Bearer test-token"}}, res);
    return result;
  }
  return {call, get stored() {return stored;}, get updates() {return updates;}};
}

test("authenticated initial order is written once, with stable reference", async () => {
  const fake = mockHandler();
  const first = await fake.call();
  assert.equal(first.status, 200);
  assert.equal(first.json.alreadyExists, false);
  assert.equal(first.json.receipt.payableExclTaxCents, 13410);
  assert.equal(first.json.receipt.testOnly, true);
  assert.equal(fake.stored.quoteOrderCompleted, true);
  assert.equal(fake.stored.order.paymentProofVerified, false);
  assert.equal(fake.updates, 1);

  const again = await fake.call();
  assert.equal(again.status, 200);
  assert.equal(again.json.alreadyExists, true);
  assert.equal(again.json.receipt.reference, first.json.receipt.reference);
  assert.equal(fake.updates, 1);
});

test("cannot create an order for someone else's approved request", async () => {
  const fake = mockHandler({data: {...client, firebaseUid: "someone_else"}});
  const result = await fake.call();
  assert.equal(result.status, 403);
  assert.equal(fake.updates, 0);
});

test("cannot create an order with a different role", async () => {
  const fake = mockHandler({claims: {role: "SUPER_ADMIN", uid}});
  const result = await fake.call();
  assert.equal(result.status, 403);
  assert.equal(fake.updates, 0);
});

test("a stale preview never generates a test order", async () => {
  const fake = mockHandler();
  const result = await fake.call({requestId, expected: expectedQuote({percent: 0})});
  assert.equal(result.status, 409);
  assert.equal(fake.updates, 0);
});

test("order is rejected when application is no longer approved", async () => {
  const fake = mockHandler({data: {...client, status: "rejected"}});
  const result = await fake.call();
  assert.equal(result.status, 409);
  assert.equal(fake.updates, 0);
});

test("endpoint is closed by default without explicit test enablement", async () => {
  const handler = registerAdvertiserInitialOrder({
    admin: {}, onRequest: (_, callback) => callback,
    testOrdersEnabled: false,
  });
  let responseCode = null;
  const res = {
    set: () => res,
    status: (code) => {responseCode = code; return res;},
    json: () => res,
  };
  await handler({method: "POST", headers: {}, body: {}}, res);
  assert.equal(responseCode, 503);
});
