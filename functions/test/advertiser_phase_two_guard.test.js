"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {registerAdvertiserPhaseTwoWrite} =
    require("../advertiser_phase_two_write");
const {buildDecisionUpdate} = require("../advertiser_review_decision");

const stamp = "NOW";
const Firestore = {
  FieldValue: {
    serverTimestamp: () => stamp,
    arrayUnion: (...items) => ({arrayUnion: items}),
  },
  Timestamp: {now: () => stamp},
};

/**
 * Execute a fake endpoint using the same auth and transaction branches.
 * @param {Object} claims Verified Firebase claims.
 * @param {Object} data Server document contents.
 * @param {string} action Action to submit.
 * @param {Object} suppliedPayload Optional body for asset corrections.
 * @return {Promise<Object>} HTTP response and server update.
 */
async function submit(claims, data, action, suppliedPayload) {
  let update;
  let httpStatus;
  let payload;
  const admin = {
    auth: () => ({verifyIdToken: async () => claims}),
    firestore: () => ({
      collection: () => ({doc: () => ({})}),
      runTransaction: async (callback) => callback({
        get: async () => ({exists: true, data: () => data}),
        update: (_, patch) => {
          update = patch;
        },
      }),
    }),
  };
  admin.firestore.FieldValue = Firestore.FieldValue;
  admin.firestore.Timestamp = Firestore.Timestamp;
  const endpoint = registerAdvertiserPhaseTwoWrite({
    admin, onRequest: (_, handler) => handler,
  });
  await endpoint({
    method: "POST", headers: {authorization: "Bearer test-id-token"},
    body: {
      requestId: "request_12345678", action,
      payload: suppliedPayload || {visibilityType: "map"},
    },
  }, {
    status: (code) => {
      httpStatus = code;
      return {
        json: (body) => {
          payload = body;
        },
      };
    },
  });
  return {httpStatus, payload, update};
}

const requestId = "request_12345678";
const candidate = {
  uid: requestId,
  role: "advertiser_candidate",
  advertiserRequestId: requestId,
};
const approved = {
  status: "approved", firebaseUid: "approved-user-uid",
  advertisingSpotCompleted: true, contactEmail: "test@example.com",
};

test("correction session cannot change pricing or diffusion", async () => {
  const result = await submit(candidate, {
    ...approved, assetChangeRequest: {status: "changes_requested"},
  }, "saveDiffusion");
  assert.equal(result.httpStatus, 403);
  assert.equal(result.update, undefined);
});

test("correction session cannot write without an open asset correction",
    async () => {
      const result = await submit(candidate, {
        ...approved, assetChangeRequest: {status: "rejected"},
      }, "submitAssetChange");
      assert.equal(result.httpStatus, 403);
      assert.equal(result.update, undefined);
    });

test("a personal correction link submits an authorized PHASE 2 proposal",
    async () => {
      const originalVisual = "https://example.org/banner-original.png";
      const replacement =
          "https://firebasestorage.googleapis.com/v0/b/" +
          "sphot-ab80b.firebasestorage.app/o/" +
          "advertising_banners%2Frequest_12345678%2Fbanner_123.png";
      const data = {
        ...approved,
        approvedApplication: {visual: {url: originalVisual}},
        advertisingSpot: {
          latitude: 46, longitude: -1, bannerUrl: originalVisual,
        },
        assetChangeRequest: {status: "changes_requested"},
      };
      const result = await submit(candidate, data, "submitAssetChange", {
        position: {latitude: 46, longitude: -1},
        visual: {url: replacement},
      });
      assert.equal(result.httpStatus, 200);
      assert.equal(result.update.assetChangeRequest.status, "submitted");
      assert.equal(result.update.advertisingSpot, undefined);
    });

test("candidate cannot impersonate another file owner", async () => {
  const result = await submit({...candidate, uid: "other-uid"}, {
    ...approved, assetChangeRequest: {status: "changes_requested"},
  }, "submitAssetChange");
  assert.equal(result.httpStatus, 403);
});

test("a normal approved advertiser can save a diffusion", async () => {
  const result = await submit({
    uid: approved.firebaseUid, role: "ANNONCEUR",
    advertiserRequestId: requestId,
  }, approved, "saveDiffusion");
  assert.equal(result.httpStatus, 200);
  assert.equal(result.update.diffusion.visibilityType, "map");
});

test("other approved advertiser cannot save somebody else's file",
    async () => {
      const result = await submit({
        uid: "different-user", role: "ANNONCEUR",
        advertiserRequestId: requestId,
      }, approved, "saveDiffusion");
      assert.equal(result.httpStatus, 403);
    });

test("PHASE 2 review preserves PHASE 1 approval metadata", () => {
  const previous = {
    ...approved,
    review: {status: "approved", reviewedAt: "OLD", reason: ""},
    approvedApplication: {
      campaignType: "already-approved",
      destinationUrl: "https://example.org",
      location: {latitude: 46, longitude: -1},
      visual: {url: "https://example.org/old.png"},
    },
    applicantLocation: {latitude: 46, longitude: -1},
    advertisingSpot: {latitude: 46, longitude: -1},
    assetChangeRequest: {
      status: "submitted",
      proposedLocation: {latitude: 47, longitude: -2},
      proposedVisual: {url: "https://example.org/new.png"},
    },
  };
  const changed = buildDecisionUpdate(previous, {
    decision: "approved", reason: "",
  }, Firestore.FieldValue, Firestore.Timestamp);
  assert.equal(changed.status, "approved");
  assert.equal(changed.review, undefined);
  assert.equal(changed.applicantLocation, undefined);
  assert.equal(changed.approvedApplication.campaignType, "already-approved");
  assert.equal(changed.approvedApplication.destinationUrl,
      "https://example.org");
});

test("asset correction email reuses first email queue", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "index.js"),
      "utf8");
  assert.ok(source.includes(
      "[\"authorized\", \"changes_requested\"]"));
  assert.ok(source.includes(
      "[\"pending\", \"sending\", \"sent\"]"));
});
