"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {action, EDITOR_SOURCE, hash} = require("../legal_document_editor");
const {activeSnapshot} = require("../legal_pack_publication");
const UID = `sphot-super-admin-${"a".repeat(32)}`;
const ids = ["cgu", "adminCgv", "advertiserCgv", "sauveteurCgu", "sauveteurCharter",
  "privacyPolicy", "rgpdNotice"];
function fixture() {
  const docs = new Map();
  const clone = (x) => structuredClone(x);
  const k = (parts) => parts.join("/");
  const ref = (parts) => ({parts, path: k(parts), id: parts.at(-1),
    collection: (c) => col([...parts, c])});
  const col = (parts) => ({parts, path: k(parts),
    doc: (id) => ref([...parts, id])});
  const get = (r) => {
    if (r.parts.length % 2 !== 0) {
      const prefix = `${k(r.parts)}/`;
      return {docs: [...docs].filter(([key]) => key.startsWith(prefix) &&
        !key.slice(prefix.length).includes("/")).map(([key, value]) => ({
        id: key.slice(prefix.length), data: () => clone(value),
        ref: ref(key.split("/"))})), empty: false};
    }
    const d = docs.get(k(r.parts));
    return {exists: d !== undefined, data: () => d === undefined ? undefined : clone(d)};
  };
  const db = {collection: (name) => col([name]), runTransaction: async (fn) => {
    const writes = [];
    const tx = {
      get: async (r) => get(r),
      create: (r, d) => writes.push(() => {
        if (docs.has(r.path)) throw Error("duplicate"); docs.set(r.path, clone(d));
      }),
      set: (r, d, opts) => writes.push(() => docs.set(r.path,
        opts?.merge ? {...(docs.get(r.path) || {}), ...clone(d)} : clone(d))),
      update: (r, d) => writes.push(() => {
        if (!docs.has(r.path)) throw Error("missing");
        docs.set(r.path, {...docs.get(r.path), ...clone(d)});
      }),
    };
    const result = await fn(tx);
    writes.forEach((write) => write());
    return result;
  }};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "SERVER_TIMESTAMP"};
  const admin = {firestore};
  const token = {uid: UID, role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
    sphotSaSessionExpiresAt: Date.now() + 3600000};
  const makeRows = (content) => [{id: "01", title: "Article", content,
    order: 1, isActive: true}];
  for (const id of ids) {
    const rows = makeRows(`Texte officiel ${id}`);
    docs.set(`legalDocuments/${id}`, {version: "1.1", revision: 0,
      published: true, testOnly: false, chapters: rows});
    docs.set(`legalDocuments/${id}/chapters/01`, {...rows[0]});
  }
  docs.set("legalDocuments/metadata", {legalVersion: "1.1", version: "1.1",
    packPath: "legalPacks/versions/items/1_1",
    lastLegalPackPublicationSource: "legal_pack_five_documents_atomic_v1"});
  const before = makeRows("Texte officiel cgu");
  const after = makeRows("Texte officiel cgu corrige");
  const live = get(db.collection("legalDocuments").doc("cgu"));
  const chapters = get(db.collection("legalDocuments").doc("cgu").collection("chapters"));
  const active = activeSnapshot(live, chapters);
  docs.set("legalEditorialDrafts/cgu", {documentId: "cgu", source: EDITOR_SOURCE,
    status: "validated", draftRevision: 1, chapters: after,
    sourceHash: hash(before), baseHash: active.hash, baseRevision: 0,
    baseVersion: "1.1", reviewedHash: hash(after), reviewedByUid: UID,
    reviewedAt: "SERVER_TIMESTAMP", changeSummary: "Correction juridique"});
  return {admin, token, docs, after};
}
test("publication individuelle atomique : 1.2, archive, cinq textes et communs preserves", async () => {
  const f = fixture();
  const result = await action({admin: f.admin, token: f.token, allowPublish: true,
    input: {action: "publish", documentId: "cgu", confirm: true,
      expectedDraftRevision: 1, expectedHash: hash(f.after)}});
  assert.equal(result.version, "1.2");
  assert.equal(result.revision, 1);
  assert.equal(f.docs.get("legalDocuments/metadata").legalVersion, "1.2");
  assert.equal(f.docs.get("legalDocuments/cgu/chapters/01").content,
    "Texte officiel cgu corrige");
  assert.equal(f.docs.get("legalVersions/1_2").previousVersion, "1.1");
  assert.equal(f.docs.get("legalVersions/cgu_r00000000_legacy").chapters[0].content,
    "Texte officiel cgu");
  assert.equal(f.docs.get("legalVersions/cgu_r00000001_published").chapters[0].content,
    "Texte officiel cgu corrige");
  assert.equal(f.docs.get("legalPacks/versions/items/1_2").documents.length, 5);
  assert.equal(f.docs.get("legalPacks/versions/items/1_2").commonDocuments.length, 2);
  assert.equal(f.docs.get("legalEditorialDrafts/cgu").status, "published");
  for (const id of ids.filter((x) => x !== "cgu")) {
    assert.equal(f.docs.get(`legalDocuments/${id}/chapters/01`).content,
      `Texte officiel ${id}`);
  }
  await assert.rejects(action({admin: f.admin, token: f.token, allowPublish: true,
    input: {action: "publish", documentId: "cgu", confirm: true,
      expectedDraftRevision: 1, expectedHash: hash(f.after)}}),
    {httpStatus: 409});
});
