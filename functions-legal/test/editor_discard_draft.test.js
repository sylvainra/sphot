"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {action, hash, EDITOR_SOURCE, validateInput, register} =
  require("../legal_document_editor");
const uid = `sphot-super-admin-${"a".repeat(32)}`;
const token = {uid, role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
  sphotSaSessionExpiresAt: Date.now() + 3600000};
const rows = [{id: "article_1", order: 1, title: "Test titre",
  content: "Texte non publié", isActive: true}];
const existing = {source: EDITOR_SOURCE, documentId: "cgu",
  status: "draft", draftRevision: 2, chapters: rows,
  sourceHash: hash(rows), baseHash: "a".repeat(64), baseRevision: 0};
function mock(draft = existing) {
  let saved = draft;
  const touched = [];
  const ref = (path) => ({path, doc: (id) => ref(`${path}/${id}`),
    collection: (name) => ref(`${path}/${name}`)});
  const tx = {get: async (reference) => {
    touched.push(`read:${reference.path}`);
    return {exists: saved != null, data: () => saved};
  }, delete: (reference) => {
    touched.push(`delete:${reference.path}`);
    saved = null;
  }, set: () => {throw new Error("ECRITURE HORS BROUILLON");},
  update: () => {throw new Error("ECRITURE HORS BROUILLON");},
  create: () => {throw new Error("ECRITURE HORS BROUILLON");}};
  const admin = {firestore: () => ({collection: (name) => ref(name),
    runTransaction: async (fn) => fn(tx)})};
  return {admin, touched, getDraft: () => saved};
}
function input(extra = {}) {return {action: "discard", documentId: "cgu",
  expectedDraftRevision: 2, confirm: true, ...extra};}
test("abandon d'un brouillon prive: efface uniquement ce document", async () => {
  const m = mock();
  const result = await action({admin: m.admin, token, input: input(),
    allowPublish: false});
  assert.deepEqual(result, {discarded: true, documentId: "cgu"});
  assert.equal(m.getDraft(), null);
  assert.deepEqual(m.touched, ["read:legalEditorialDrafts/cgu",
    "delete:legalEditorialDrafts/cgu"]);
});
test("abandon d'un brouillon deja valide: possible avant publication", async () => {
  const m = mock({...existing, status: "validated", reviewedHash: hash(rows)});
  const result = await action({admin: m.admin, token, input: input()});
  assert.equal(result.discarded, true);
  assert.equal(m.getDraft(), null);
});
test("abandon sans confirmation explicite refuse avant Firestore", () => {
  assert.throws(() => validateInput(input({confirm: false})),
    {httpStatus: 400, message: "CONFIRMATION_EXPLICITE_REQUISE"});
});
test("abandon sans revision ou avec champ inconnu refuse", () => {
  assert.throws(() => validateInput(input({expectedDraftRevision: -1})),
    {httpStatus: 400, message: "REVISION_BROUILLON_INVALIDE"});
  assert.throws(() => validateInput(input({published: true})),
    {httpStatus: 400, message: "ACTION_OU_CHAMPS_INTERDITS"});
});
test("abandon avec revision perimee refuse sans ecriture", async () => {
  const m = mock();
  await assert.rejects(action({admin: m.admin, token,
    input: input({expectedDraftRevision: 1})}),
  {httpStatus: 409, message: "BROUILLON_OBSOLETE_RECHARGEZ"});
  assert.deepEqual(m.touched, ["read:legalEditorialDrafts/cgu"]);
});
test("abandon brouillon deja publie refuse sans ecriture", async () => {
  const m = mock({...existing, status: "published"});
  await assert.rejects(action({admin: m.admin, token, input: input()}),
  {httpStatus: 409, message: "BROUILLON_OBSOLETE_RECHARGEZ"});
  assert.equal(m.getDraft().status, "published");
});
test("abandon avec role non autorise refuse avant Firestore", async () => {
  const m = mock();
  await assert.rejects(action({admin: m.admin,
    token: {...token, role: "ADMIN"}, input: input()}),
  {httpStatus: 403});
  assert.deepEqual(m.touched, []);
});
test("abandon d'un document non connu refuse", () => {
  assert.throws(() => validateInput(input({documentId: "metadata"})),
    {httpStatus: 400, message: "DOCUMENT_INCONNU"});
});
test("requete HTTP anonyme interdite avant tout acces Firestore", async () => {
  let accesses = 0;
  const m = {auth: () => ({verifyIdToken: async () => token}),
    firestore: () => {accesses++; throw Error("Firestore ne doit pas etre lu");}};
  const handler = register({admin: m, onRequest: (_options, fn) => fn});
  const res = {statusCode: 200, body: null, set: () => res,
    status: (n) => {res.statusCode = n; return res;},
    json: (v) => {res.body = v; return res;}};
  await handler({method: "POST", get: () => "", body: input()}, res);
  assert.equal(res.statusCode, 401);
  assert.equal(accesses, 0);
});
