"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {registerAdvertiserCorrectionResubmit} =
    require("../advertiser_correction_resubmit");

/**
 * Construit un faux serveur Firebase pour tester le contrôle des droits.
 * @param {Object} overrides Valeurs du dossier de test.
 * @param {Object} claims Revendications du jeton de test.
 * @return {Object} Gestionnaire d'appel et journal des écritures.
 */
function setup(overrides = {}, claims = {}) {
  const dossier = {
    status: "changes_requested",
    correctionRequest: {
      status: "changes_requested", scopes: ["location"], reason: "Position",
    },
    profileCompleted: true,
    establishmentCompleted: true,
    applicationCompleted: true,
    legalAcceptanceCompleted: true,
    contactEmail: "advertiser@example.com",
    ...overrides,
  };
  const writes = [];
  const identity = {
    uid: "request-12345", role: "advertiser_candidate",
    advertiserRequestId: "request-12345", ...claims,
  };
  const admin = {
    auth: () => ({verifyIdToken: async (token, checkRevoked) => {
      assert.equal(token, "valid");
      assert.equal(checkRevoked, true);
      return identity;
    }}),
    firestore: () => ({
      collection: (name) => ({doc: (id) => ({name, id})}),
      runTransaction: async (callback) => callback({
        get: async (ref) => {
          if (ref.name === "advertiserRequests") {
            return {exists: true, data: () => dossier};
          }
          if (ref.id === "metadata") {
            return {data: () => ({legalVersion: "2.0", packPath: "legal"})};
          }
          if (ref.id === "advertiserCgv") {
            return {data: () => ({version: "3.0"})};
          }
          throw new Error("unknown collection " + ref.name);
        },
        update: (ref, update) => writes.push({ref, update}),
      }),
    }),
  };
  admin.firestore.FieldValue = {
    serverTimestamp: () => "SERVER_TIME",
    arrayUnion: (entry) => ({append: entry}),
  };
  admin.firestore.Timestamp = {now: () => "NOW"};
  const handler = registerAdvertiserCorrectionResubmit({
    admin, onRequest: (_options, fn) => fn,
  });
  const call = async (
      body = {requestId: "request-12345", legalAcceptance: false},
      authorization = "Bearer valid") => {
    const req = {method: "POST", headers: {authorization}, body};
    const res = {
      code: 200, payload: null,
      status(code) {
        this.code = code;
        return this;
      },
      json(payload) {
        this.payload = payload;
        return this;
      },
    };
    await handler(req, res);
    return res;
  };
  return {call, writes};
}

const TEST_RETRANSMISSION =
    "retransmission sans droit de modifier decision par le client";
test(TEST_RETRANSMISSION, async () => {
  const {call, writes} = setup();
  const result = await call();
  assert.equal(result.code, 200);
  assert.equal(writes.length, 1);
  const update = writes[0].update;
  assert.equal(update.status, "pending");
  assert.equal(update["review.status"], "pending");
  assert.equal(update["correctionRequest.status"], "resubmitted");
  assert.equal(update.applicationHistory.append.event, "resubmitted");
  assert.equal(update.applicationHistory.append.actor, "advertiser");
  assert.deepEqual(update.acknowledgementEmail, {
    status: "pending",
    recipient: "advertiser@example.com",
    updatedAt: "SERVER_TIME",
  });
});

test("autre demandeur refuse", async () => {
  const {call, writes} = setup({}, {uid: "other-user"});
  assert.equal((await call()).code, 403);
  assert.equal(writes.length, 0);
});

test("jeton d'identite absente refuse", async () => {
  const {call, writes} = setup();
  assert.equal((await call(undefined, "")).code, 401);
  assert.equal(writes.length, 0);
});

test("dossier sans correction ouverte refuse", async () => {
  const {call, writes} = setup({status: "approved"});
  assert.equal((await call()).code, 409);
  assert.equal(writes.length, 0);
});

test("appel repete ne produit pas un second historique", async () => {
  const {call, writes} = setup({status: "pending", correctionRequest: {
    status: "resubmitted", scopes: ["location"],
  }});
  assert.equal((await call()).code, 200);
  assert.equal(writes.length, 0);
});

test("attestation juridique impossible si rubrique interdite", async () => {
  const {call, writes} = setup();
  const result = await call({requestId: "request-12345", legalAcceptance: true,
    legalVersion: "2.0", advertiserCgvVersion: "3.0"});
  assert.equal(result.code, 409);
  assert.equal(writes.length, 0);
});

test("version juridique obsolete refusee", async () => {
  const {call, writes} = setup({correctionRequest: {
    status: "changes_requested", scopes: ["legal"],
  }});
  const result = await call({requestId: "request-12345", legalAcceptance: true,
    legalVersion: "1.0", advertiserCgvVersion: "3.0"});
  assert.equal(result.code, 409);
  assert.equal(writes.length, 0);
});

test("validations juridiques actuelles enregistrees cote serveur", async () => {
  const {call, writes} = setup({correctionRequest: {
    status: "changes_requested", scopes: ["legal"],
  }});
  const result = await call({requestId: "request-12345", legalAcceptance: true,
    legalVersion: "2.0", advertiserCgvVersion: "3.0"});
  assert.equal(result.code, 200);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].update.legalAcceptance.version, "2.0");
  assert.equal(writes[0].update.acceptedDocuments.advertiserCgvVersion, "3.0");
});

test("liste de rubriques invalide refusee", async () => {
  const {call, writes} = setup({correctionRequest: {
    status: "changes_requested", scopes: ["unknown"],
  }});
  assert.equal((await call()).code, 409);
  assert.equal(writes.length, 0);
});


test("retransmission rearme le mail deja envoye", async () => {
  const {call, writes} = setup({
    contactEmail: "NOUVEAU@EXAMPLE.COM",
    acknowledgementEmail: {status: "sent", messageId: "ancien-id"},
  });
  const result = await call();
  assert.equal(result.code, 200);
  assert.deepEqual(writes[0].update.acknowledgementEmail, {
    status: "pending",
    recipient: "nouveau@example.com",
    updatedAt: "SERVER_TIME",
  });
});
