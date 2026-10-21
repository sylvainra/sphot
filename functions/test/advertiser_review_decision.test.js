"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildDecisionUpdate, registerAdvertiserReviewDecision} =
    require("../advertiser_review_decision");

const FieldValue = {
  serverTimestamp: () => "SERVER_TIME",
  arrayUnion: (...values) => ({arrayUnion: values}),
};
const Timestamp = {now: () => "DECISION_TIME"};

/** @return {Object} Dossier fictif avant décision. */
function pending() {
  return {
    status: "pending", contactEmail: "contact@example.test",
    applicantLocation: {latitude: 46, longitude: -1},
    proposedVisual: {url: "https://example.test/banner.png"},
    destinationUrl: "https://example.test",
  };
}
/** @return {Object} Dossier fictif avec proposition PHASE 2. */
function assetReview() {
  return {
    ...pending(), status: "approved",
    approvedApplication: {
      location: {latitude: 45, longitude: -2},
      visual: {url: "https://example.test/old.png"},
    },
    advertisingSpot: {latitude: 45, longitude: -2, marker: "keep"},
    assetChangeRequest: {
      status: "submitted", submittedAt: "SUBMITTED_TIME",
      proposedLocation: {latitude: 46, longitude: -1},
      proposedVisual: {url: "https://example.test/new.png"},
    },
  };
}
const decide = (data, command) =>
  buildDecisionUpdate(data, command, FieldValue, Timestamp);

test("PHASE 1: refus conserve motif et historique, sans champs client", () => {
  const patch = decide(pending(), {
    decision: "rejected", reason: "Dossier incomplet",
  });
  assert.equal(patch.status, "rejected");
  assert.equal(patch.rejectionEmail.status, "pending");
  assert.equal(patch.applicationHistory.arrayUnion[0].event, "rejected");
  assert.equal(patch.applicationHistory.arrayUnion[0].actor, "super_admin");
});

test("PHASE 1: correction multi-rubriques, motif obligatoire", () => {
  const patch = decide(pending(), {
    decision: "changes_requested", reason: "Corriger les deux éléments",
    scopes: ["visual", "location"],
  });
  assert.deepEqual(patch.correctionRequest.scopes, ["visual", "location"]);
  assert.equal(patch.changeRequestEmail.status, "pending");
  assert.equal(patch.applicationHistory.arrayUnion[0].event,
      "changes_requested");
  assert.throws(() => decide(pending(), {
    decision: "changes_requested", reason: "", scopes: ["visual"],
  }));
  assert.throws(() => decide(pending(), {
    decision: "changes_requested", reason: "Corriger", scopes: [],
  }));
});

test("PHASE 1: approbation, email en attente et historique", () => {
  const patch = decide(pending(), {decision: "approved"});
  assert.equal(patch.status, "approved");
  assert.equal(patch.approvalEmail.status, "pending");
  assert.equal(patch.applicationHistory.arrayUnion[0].event, "approved");
});

test("PHASE 2: approbation conserve historique et champs du spot", () => {
  const patch = decide(assetReview(), {decision: "approved"});
  assert.equal(patch.status, "approved");
  assert.equal(patch.advertisingSpot.marker, "keep");
  assert.equal(patch.advertisingSpot.latitude, 46);
  assert.equal(patch.assetChangeRequest.status, "approved");
  assert.equal(patch.assetChangeHistory.arrayUnion[0].decision, "approved");
  assert.equal(patch.applicationHistory, undefined);
});

test("PHASE 2: refus garde statut du dossier approuvé", () => {
  const patch = decide(assetReview(), {
    decision: "rejected", reason: "Visuel non conforme",
  });
  assert.equal(patch.status, "approved");
  assert.equal(patch.assetChangeRequest.status, "rejected");
  assert.equal(patch.rejectionEmail.status, "pending");
  assert.equal(patch.assetChangeHistory.arrayUnion[0].decision, "rejected");
});

test("PHASE 2: correction crée un mail sans écraser le dossier", () => {
  const patch = decide(assetReview(), {
    decision: "changes_requested", reason: "Visuel trop petit",
  });
  assert.equal(patch.status, "approved");
  assert.equal(patch.assetChangeRequest.status, "changes_requested");
  assert.equal(patch.changeRequestEmail.status, "pending");
});

test("dossier déjà examiné et rubriques invalides refusés", () => {
  assert.throws(() => decide({...pending(), status: "rejected"}, {
    decision: "approved",
  }));
  assert.throws(() => decide(pending(), {
    decision: "changes_requested", reason: "corriger", scopes: ["status"],
  }));
  assert.throws(() => decide(pending(), {
    decision: "changes_requested", reason: "corriger",
    scopes: ["visual", "visual"],
  }));
});

test("endpoint: refus si session Super Admin invalide", async () => {
  let resStatus;
  let resBody;
  const handler = registerAdvertiserReviewDecision({
    admin: {}, crypto: {}, onRequest: (_, callback) => callback,
    checkSuperAdminSession: async () => {
      throw new Error("expired");
    },
  });
  await handler({
    method: "POST", headers: {authorization: "Bearer bad"},
    body: {requestId: "abcdefgh", action: "review", decision: "approved"},
  }, {
    status: (status) => {
      resStatus = status;
      return {json: (body) => {
        resBody = body;
      }};
    },
  });
  assert.equal(resStatus, 401);
  assert.equal(resBody.success, false);
});
