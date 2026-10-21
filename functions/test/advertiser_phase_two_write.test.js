/* eslint-disable max-len, indent, comma-dangle, brace-style, operator-linebreak, object-curly-spacing, quote-props */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildPatch, calculatePlanning, validTerritory} =
    require("../advertiser_phase_two_write");

const firebase = {
  FieldValue: {
    serverTimestamp: () => "SERVER_TIME",
    delete: () => "DELETE",
  },
  Timestamp: {fromDate: (d) => d.toISOString()},
};
const now = new Date("2026-10-21T09:00:00Z");
const id = "candidate123";
const photo = "https://firebasestorage.googleapis.com/v0/b/" +
    "sphot-ab80b.firebasestorage.app/o/" +
    `advertising_banners%2F${id}%2Fbanner_123.jpg?alt=media&token=test`;
const data = {
  status: "approved", advertisingSpotCompleted: true,
  advertisingSpot: {latitude: 46.1, longitude: -1.3, bannerUrl: photo},
  approvedApplication: {visual: {url: photo}},
  diffusionCompleted: true,
};

test("do not allow advertiser to change review status", () => {
  const p = buildPatch(data, "saveDiffusion", {
    visibilityType: "map", status: "rejected", review: {reason: "fake"},
  }, firebase, now, id);
  assert.deepEqual(Object.keys(p).sort(), ["diffusion",
    "diffusionCompleted", "updatedAt"].sort());
});

test("only approved applications may be edited", () => {
  assert.throws(() => buildPatch({...data, status: "pending"},
      "savePlanning", {durationLabel: "1 mois", startDate: "2026-10-21"},
      firebase, now, id), /approuvée/);
});

test("contractual choices are locked when paid", () => {
  assert.throws(() => buildPatch({...data, order: {status: "paid"}},
      "saveDiffusion", {visibilityType: "map"},
      firebase, now, id), /verrouillée/);
});

test("reject unknown visibility values", () => {
  assert.throws(() => buildPatch(data, "saveDiffusion",
      {visibilityType: "free-unlimited"},
      firebase, now, id), /inconnue/);
});

test("validate duration using server calculations", () => {
  const p = buildPatch(data, "savePlanning", {
    durationLabel: "1 mois", startDate: "2026-10-21",
    campaignEndDate: "2099-01-01", status: "active",
  }, firebase, now, id);
  assert.equal(p.planning.campaignEndDate,
      "2026-11-21T12:00:00.000Z");
  assert.equal(Object.hasOwn(p, "status"), false);
});

test("reject past dates", () => {
  assert.throws(() => calculatePlanning("2026-10-18",
      "1 semaine", now), /aujourd'hui/);
});

test("reject unauthorized territory", () => {
  assert.throws(() => validTerritory({level: "radius_9000km"}),
      /invalide/);
});

test("do not allow changing an existing approved spot", () => {
  assert.throws(() => buildPatch(data, "saveSpot", {
    position: {latitude: 46.1, longitude: -1.3},
    visual: {url: photo},
    territory: {level: "radius_5km"},
  }, firebase, now, id), /déjà enregistré/);
});

test("an asset change is a proposal, not an approved mutation", () => {
  const p = buildPatch(data, "submitAssetChange", {
    position: {latitude: 46.2, longitude: -1.3},
    visual: {url: photo},
    status: "approved", radiusKm: 100,
  }, firebase, now, id);
  assert.equal(p.assetChangeRequest.status, "submitted");
  assert.deepEqual(Object.keys(p).sort(),
      ["assetChangeRequest", "updatedAt"].sort());
});

test("reject a second proposal while review is pending", () => {
  assert.throws(() => buildPatch({...data, assetChangeRequest: {
    status: "submitted"}}, "submitAssetChange", {
    position: {latitude: 46.2, longitude: -1.3}, visual: {url: photo},
  }, firebase, now, id), /instruction/);
});

test("HTTP: deny a caller without ANNOUNCEUR claim", async () => {
  const {registerAdvertiserPhaseTwoWrite} =
      require("../advertiser_phase_two_write");
  const fakeAdmin = {
    auth: () => ({verifyIdToken: async () => ({
      uid: "other", role: "advertiser_candidate", advertiserRequestId: id,
    })}),
  };
  const handler = registerAdvertiserPhaseTwoWrite({
    admin: fakeAdmin, onRequest: (_, fn) => fn,
  });
  let status = 0;
  const response = {
    status: (s) => {status = s; return response;},
    json: () => {},
  };
  await handler({method: "POST", headers: {authorization: "Bearer token"},
    body: {requestId: id, action: "saveDiffusion",
      payload: {visibilityType: "map"}}}, response);
  assert.equal(status, 403);
});

test("HTTP: do not write an application owned by another Firebase UID",
    async () => {
      const {registerAdvertiserPhaseTwoWrite} =
          require("../advertiser_phase_two_write");
      let written = false;
      const fakeAdmin = {
        auth: () => ({verifyIdToken: async () => ({
          uid: "actor-1", role: "ANNONCEUR", advertiserRequestId: id,
        })}),
        firestore: () => ({
          collection: () => ({doc: () => ({})}),
          runTransaction: async (fn) => fn({
            get: async () => ({exists: true,
              data: () => ({...data, firebaseUid: "another-actor"})}),
            update: () => {written = true;},
          }),
        }),
      };
      const handler = registerAdvertiserPhaseTwoWrite({
        admin: fakeAdmin, onRequest: (_, fn) => fn,
      });
      let status = 0;
      const response = {
        status: (s) => {status = s; return response;},
        json: () => {},
      };
      await handler({method: "POST",
        headers: {authorization: "Bearer token"},
        body: {requestId: id, action: "saveDiffusion",
          payload: {visibilityType: "map"}}}, response);
      assert.equal(status, 403);
      assert.equal(written, false);
    });
