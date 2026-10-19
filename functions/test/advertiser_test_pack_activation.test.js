"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  previewTestPack,
  registerAdvertiserTestPackActivation,
} = require("../advertiser_test_pack_activation");
const {projectPublicMapAdvertisement} =
    require("../public_map_advertising");

const NOW = Date.parse("2026-10-19T16:00:00Z");

/**
 * @param {Object} overrides Champs du dossier.
 * @return {Object} Dossier annonceur approuvé.
 */
function dossier(overrides = {}) {
  return {
    status: "approved",
    diffusionCompleted: true,
    diffusion: {visibilityType: "pack"},
    establishment: {businessName: "BAR DE LA PLAGE"},
    advertisingSpot: {bannerUrl: "https://example.com/surf-shop.jpg"},
    ...overrides,
  };
}

/**
 * @param {Object} overrides Champs de la campagne.
 * @return {Object} Campagne Carte active.
 */
function campagne(overrides = {}) {
  return {
    status: "active",
    visibilityType: "map",
    advertiserName: "BAR DE LA PLAGE",
    bannerUrl: "https://example.com/surf-shop.jpg",
    broadcastType: "local",
    centerLat: 46.4,
    centerLng: -1.5,
    radiusKm: 5,
    campaignStartDate: new Date(NOW - 3600000),
    campaignEndDate: new Date(NOW + 2 * 86400000),
    ...overrides,
  };
}

test("Pack autorisé : même annonceur, visuel et campagne active", () => {
  const plan = previewTestPack(dossier(), campagne(), "request1", NOW);
  assert.equal(plan.proposedVisibilityType, "pack");
  assert.equal(plan.previousVisibilityType, "map");
  assert.equal(plan.expiresAt, NOW + 86400000);
});

test("Pack refusé si le dossier n'est pas confirmé ou approuvé", () => {
  assert.throws(() => previewTestPack(
      dossier({status: "pending"}), campagne(), "request1", NOW));
  assert.throws(() => previewTestPack(
      dossier({diffusion: {visibilityType: "map"}}),
      campagne(), "request1", NOW));
});

test("Pack refusé si la campagne porte un autre visuel ou dossier", () => {
  assert.throws(() => previewTestPack(
      dossier(), campagne({bannerUrl: "https://example.com/other.jpg"}),
      "request1", NOW));
  assert.throws(() => previewTestPack(
      dossier(), campagne({advertiserRequestId: "someone-else"}),
      "request1", NOW));
});

test("Le Pack de test expire dans l'API sans modifier les dates", () => {
  const testPack = {
    previousVisibilityType: "map",
    expiresAt: new Date(NOW + 120000),
  };
  const active = projet(NOW + 60000, testPack);
  const expired = projet(NOW + 180000, testPack);
  assert.equal(active.visibilityType, "pack");
  assert.equal(expired.visibilityType, "map");
});

/**
 * @param {number} now Horodatage du contrôle.
 * @param {Object} testPack Droit temporaire.
 * @return {Object} Projection publique.
 */
function projet(now, testPack) {
  return projectPublicMapAdvertisement("x", campagne({
    visibilityType: "pack",
    testPack,
  }), now);
}

test("Sans session, l'API de confirmation refuse sans écrire", async () => {
  let writes = 0;
  const admin = {
    firestore: () => {
      writes++;
      return {};
    },
  };
  const handler = registerAdvertiserTestPackActivation({
    admin, crypto: {},
    onRequest: (_, fn) => fn,
    checkSuperAdminSession: async () => "super-admin",
  });
  const response = {
    set() {return this;},
    status(code) {this.code = code; return this;},
    json(body) {this.body = body; return this;},
  };
  await handler({
    method: "POST",
    headers: {origin: "http://localhost:51778"},
    body: {action: "confirm"},
  }, response);
  assert.equal(response.code, 401);
  assert.equal(writes, 0);
});


test("Prévisualisation sans écriture et confirmation limitée au Pack",
    async () => {
      const updates = [];
      const histories = [];
      const requestRef = {
        kind: "request",
        get: async () => document(requestRef),
      };
      const campaignRef = {
        kind: "campaign",
        get: async () => document(campaignRef),
        collection: () => ({doc: () => ({kind: "history"})}),
      };
      const document = (ref) => ({
        exists: true,
        data: () => ref.kind === "request" ? dossier() : campagne({
          campaignStartDate: new Date(Date.now() - 3600000),
          campaignEndDate: new Date(Date.now() + 3600000),
        }),
      });
      const firestore = () => ({
        collection: (name) => ({
          doc: () => name === "adRequests" ? campaignRef : requestRef,
        }),
        runTransaction: async (callback) => callback({
          get: async (ref) => document(ref),
          update: (ref, fields) => updates.push({ref, fields}),
          set: (ref, fields) => histories.push({ref, fields}),
        }),
      });
      firestore.Timestamp = {
        fromMillis: (timestamp) => new Date(timestamp),
      };
      firestore.FieldValue = {
        serverTimestamp: () => new Date(),
      };
      const handler = registerAdvertiserTestPackActivation({
        admin: {firestore},
        crypto: {},
        onRequest: (_, callback) => callback,
        checkSuperAdminSession: async () => "super-admin",
      });
      const response = {
        set() {return this;},
        status(code) {this.code = code; return this;},
        json(body) {this.body = body; return this;},
      };
      const base = {
        method: "POST",
        headers: {
          origin: "http://localhost:51778",
          authorization: "Bearer test-session",
        },
      };
      await handler({...base, body: {
        requestId: "dossier-1", campaignId: "campaign-1", action: "preview",
      }}, response);
      assert.equal(response.code, 200);
      assert.equal(updates.length, 0);
      assert.equal(histories.length, 0);
      await handler({...base, body: {
        requestId: "dossier-1",
        campaignId: "campaign-1",
        action: "confirm",
        confirmation: "ACTIVER PACK TEST",
      }}, response);
      assert.equal(response.code, 200);
      assert.equal(updates.length, 1);
      assert.equal(histories.length, 1);
      assert.equal(updates[0].fields.visibilityType, "pack");
      assert.equal(updates[0].fields.advertiserRequestId, "dossier-1");
      assert.equal(updates[0].fields.testPack.previousVisibilityType, "map");
      assert.equal(
          Object.hasOwn(updates[0].fields, "campaignEndDate"), false);
      assert.equal(
          Object.hasOwn(updates[0].fields, "totalPriceExclTax"), false);
    });
