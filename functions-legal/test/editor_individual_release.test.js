"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {register, validateInput} = require("../legal_document_editor");
const fs = require("node:fs");
const path = require("node:path");
const server = fs.readFileSync(path.join(__dirname, "../legal_document_editor.js"), "utf8");
const index = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
const uid = `sphot-super-admin-${"a".repeat(32)}`;
const token = {uid, role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
  sphotSaSessionExpiresAt: Date.now() + 3600000};
function res() {
  const r = {statusCode: 200, body: null};
  r.set = () => r;
  r.status = (code) => {r.statusCode = code; return r;};
  r.json = (data) => {r.body = data; return r;};
  return r;
}
function makeHandler({user = token} = {}) {
  let reads = 0;
  let writes = 0;
  const doc = () => ({get: async () => {reads++; return {exists: false,
    data: () => ({})};}, collection: () => ({get: async () => {reads++;
    return {docs: []};}})});
  const admin = {
    auth: () => ({verifyIdToken: async () => user}),
    firestore: () => ({collection: () => ({doc}),
      runTransaction: async () => {writes++; throw Error("Unexpected write attempt");}}),
  };
  return {handler: register({admin, onRequest: (_, callback) => callback}),
    stats: () => ({reads, writes})};
}
test("release individuel : action manuelle uniquement, lot initial conserve", () => {
  assert.match(server, /allowPublish: true \/\* publication individuelle explicite uniquement \*\//);
  assert.match(server, /PUBLIER_D_ABORD_LE_LOT_INITIAL/);
  assert.match(server, /BROUILLON_NON_VALIDE_OU_MODIFIE/);
  assert.match(server, /HISTORIQUE_INCOHERENT_OU_VERSION_EXISTANTE/);
  assert.match(index, /reviewEnabled: true, publishEnabled: true/);
  assert.equal(validateInput({action: "publish", documentId: "cgu",
    expectedDraftRevision: 1, expectedHash: "a".repeat(64), confirm: true}).action,
    "publish");
  assert.throws(() => validateInput({action: "publish", documentId: "cgu",
    expectedDraftRevision: 1, expectedHash: "a".repeat(64), confirm: false}),
    {httpStatus: 400, message: "CONFIRMATION_EXPLICITE_REQUISE"});
});
test("HTTP sans session Super Admin refuse sans lecture ni ecriture", async () => {
  const {handler, stats} = makeHandler();
  const r = res();
  await handler({method: "POST", get: () => "", body: {action: "status", documentId: "cgu"}}, r);
  assert.equal(r.statusCode, 401);
  assert.deepEqual(stats(), {reads: 0, writes: 0});
});
test("jeton sans droits Super Admin refuse sans lecture ni ecriture", async () => {
  const {handler, stats} = makeHandler({user: {...token, role: "ADMIN"}});
  const r = res();
  await handler({method: "POST", get: () => "Bearer test",
    body: {action: "status", documentId: "cgu"}}, r);
  assert.equal(r.statusCode, 403);
  assert.deepEqual(stats(), {reads: 0, writes: 0});
});
test("publication sans confirmation refusee avant toute lecture ou ecriture", async () => {
  const {handler, stats} = makeHandler();
  const r = res();
  await handler({method: "POST", get: () => "Bearer test",
    body: {action: "publish", documentId: "cgu",
      expectedDraftRevision: 1, expectedHash: "a".repeat(64), confirm: false}}, r);
  assert.equal(r.statusCode, 400);
  assert.deepEqual(stats(), {reads: 0, writes: 0});
});
test("statut de l'editeur expose la publication manuelle sans creer de brouillon", async () => {
  const {handler, stats} = makeHandler();
  const r = res();
  await handler({method: "POST", get: () => "Bearer test",
    body: {action: "status", documentId: "cgu"}}, r);
  assert.equal(r.statusCode, 200);
  assert.equal(r.body.publicationEnabled, true);
  assert.equal(r.body.draft, null);
  assert.equal(stats().writes, 0);
});
