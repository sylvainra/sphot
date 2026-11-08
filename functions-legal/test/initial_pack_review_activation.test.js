"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {register} = require("../legal_pack_gateway");
const {validateInput} = require("../legal_pack_publication");
const index = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
const editor = fs.readFileSync(path.join(__dirname, "../legal_document_editor.js"), "utf8");
const pack = fs.readFileSync(path.join(__dirname, "../legal_pack_publication.js"), "utf8");
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
const response = () => {
  const r = {statusCode: 200, body: null};
  r.set = () => r;
  r.status = (code) => {r.statusCode = code; return r;};
  r.json = (data) => {r.body = data; return r;};
  return r;
};
test("phase de release: lot initial publie, edition individuelle manuelle controlee", () => {
  assert.match(index, /reviewEnabled:\s*true,\s*publishEnabled:\s*true/);
  assert.match(editor, /allowPublish:\s*true/);
  assert.match(pack, /PUBLICATION_MODIFIEE_RECHARGEZ/);
  assert.match(pack, /tx\.create\(historyRef/);
  assert.match(pack, /tx\.create\(packRef/);
});
test("statut: bouton de publication autorise uniquement par un retour authentifie", async () => {
  const handler = register({admin, reviewEnabled: true, publishEnabled: true,
    onRequest: (_opts, callback) => callback});
  const r = response();
  await handler({method: "POST", get: () => "Bearer test", body: {action: "status"}}, r);
  assert.equal(r.statusCode, 200);
  assert.equal(r.body.validationEnabled, true);
  assert.equal(r.body.publicationEnabled, true);
  assert.equal(r.body.documents.length, 5);
});
test("aucune publication sans confirmation et empreinte de version", async () => {
  const handler = register({admin, reviewEnabled: true, publishEnabled: true,
    onRequest: (_opts, callback) => callback});
  const r = response();
  await handler({method: "POST", get: () => "Bearer test", body: {
    action: "publish", expectedPackHash: "a".repeat(64), expectedVersion: "1.0",
  }}, r);
  assert.equal(r.statusCode, 400);
  assert.equal(r.body.success, false);
  assert.equal(r.body.error, "ACTION_OU_CONFIRMATION_INVALIDE");
  assert.throws(() => validateInput({action: "publish", confirm: true,
    expectedPackHash: "a".repeat(64), expectedVersion: "1.0", extra: 1}));
});
test("appel anonyme toujours refuse", async () => {
  const handler = register({admin, reviewEnabled: true, publishEnabled: true,
    onRequest: (_opts, callback) => callback});
  const r = response();
  await handler({method: "POST", get: () => "", body: {action: "status"}}, r);
  assert.equal(r.statusCode, 401);
});
