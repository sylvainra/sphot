"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const editor = require("../legal_document_editor");
const initialPack = require("../legal_pack_publication");

class Ref {
  constructor(db, p) {this.db = db; this.path = p; this.id = p.split("/").at(-1);}
  collection(name) {return new Col(this.db, this.path + "/" + name);}
  async get() {return this.db.snapshot(this.path);}
}
class Col {
  constructor(db, p) {this.db = db; this.path = p;}
  doc(id) {return new Ref(this.db, this.path + "/" + id);}
  async get() {return this.db.query(this.path);}
}
class FakeDb {
  constructor() {this.docs = new Map();}
  collection(name) {return new Col(this, name);}
  snapshot(p) {
    const value = this.docs.get(p);
    return {exists: value !== undefined, id: p.split("/").at(-1),
      data: () => value === undefined ? undefined : structuredClone(value)};
  }
  query(p) {
    const docs = [];
    for (const key of this.docs.keys()) {
      if (key.startsWith(p + "/") && key.slice(p.length + 1).split("/").length === 1) {
        docs.push({...this.snapshot(key), id: key.split("/").at(-1)});
      }
    }
    docs.sort((a, b) => a.id.localeCompare(b.id));
    return {docs, empty: docs.length === 0};
  }
  async runTransaction(callback) {
    const writes = [];
    const tx = {get: (ref) => ref.get(),
      set: (ref, data, opts) => writes.push({op: "set", ref, data, opts}),
      update: (ref, data) => writes.push({op: "update", ref, data}),
      create: (ref, data) => writes.push({op: "create", ref, data}),
      delete: (ref) => writes.push({op: "delete", ref})};
    const result = await callback(tx);
    const copy = new Map(this.docs);
    for (const {op, ref, data, opts} of writes) {
      if (op === "create" && copy.has(ref.path)) throw Error("ALREADY_EXISTS");
      if (op === "update" && !copy.has(ref.path)) throw Error("NOT_FOUND");
      if (op === "delete") copy.delete(ref.path);
      else if (op === "update" || opts?.merge) {
        copy.set(ref.path, {...copy.get(ref.path), ...structuredClone(data)});
      } else copy.set(ref.path, structuredClone(data));
    }
    this.docs = copy;
    return result;
  }
}
function fixture() {
  const db = new FakeDb();
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "SERVER_TIMESTAMP"};
  const admin = {firestore};
  const now = Date.now();
  const token = {role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
    uid: "sphot-super-admin-" + "a".repeat(32),
    sphotSaSessionExpiresAt: now + 120000};
  db.docs.set("legalDocuments/metadata", {
    version: "1.1", legalVersion: "1.1",
    packPath: "legalPacks/versions/items/1_1",
    lastLegalPackPublicationSource: "legal_pack_five_documents_atomic_v1",
  });
  for (const [id, label] of Object.entries(editor.SPECIFICATIONS)) {
    const chapterId = id === "rgpdNotice" || id === "privacyPolicy" ?
      "article_contexte" : "01";
    const chapter = {id: chapterId, title: label,
      content: `Texte déjà publié ${id}`, order: 1, isActive: true};
    db.docs.set(`legalDocuments/${id}`, {
      version: "1.1", revision: 0, published: true, testOnly: false,
      chapters: [chapter], publicationSource: "legal_pack_five_documents_atomic_v1",
    });
    db.docs.set(`legalDocuments/${id}/chapters/${chapterId}`, chapter);
  }
  const invoke = (input, options = {}) => editor.action({admin, token,
    input, now, ...options});
  return {db, admin, token, now, invoke};
}

test("sept documents uniques, souscriptions ni paiements non concernés", () => {
  assert.deepEqual(Object.keys(editor.SPECIFICATIONS).sort(), [
    "cgu", "adminCgv", "advertiserCgv", "sauveteurCgu",
    "sauveteurCharter", "rgpdNotice", "privacyPolicy",
  ].sort());
  assert.throws(() => editor.validateInput({action: "status", documentId: "metadata"}));
  assert.throws(() => editor.validateInput({action: "save", documentId: "cgu",
    expectedDraftRevision: 0, articleId: "01", title: "A", content: "B",
    changeSummary: "C", admin: true}));
});

test("sauvegarde et validation restent dans le brouillon distinct, sans publication", async () => {
  const {db, invoke} = fixture();
  const activeBefore = JSON.stringify(db.docs.get("legalDocuments/adminCgv"));
  const original = await invoke({action: "create", documentId: "adminCgv"});
  assert.equal(original.draft.draftRevision, 0);
  const saved = await invoke({action: "save", documentId: "adminCgv",
    expectedDraftRevision: 0, articleId: "01", title: "CGV revue",
    content: "Texte juridique actualisé", changeSummary: "Révision de la clause"});
  assert.equal(saved.draft.draftRevision, 1);
  await assert.rejects(invoke({action: "save", documentId: "adminCgv",
    expectedDraftRevision: 0, articleId: "01", title: "Ancien état",
    content: "Ne doit pas passer", changeSummary: "Conflit"}));
  const validated = await invoke({action: "validate", documentId: "adminCgv",
    expectedDraftRevision: 1, confirm: true});
  assert.equal(validated.draft.status, "validated");
  await assert.rejects(invoke({action: "publish", documentId: "adminCgv",
    expectedDraftRevision: 1, expectedHash: validated.draft.reviewedHash,
    confirm: true}), /PUBLICATION_NON_ACTIVEE/);
  assert.equal(JSON.stringify(db.docs.get("legalDocuments/adminCgv")), activeBefore);
  assert.equal(db.docs.has("legalVersions/1_2"), false);
  assert.equal(db.docs.has("legalPacks/versions/items/1_2"), false);
});

test("publication autorisée explicitement : archive, version globale, documents communs inchangés", async () => {
  const {db, invoke} = fixture();
  const beforePrivacy = JSON.stringify(db.docs.get("legalDocuments/privacyPolicy"));
  await invoke({action: "create", documentId: "sauveteurCgu"});
  await invoke({action: "save", documentId: "sauveteurCgu",
    expectedDraftRevision: 0, articleId: "01", title: "CGU sauveteur actualisées",
    content: "Texte sauvegardé et relu", changeSummary: "Précision métier"});
  const reviewed = await invoke({action: "validate", documentId: "sauveteurCgu",
    expectedDraftRevision: 1, confirm: true});
  const result = await invoke({action: "publish", documentId: "sauveteurCgu",
    expectedDraftRevision: 1, expectedHash: reviewed.draft.reviewedHash,
    confirm: true}, {allowPublish: true});
  assert.equal(result.version, "1.2");
  assert.equal(result.revision, 1);
  assert.equal(db.docs.get("legalDocuments/metadata").legalVersion, "1.2");
  assert.equal(db.docs.get("legalVersions/1_2").documentsModified[0], "CGU — SPHOT SAUVETEUR");
  assert.equal(db.docs.get("legalPacks/versions/items/1_2").documents.length, 5);
  assert.equal(db.docs.get("legalPacks/versions/items/1_2").commonDocuments.length, 2);
  assert.equal(db.docs.has("legalVersions/sauveteurCgu_r00000000_legacy"), true);
  assert.equal(db.docs.get("legalEditorialDrafts/sauveteurCgu").status, "published");
  assert.equal(JSON.stringify(db.docs.get("legalDocuments/privacyPolicy")), beforePrivacy);
});

test("RGPD et confidentialité : IDs historiques conservés, version propre", async () => {
  const {db, invoke} = fixture();
  const rgpdBefore = JSON.stringify(db.docs.get("legalDocuments/rgpdNotice"));
  const draft = await invoke({action: "create", documentId: "privacyPolicy"});
  assert.equal(draft.draft.chapters[0].id, "article_contexte");
  await invoke({action: "save", documentId: "privacyPolicy",
    expectedDraftRevision: 0, articleId: "article_contexte",
    title: "Confidentialité adaptée", content: "Texte de la politique",
    changeSummary: "Clarification des droits"});
  const verified = await invoke({action: "validate", documentId: "privacyPolicy",
    expectedDraftRevision: 1, confirm: true});
  await invoke({action: "publish", documentId: "privacyPolicy",
    expectedDraftRevision: 1, expectedHash: verified.draft.reviewedHash,
    confirm: true}, {allowPublish: true});
  assert.equal(db.docs.get("legalDocuments/privacyPolicy").revision, 1);
  assert.equal(JSON.stringify(db.docs.get("legalDocuments/rgpdNotice")), rgpdBefore);
});

test("conflit sur la version active : aucune mutation, et rôle non autorisé rejeté", async () => {
  const {db, invoke, admin, now, token} = fixture();
  await assert.rejects(editor.action({admin, token: {...token, role: "ADMIN"},
    input: {action: "create", documentId: "cgu"}, now}));
  await invoke({action: "create", documentId: "cgu"});
  await invoke({action: "save", documentId: "cgu", expectedDraftRevision: 0,
    articleId: "01", title: "CGU corrigées", content: "Texte modifié",
    changeSummary: "Correction"});
  const verified = await invoke({action: "validate", documentId: "cgu",
    expectedDraftRevision: 1, confirm: true});
  db.docs.set("legalDocuments/cgu", {...db.docs.get("legalDocuments/cgu"), revision: 5});
  await assert.rejects(invoke({action: "publish", documentId: "cgu",
    expectedDraftRevision: 1, expectedHash: verified.draft.reviewedHash,
    confirm: true}, {allowPublish: true}), /VERSION_PUBLIEE_MODIFIEE/);
  assert.equal(db.docs.has("legalVersions/1_2"), false);
});

test("avant le premier pack, brouillon éditable mais publication bloquée", async () => {
  const {db, invoke} = fixture();
  db.docs.set("legalDocuments/metadata", {version: "1.0"});
  const spec = initialPack.DOCUMENTS.find((item) => item.id === "cgu");
  const source = fs.readFileSync(path.resolve(__dirname,
      "../../assets/legal/test_corpus/cgu_grand_public.md"), "utf8");
  const headings = [...source.matchAll(/^##\s+(.+)$/gm)];
  const chapters = headings.map((match, i) => ({
    id: String(i + 1).padStart(2, "0"), title: match[1],
    content: source.slice(match.index + match[0].length,
        headings[i + 1]?.index ?? source.length).trim(),
    order: i + 1, isActive: true,
  }));
  const activeParent = db.snapshot("legalDocuments/cgu");
  const activeSub = db.query("legalDocuments/cgu/chapters");
  const active = initialPack.activeSnapshot(activeParent, activeSub);
  db.docs.set("legalDocumentDrafts/cgu", {
    documentId: "cgu", importSource: "sphot_c4_validated_legal_import_20261106_v1",
    sourceProject: "sphot-c4-test-20261029", sourceDocumentId: spec.source,
    sourceVersion: "1.0", sourceRevision: 1, importedC4Hash: spec.sha,
    draftRevision: 0, baseRevision: active.revision, baseHash: active.hash,
    chapters,
  });
  const created = await invoke({action: "create", documentId: "cgu"});
  assert.equal(created.draft.chapters.length, 13);
  assert.equal(created.draft.sourcePendingInitialPublication, true);
  assert.equal(db.docs.get("legalDocumentDrafts/cgu").draftRevision, 0);
  await invoke({action: "save", documentId: "cgu", expectedDraftRevision: 0,
    articleId: "01", title: "CGU revues", content: "Brouillon post-publication",
    changeSummary: "Modification ultérieure"});
  const validated = await invoke({action: "validate", documentId: "cgu",
    expectedDraftRevision: 1, confirm: true});
  await assert.rejects(invoke({action: "publish", documentId: "cgu",
    expectedDraftRevision: 1, expectedHash: validated.draft.reviewedHash,
    confirm: true}, {allowPublish: true}), /PUBLIER_D_ABORD_LES_CINQ_TEXTES/);
  assert.equal(db.docs.get("legalDocuments/metadata").version, "1.0");

  // Simuler la publication initiale intacte des cinq textes par le circuit
  // existant. Le brouillon editorial reste isole et devient publiable ensuite.
  db.docs.set("legalDocuments/metadata", {version: "1.1", legalVersion: "1.1",
    packPath: "legalPacks/versions/items/1_1",
    lastLegalPackPublicationSource: "legal_pack_five_documents_atomic_v1"});
  db.docs.set("legalDocuments/cgu", {version: "1.1", revision: 1,
    published: true, testOnly: false, chapters});
  for (const row of chapters) {
    db.docs.set(`legalDocuments/cgu/chapters/${row.id}`, row);
  }
  const later = await invoke({action: "publish", documentId: "cgu",
    expectedDraftRevision: 1, expectedHash: validated.draft.reviewedHash,
    confirm: true}, {allowPublish: true});
  assert.equal(later.version, "1.2");
  assert.equal(db.docs.get("legalDocumentDrafts/cgu").draftRevision, 0);
  assert.equal(db.docs.get("legalDocuments/cgu").chapters[0].title, "CGU revues");
});
