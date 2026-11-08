"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {register} = require("../legal_pack_gateway");
const token = {role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
  uid: "sphot-super-admin-" + "a".repeat(32),
  sphotSaSessionExpiresAt: Date.now() + 600000};
const admin = {
  auth: () => ({verifyIdToken: async () => token}),
  firestore: () => ({collection: (name) => ({doc: (id) => ({get: async () => ({
    exists: name === "legalDocuments" && id === "metadata",
    data: () => ({version: "1.0"}),
  })})})}),
};
test("lot initial : le statut expose deux verrous fermes", async () => {
  const handler = register({admin, onRequest: (_options, callback) => callback});
  const response = {statusCode: 200, body: null};
  response.set = () => response;
  response.status = (code) => {response.statusCode = code; return response;};
  response.json = (value) => {response.body = value; return response;};
  await handler({method: "POST", get: () => "Bearer test",
    body: {action: "status"}}, response);
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.validationEnabled, false);
  assert.equal(response.body.publicationEnabled, false);
  assert.equal(response.body.documents.length, 5);
});
