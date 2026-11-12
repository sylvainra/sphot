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
  let generatedDocumentId = 0;
  const ref = (parts) => ({parts, path: k(parts), id: parts.at(-1),
    get: async () => get(ref(parts)),
    collection: (c) => col([...parts, c])});
  const col = (parts) => ({parts, path: k(parts),
    doc: (id) => ref([...parts, id || `auto-${++generatedDocumentId}`])});
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

test("nouvelles CGU ADMIN et PUBLICITAIRE : import approuvé et publication", async () => {
  const f = fixture();
  for (const [id, count] of [["adminCgu", 14], ["advertiserCgu", 12]]) {
    const created = await action({admin: f.admin, token: f.token,
      input: {action: "create", documentId: id}});
    assert.equal(created.draft.chapters.length, count);
    assert.equal(created.draft.draftRevision, 0);
    const reviewed = await action({admin: f.admin, token: f.token,
      input: {action: "validate", documentId: id, expectedDraftRevision: 0,
        confirm: true}});
    assert.equal(reviewed.draft.status, "validated");
    const published = await action({admin: f.admin, token: f.token,
      allowPublish: true, input: {action: "publish", documentId: id,
        expectedDraftRevision: 0, expectedHash: hash(created.draft.chapters),
        confirm: true}});
    assert.equal(published.published, true);
    assert.equal(f.docs.get(`legalDocuments/${id}`).published, true);
    assert.equal(f.docs.get(`legalDocuments/${id}`).chapters.length, count);
    assert.equal(f.docs.get(`legalDocuments/${id}/chapters/01`).isActive, true);
  }
  assert.equal(f.docs.get("legalDocuments/cgu").chapters.length, 1);
  assert.equal(f.docs.get("legalDocuments/cgu").chapters[0].content,
    "Texte officiel cgu");
  assert.equal(f.docs.get("legalPacks/versions/items/1_3").commonDocuments.length, 4);
});

test("mise à niveau de CGU SAUVETEUR existantes : historique conservé", async () => {
  const f = fixture();
  const created = await action({admin: f.admin, token: f.token,
    input: {action: "create", documentId: "sauveteurCgu"}});
  assert.equal(created.draft.chapters.length, 8);
  const approved = await action({admin: f.admin, token: f.token,
    input: {action: "validate", documentId: "sauveteurCgu",
      expectedDraftRevision: 0, confirm: true}});
  assert.equal(approved.draft.status, "validated");
  const published = await action({admin: f.admin, token: f.token,
    allowPublish: true, input: {action: "publish",
      documentId: "sauveteurCgu", expectedDraftRevision: 0,
      expectedHash: hash(created.draft.chapters), confirm: true}});
  assert.equal(published.published, true);
  assert.equal(f.docs.get("legalDocuments/sauveteurCgu").chapters.length, 8);
  assert.equal(f.docs.get("legalVersions/sauveteurCgu_r00000000_legacy")
      .chapters[0].content, "Texte officiel sauveteurCgu");
  const reloaded = await action({admin: f.admin, token: f.token,
    input: {action: "create", documentId: "sauveteurCgu"}});
  assert.equal(reloaded.draft.chapters.length, 8);
  assert.equal(f.docs.get("legalEditorialDrafts/sauveteurCgu").approvedImport,
    false);
});


test("cycle complet : modifier puis publier une CGU ADMIN/ANNONCEUR entraine une nouvelle acceptation", async () => {
  const professional = require("../professional_legal_acceptance");
  const f = fixture();
  const actors = [
    ["adminCgu", 14, {uid: "test-admin", role: "ADMIN",
      adminUid: "test-admin"}],
    ["advertiserCgu", 12, {uid: "test-annonceur", role: "ANNONCEUR",
      advertiserRequestId: "request-test"}],
  ];

  for (const [documentId, expected, account] of actors) {
    // 1. On importe et on publie le document approuvé dans la base simulée.
    const imported = await action({admin: f.admin, token: f.token,
      input: {action: "create", documentId}});
    assert.equal(imported.draft.chapters.length, expected);
    await action({admin: f.admin, token: f.token,
      input: {action: "validate", documentId, expectedDraftRevision: 0,
        confirm: true}});
    await action({admin: f.admin, token: f.token, allowPublish: true,
      input: {action: "publish", documentId, expectedDraftRevision: 0,
        expectedHash: hash(imported.draft.chapters), confirm: true}});

    // 2. Une première acceptation correspond à la version publiée.
    const before = await professional.action({admin: f.admin, token: account,
      input: {action: "status"}});
    assert.equal(before.published, true);
    assert.equal(before.required, true);
    assert.equal(before.documentId, documentId);
    await professional.action({admin: f.admin, token: account,
      input: {action: "accept", versionId: before.versionId, accepted: true}});
    const accepted = await professional.action({admin: f.admin, token: account,
      input: {action: "status"}});
    assert.equal(accepted.required, false);
    const previousVersion = f.docs.get(`legalDocuments/${documentId}`);
    const previousText = previousVersion.chapters[0].content;

    // 3. Une modification n'affecte PAS le texte publié ni la version acceptée.
    const opened = await action({admin: f.admin, token: f.token,
      input: {action: "create", documentId}});
    assert.equal(opened.draft.draftRevision, 0);
    const changed = await action({admin: f.admin, token: f.token,
      input: {action: "save", documentId, expectedDraftRevision: 0,
        articleId: "01", title: opened.draft.chapters[0].title,
        content: previousText + " — MODIFICATION TEST ISOLÉE",
        changeSummary: "Test automatique de propagation"}});
    assert.equal(changed.draft.draftRevision, 1);
    assert.equal(changed.draft.status, "draft");
    assert.equal(f.docs.get(`legalDocuments/${documentId}`).chapters[0].content,
      previousText);
    assert.equal((await professional.action({admin: f.admin, token: account,
      input: {action: "status"}})).required, false);

    // 4. La validation ne déclenche toujours pas de réacceptation.
    const reviewed = await action({admin: f.admin, token: f.token,
      input: {action: "validate", documentId, expectedDraftRevision: 1,
        confirm: true}});
    assert.equal(reviewed.draft.status, "validated");
    assert.equal((await professional.action({admin: f.admin, token: account,
      input: {action: "status"}})).required, false);

    // 5. Seule la publication déclenche la nouvelle version et son acceptation.
    const next = await action({admin: f.admin, token: f.token,
      allowPublish: true, input: {action: "publish", documentId,
        expectedDraftRevision: 1, expectedHash: hash(changed.draft.chapters),
        confirm: true}});
    assert.equal(next.published, true);
    const after = await professional.action({admin: f.admin, token: account,
      input: {action: "status"}});
    assert.equal(after.published, true);
    assert.equal(after.required, true);
    assert.notEqual(after.versionId, before.versionId);
    await assert.rejects(() => professional.action({admin: f.admin,
      token: account, input: {action: "accept",
        versionId: before.versionId, accepted: true}}),
    {httpStatus: 409});
    await professional.action({admin: f.admin, token: account,
      input: {action: "accept", versionId: after.versionId, accepted: true}});
    assert.equal((await professional.action({admin: f.admin, token: account,
      input: {action: "status"}})).required, false);
    const prefix =
      `professionalLegalAcceptances/${account.role}_${account.uid}/history/`;
    assert.equal([...f.docs.keys()].filter((key) =>
      key.startsWith(prefix)).length, 2);
    assert.equal(f.docs.get(`legalDocuments/${documentId}`).chapters.length,
      expected);
    assert.ok([...f.docs.keys()].some((key) =>
      key.startsWith(`legalVersions/${documentId}_r`) &&
      key.includes("_published")));
  }
  assert.equal(f.docs.get("legalDocuments/cgu").chapters[0].content,
    "Texte officiel cgu");
});


test("la modification des CGU d'un acteur ne fait pas revalider celles des autres", async () => {
  const professional = require("../professional_legal_acceptance");
  const f = fixture();
  const actors = [
    ["adminCgu", {uid: "indep-admin", adminUid: "indep-admin", role: "ADMIN"}],
    ["advertiserCgu", {uid: "indep-adv", advertiserRequestId: "r1",
      role: "ANNONCEUR"}],
  ];

  // Les deux documents doivent être déjà publiés et acceptés.
  for (const [documentId, token] of actors) {
    const initial = await action({admin: f.admin, token: f.token,
      input: {action: "create", documentId}});
    await action({admin: f.admin, token: f.token,
      input: {action: "validate", documentId, confirm: true,
        expectedDraftRevision: 0}});
    await action({admin: f.admin, token: f.token, allowPublish: true,
      input: {action: "publish", documentId, confirm: true,
        expectedDraftRevision: 0, expectedHash: hash(initial.draft.chapters)}});
    const status = await professional.action({admin: f.admin, token,
      input: {action: "status"}});
    await professional.action({admin: f.admin, token,
      input: {action: "accept", versionId: status.versionId, accepted: true}});
  }

  const advertiserOriginal = (await professional.action({
    admin: f.admin, token: actors[1][1], input: {action: "status"},
  })).versionId;

  // Publication de la CGU ADMIN uniquement.
  const adminDraft = await action({admin: f.admin, token: f.token,
    input: {action: "create", documentId: "adminCgu"}});
  const changed = await action({admin: f.admin, token: f.token,
    input: {action: "save", documentId: "adminCgu",
      expectedDraftRevision: 0, articleId: "01",
      title: adminDraft.draft.chapters[0].title,
      content: adminDraft.draft.chapters[0].content + " TEST ADMIN",
      changeSummary: "Isolation entre publics"}});
  await action({admin: f.admin, token: f.token, input: {
    action: "validate", documentId: "adminCgu",
    expectedDraftRevision: 1, confirm: true,
  }});
  await action({admin: f.admin, token: f.token, allowPublish: true,
    input: {action: "publish", documentId: "adminCgu",
      expectedDraftRevision: 1, confirm: true,
      expectedHash: hash(changed.draft.chapters)}});

  const adminStatus = await professional.action({admin: f.admin,
    token: actors[0][1], input: {action: "status"}});
  const advertiserStatus = await professional.action({admin: f.admin,
    token: actors[1][1], input: {action: "status"}});
  assert.equal(adminStatus.required, true);
  assert.equal(advertiserStatus.required, false);
  assert.equal(advertiserStatus.versionId, advertiserOriginal);
  assert.equal(f.docs.get("legalDocuments/cgu").chapters[0].content,
    "Texte officiel cgu");
});
