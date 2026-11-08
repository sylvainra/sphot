"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {legalAction} = require("../legal_admin_publication");
const UID = `sphot-super-admin-${"a".repeat(32)}`;
const NOW = Date.parse("2026-11-06T12:00:00.000Z");

function fixture({published = true, legacy = true} = {}) {
  const docs = new Map();
  const clone = (x) => structuredClone(x);
  const key = (parts) => parts.join("/");
  const mkRef = (parts) => ({id: parts.at(-1), parts,
    collection: (name) => mkCol([...parts, name]),
    get: async () => getDoc(parts)});
  const mkCol = (parts) => ({parts,
    doc: (id) => mkRef([...parts, id]),
    get: async () => getQuery(parts)});
  const getDoc = (parts) => {
    const value = docs.get(key(parts));
    return {exists: value !== undefined,
      data: () => value === undefined ? undefined : clone(value),
      id: parts.at(-1), ref: mkRef(parts)};
  };
  const getQuery = (parts) => ({docs: Array.from(docs.entries())
      .filter(([k]) => k.startsWith(key(parts) + "/") &&
        k.slice(key(parts).length + 1).indexOf("/") < 0)
      .map(([k, data]) => ({id: k.split("/").at(-1),
        data: () => clone(data), ref: mkRef(k.split("/"))}))});
  const db = {collection: (c) => mkCol([c]),
    runTransaction: async (fn) => {
      const changes = [];
      const tx = {
        get: (ref) => {
          if (changes.length) throw Error("Firestore read after write");
          return ref.parts.length % 2 ? getQuery(ref.parts) : getDoc(ref.parts);
        },
        create: (ref, data) => changes.push(() => {
          if (docs.has(key(ref.parts))) throw Error("already_exists");
          docs.set(key(ref.parts), clone(data));
        }),
        set: (ref, data, opts) => changes.push(() => docs.set(key(ref.parts),
          opts?.merge ? {...docs.get(key(ref.parts)), ...clone(data)} : clone(data))),
        update: (ref, data) => changes.push(() => {
          if (!docs.has(key(ref.parts))) throw Error("missing update");
          docs.set(key(ref.parts), {...docs.get(key(ref.parts)), ...clone(data)});
        }),
        delete: (ref) => changes.push(() => docs.delete(key(ref.parts))),
      };
      const result = await fn(tx);
      changes.forEach((apply) => apply());
      return result;
    },
  };
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "SERVER_TIMESTAMP"};
  const admin = {firestore};
  const token = {uid: UID, role: "SPHOT_SUPER_ADMIN",
    sphotSuperAdmin: true, sphotSaSessionExpiresAt: NOW + 3600000};
  const put = (k, val) => docs.set(k, clone(val));
  if (legacy) {
    put("legalDocuments/adminCgv", {version: "1.0", revision: 2,
      published, someOtherField: "keep"});
    put("legalDocuments/adminCgv/chapters/01", {title: "Article A",
      content: "Contenu d'origine A", order: 1, isActive: true});
    put("legalDocuments/adminCgv/chapters/02", {title: "Article B",
      content: "Contenu d'origine B", order: 2, isActive: true});
  }
  const call = (action, extra = {}, t = token) => legalAction({admin,
    token: t, input: {action, documentId: "adminCgv", ...extra}, now: NOW});
  return {call, docs, token, put};
}

test("creation d'un brouillon ne modifie jamais les CGV actives", async () => {
  const h = fixture();
  const before = structuredClone(h.docs.get("legalDocuments/adminCgv"));
  const output = await h.call("create");
  assert.equal(output.draft.status, "draft");
  assert.equal(output.draft.draftRevision, 0);
  assert.equal(output.draft.chapters.length, 2);
  assert.deepEqual(h.docs.get("legalDocuments/adminCgv"), before);
});

test("enregistrer l'article ne touche que legalDocumentDrafts", async () => {
  const h = fixture();
  await h.call("create");
  const output = await h.call("save", {expectedDraftRevision: 0,
    articleId: "02", title: "Article révisé", content: "Nouveau contenu"});
  assert.equal(output.draft.draftRevision, 1);
  assert.equal(output.draft.chapters[1].title, "Article révisé");
  assert.equal(h.docs.get("legalDocuments/adminCgv/chapters/02").title,
      "Article B");
});

test("aucune publication possible sans validation distincte", async () => {
  const h = fixture();
  await h.call("create");
  await assert.rejects(() => h.call("publish", {
    expectedDraftRevision: 0, expectedHash: "0".repeat(64), confirm: true,
  }), /NON_VALIDEE/);
});

test("validation puis publication : archivage et document actif atomiques", async () => {
  const h = fixture();
  await h.call("create");
  await h.call("save", {expectedDraftRevision: 0, articleId: "01",
    title: "Article refondu", content: "Texte contrôlé"});
  const v = await h.call("validate", {expectedDraftRevision: 1});
  assert.equal(v.draft.status, "validated");
  assert.match(v.draft.reviewedHash, /^[a-f0-9]{64}$/);
  assert.equal(h.docs.get("legalDocuments/adminCgv").revision, 2);
  const p = await h.call("publish", {expectedDraftRevision: 1,
    expectedHash: v.draft.reviewedHash, confirm: true});
  assert.equal(p.revision, 3);
  assert.equal(h.docs.get("legalDocuments/adminCgv").someOtherField, "keep");
  assert.equal(h.docs.get("legalDocuments/adminCgv").published, true);
  assert.equal(h.docs.get("legalDocuments/adminCgv/chapters/01").content,
      "Texte contrôlé");
  assert.equal(h.docs.get("legalVersions/adminCgv_r00000003_published").status,
      "Publié");
  assert.equal(h.docs.get("legalVersions/adminCgv_r00000002_legacy")
      .chapters[0].content, "Contenu d'origine A");
  assert.equal(h.docs.get("legalDocumentDrafts/adminCgv").status, "published");
});

test("une edition apres validation invalide celle-ci", async () => {
  const h = fixture();
  await h.call("create");
  const v = await h.call("validate", {expectedDraftRevision: 0});
  const saved = await h.call("save", {expectedDraftRevision: 0,
    articleId: "03", title: "Nouveau", content: "Texte"});
  assert.equal(saved.draft.status, "draft");
  await assert.rejects(() => h.call("publish", {
    expectedDraftRevision: 1, expectedHash: v.draft.reviewedHash, confirm: true,
  }), /NON_VALIDEE/);
});

test("conflit de revision du brouillon refuse", async () => {
  const h = fixture();
  await h.call("create");
  await assert.rejects(() => h.call("save", {expectedDraftRevision: 8,
    articleId: "03", title: "test", content: "test"}), /BROUILLON_MODIFIE/);
});

test("document actif modifie entre brouillon et publication refuse", async () => {
  const h = fixture();
  await h.call("create");
  const v = await h.call("validate", {expectedDraftRevision: 0});
  h.put("legalDocuments/adminCgv/chapters/02", {title: "Modifié hors workflow",
    content: "Texte", order: 2});
  await assert.rejects(() => h.call("publish", {
    expectedDraftRevision: 0, expectedHash: v.draft.reviewedHash, confirm: true,
  }), /NON_VALIDEE/);
});

test("publication sans confirmation explicite refuse", async () => {
  const h = fixture();
  await h.call("create");
  const v = await h.call("validate", {expectedDraftRevision: 0});
  await assert.rejects(() => h.call("publish", {expectedDraftRevision: 0,
    expectedHash: v.draft.reviewedHash, confirm: false}), /EXPLICIT/);
});

test("refus des droits : session non Super Admin", async () => {
  const h = fixture();
  await assert.rejects(() => h.call("create", {}, {...h.token,
    sphotSuperAdmin: false}), /SUPERADMIN_SESSION_NOT_VERIFIED/);
  assert.equal(h.docs.has("legalDocumentDrafts/adminCgv"), false);
});

test("refus des droits : session expiree", async () => {
  const h = fixture();
  await assert.rejects(() => h.call("create", {}, {...h.token,
    sphotSaSessionExpiresAt: NOW - 1}), /SUPERADMIN_SESSION_NOT_VERIFIED/);
});

test("la publication ne peut etre repetee avec la meme revision", async () => {
  const h = fixture();
  await h.call("create");
  const v = await h.call("validate", {expectedDraftRevision: 0});
  await h.call("publish", {expectedDraftRevision: 0,
    expectedHash: v.draft.reviewedHash, confirm: true});
  await assert.rejects(() => h.call("publish", {
    expectedDraftRevision: 0, expectedHash: v.draft.reviewedHash, confirm: true,
  }), /BROUILLON_MODIFIE/);
});

test("CGV non encore publiees restent non publiees avant confirmation", async () => {
  const h = fixture({published: false});
  await h.call("create");
  const v = await h.call("validate", {expectedDraftRevision: 0});
  assert.equal(h.docs.get("legalDocuments/adminCgv").published, false);
  await h.call("publish", {expectedDraftRevision: 0,
    expectedHash: v.draft.reviewedHash, confirm: true});
  assert.equal(h.docs.get("legalDocuments/adminCgv").published, true);
});

test("le circuit ne prend que adminCgv (autres textes preserves)", async () => {
  const h = fixture();
  await assert.rejects(() => h.call("create", {documentId: "sauveteurCgu"}),
      /DOCUMENT_NOT_SUPPORTED/);
});

test("sans document actif : brouillon vide et aucune publication implicite", async () => {
  const h = fixture({legacy: false});
  const c = await h.call("create");
  assert.equal(c.draft.chapters.length, 0);
  assert.equal(h.docs.has("legalDocuments/adminCgv"), false);
  await assert.rejects(() => h.call("validate", {expectedDraftRevision: 0}),
      /ARTICLES_INCOMPLETS/);
  await h.call("save", {expectedDraftRevision: 0,
    articleId: "01", title: "Initial", content: "Texte initial"});
  const v = await h.call("validate", {expectedDraftRevision: 1});
  await h.call("publish", {expectedDraftRevision: 1,
    expectedHash: v.draft.reviewedHash, confirm: true});
  assert.equal(h.docs.get("legalDocuments/adminCgv").revision, 0);
  assert.equal(h.docs.get("legalDocuments/adminCgv").published, true);
});

test("double ouverture du meme brouillon sans duplication", async () => {
  const h = fixture();
  const a = await h.call("create");
  const b = await h.call("create");
  assert.deepEqual(a.draft.chapters, b.draft.chapters);
  assert.equal(h.docs.size, 4);
});

test("empreinte differente lors de la publication refuse", async () => {
  const h = fixture();
  await h.call("create");
  await h.call("validate", {expectedDraftRevision: 0});
  await assert.rejects(() => h.call("publish", {
    expectedDraftRevision: 0, expectedHash: "f".repeat(64), confirm: true,
  }), /DIFFERENTE/);
});

test("archive existante de revision publiee refuse nouvelle publication", async () => {
  const h = fixture();
  await h.call("create");
  const v = await h.call("validate", {expectedDraftRevision: 0});
  h.put("legalVersions/adminCgv_r00000003_published", {version: "autre"});
  await assert.rejects(() => h.call("publish", {
    expectedDraftRevision: 0, expectedHash: v.draft.reviewedHash,
    confirm: true,
  }), /REVISION_DEJA_PUBLIEE/);
});

test("publication preserve articles dans parent et sous-collection", async () => {
  const h = fixture();
  await h.call("create");
  const v = await h.call("validate", {expectedDraftRevision: 0});
  await h.call("publish", {expectedDraftRevision: 0,
    expectedHash: v.draft.reviewedHash, confirm: true});
  const parent = h.docs.get("legalDocuments/adminCgv");
  assert.equal(parent.chapters.length, 2);
  assert.equal(parent.chapters[0].content,
      h.docs.get("legalDocuments/adminCgv/chapters/01").content);
});
