/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Circuit CGV ADMIN : BROUILLON -> VALIDATION -> PUBLICATION.
// Aucune fonction exportee vers Firebase sans opt-in explicite dans index.js.
// Jamais de commande, de facture, de paiement ni d'activation commerciale.
const crypto = require("node:crypto");

const DOCUMENT_ID = "adminCgv";
const DRAFT_COLLECTION = "legalDocumentDrafts";
const HISTORY_COLLECTION = "legalVersions";
const MAX_CHAPTERS = 60;
const MAX_CONTENT = 40000;
const ORIGINS = ["https://sphot.app", "https://www.sphot.app",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com"];

function error(status, message) {
  const e = new Error(message);
  e.httpStatus = status;
  return e;
}
function clean(x) {return typeof x === "string" ? x.trim() : "";}
function fingerprint(x) {
  return crypto.createHash("sha256").update(JSON.stringify(x)).digest("hex");
}
function assertReviewer(token, now = Date.now()) {
  if (!token || token.role !== "SPHOT_SUPER_ADMIN" ||
      token.sphotSuperAdmin !== true ||
      !/^sphot-super-admin-[a-f0-9]{32}$/.test(clean(token.uid)) ||
      !Number.isSafeInteger(token.sphotSaSessionExpiresAt) ||
      token.sphotSaSessionExpiresAt <= now ||
      token.sphotSaSessionExpiresAt > now + 7200000) {
    throw error(403, "SUPERADMIN_SESSION_NOT_VERIFIED");
  }
  return token.uid;
}
function assertDocId(id) {
  if (id !== DOCUMENT_ID) {
    throw error(400, "DOCUMENT_NOT_SUPPORTED");
  }
}
function canonicalChapters(raw, allowEmpty = false) {
  if (!Array.isArray(raw) || raw.length > MAX_CHAPTERS ||
      (!allowEmpty && raw.length === 0)) {
    throw error(409, "ARTICLES_INCOMPLETS");
  }
  const ids = new Set();
  const chapters = raw.map((x, index) => {
    const id = clean(x?.id);
    const title = clean(x?.title || x?.titre);
    const content = clean(x?.content || x?.texte);
    if (!/^[A-Za-z0-9_-]{2,64}$/.test(id) || ids.has(id) ||
        !title || title.length > 240 || !content ||
        content.length > MAX_CONTENT) {
      throw error(409, `ARTICLE_INVALIDE_${index + 1}`);
    }
    ids.add(id);
    return {id, title, content, order: index + 1, isActive: true};
  });
  if (Buffer.byteLength(JSON.stringify(chapters), "utf8") > 700000) {
    throw error(409, "DOCUMENT_TROP_VOLUMINEUX");
  }
  return chapters;
}
function publishedSnapshot(meta, chapters) {
  const data = meta.exists ? meta.data() || {} : {};
  const version = clean(data.version) || "1.0";
  const revision = Number.isSafeInteger(data.revision) &&
      data.revision >= 0 ? data.revision : -1;
  // La seule source de verite du statut est published === true.
  const published = data.published === true && data.testOnly !== true;
  const parentRows = Array.isArray(data.chapters) ?
    data.chapters.map((value, index) => ({...value,
      id: clean(value?.id) || String(index + 1).padStart(2, "0")})) : [];
  const source = (chapters.docs.length > 0 ?
    chapters.docs.map((doc) => ({...doc.data(), id: doc.id})) : parentRows)
      .sort((a, b) => String(a.id).localeCompare(String(b.id)));
  const normalized = source.map((x, index) => ({
    id: x.id,
    title: clean(x.title || x.titre),
    content: clean(x.content || x.texte),
    order: index + 1,
    isActive: x.isActive !== false,
  }));
  return {exists: meta.exists, version, revision, published,
    chapters: normalized,
    hash: fingerprint({version, revision, published, chapters: normalized})};
}
function validateInput(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw error(400, "REQUEST_INVALID");
  }
  assertDocId(input.documentId);
  const actions = ["status", "create", "save", "validate", "publish"];
  if (!actions.includes(input.action)) {
    throw error(400, "ACTION_NOT_SUPPORTED");
  }
  const sets = {
    status: ["action", "documentId"],
    create: ["action", "documentId"],
    save: ["action", "documentId", "expectedDraftRevision", "articleId",
      "title", "content"],
    validate: ["action", "documentId", "expectedDraftRevision"],
    publish: ["action", "documentId", "expectedDraftRevision",
      "expectedHash", "confirm"],
  };
  if (Object.keys(input).sort().join("|") !== sets[input.action].sort().join("|")) {
    throw error(400, "FIELDS_NOT_ALLOWED");
  }
  if (["save", "validate", "publish"].includes(input.action) &&
      (!Number.isSafeInteger(input.expectedDraftRevision) ||
       input.expectedDraftRevision < 0)) {
    throw error(400, "DRAFT_REVISION_INVALID");
  }
  if (input.action === "save" &&
      (!/^[A-Za-z0-9_-]{2,64}$/.test(clean(input.articleId)) ||
       !clean(input.title) || clean(input.title).length > 240 ||
       !clean(input.content) || clean(input.content).length > MAX_CONTENT)) {
    throw error(400, "ARTICLE_INVALID");
  }
  if (input.action === "publish" &&
      (input.confirm !== true || !/^[a-f0-9]{64}$/.test(clean(input.expectedHash)))) {
    throw error(400, "EXPLICIT_PUBLICATION_CONFIRMATION_REQUIRED");
  }
  return input;
}
function summaryOfDraft(snapshot) {
  if (!snapshot.exists) return null;
  const d = snapshot.data() || {};
  return {documentId: DOCUMENT_ID, status: d.status,
    draftRevision: d.draftRevision,
    chapters: d.chapters || [],
    reviewedHash: d.reviewedHash || "",
    baseHash: d.baseHash || "",
    baseRevision: d.baseRevision};
}
function draftRef(db) {return db.collection(DRAFT_COLLECTION).doc(DOCUMENT_ID);}
function legalRef(db) {return db.collection("legalDocuments").doc(DOCUMENT_ID);}
function stamp(admin) {return admin.firestore.FieldValue.serverTimestamp();}
function draftCheck(snap, expectedRevision) {
  const d = snap.exists ? snap.data() || {} : {};
  if (!snap.exists || d.documentId !== DOCUMENT_ID ||
      d.status === "published" ||
      !Number.isSafeInteger(d.draftRevision) ||
      d.draftRevision !== expectedRevision ||
      !Array.isArray(d.chapters)) {
    throw error(409, "BROUILLON_MODIFIE_RECHARGEZ");
  }
  return d;
}
function versionId(revision, state) {
  return `adminCgv_r${String(revision).padStart(8, "0")}_${state}`;
}

async function legalAction({admin, token, input, now = Date.now()}) {
  const uid = assertReviewer(token, now);
  const p = validateInput(input);
  const db = admin.firestore();
  const live = legalRef(db);
  const draft = draftRef(db);
  const chaptersRef = live.collection("chapters");
  if (p.action === "status") {
    const [meta, rows, work] = await Promise.all([
      live.get(), chaptersRef.get(), draft.get(),
    ]);
    const active = publishedSnapshot(meta, rows);
    return {published: {version: active.version, revision: active.revision,
      published: active.published, chaptersCount: active.chapters.length},
    draft: summaryOfDraft(work)};
  }
  if (p.action === "create") {
    return db.runTransaction(async (tx) => {
      const [meta, rows, work] = await Promise.all([
        tx.get(live), tx.get(chaptersRef), tx.get(draft),
      ]);
      const active = publishedSnapshot(meta, rows);
      if (work.exists && work.data()?.status !== "published") {
        if (work.data()?.baseHash !== active.hash) {
          throw error(409, "VERSION_ACTIVE_MODIFIEE_REDEMARREZ");
        }
        return {draft: summaryOfDraft(work)};
      }
      const copied = canonicalChapters(active.chapters, true);
      const payload = {documentId: DOCUMENT_ID, status: "draft",
        baseHash: active.hash, baseRevision: active.revision,
        draftRevision: 0, chapters: copied, reviewedHash: "",
        reviewedByUid: null, reviewedAt: null,
        createdByUid: uid, createdAt: stamp(admin),
        updatedAt: stamp(admin), updatedByUid: uid};
      tx.set(draft, payload);
      return {draft: {...payload, createdAt: null, updatedAt: null}};
    });
  }
  if (p.action === "save") {
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(draft);
      const d = draftCheck(snap, p.expectedDraftRevision);
      const rows = canonicalChapters(d.chapters, true);
      const position = rows.findIndex((x) => x.id === p.articleId);
      const update = {id: p.articleId, title: clean(p.title),
        content: clean(p.content), order: position < 0 ? rows.length + 1 : position + 1,
        isActive: true};
      if (position < 0) rows.push(update); else rows[position] = update;
      const next = canonicalChapters(rows);
      tx.update(draft, {chapters: next, status: "draft",
        draftRevision: d.draftRevision + 1,
        reviewedHash: "", reviewedByUid: null, reviewedAt: null,
        updatedAt: stamp(admin), updatedByUid: uid});
      return {draft: {documentId: DOCUMENT_ID, status: "draft",
        draftRevision: d.draftRevision + 1, chapters: next,
        reviewedHash: "", baseHash: d.baseHash,
        baseRevision: d.baseRevision}};
    });
  }
  if (p.action === "validate") {
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(draft);
      const d = draftCheck(snap, p.expectedDraftRevision);
      const rows = canonicalChapters(d.chapters);
      const hash = fingerprint(rows);
      tx.update(draft, {status: "validated", reviewedHash: hash,
        reviewedByUid: uid, reviewedAt: stamp(admin),
        updatedAt: stamp(admin), updatedByUid: uid});
      return {draft: {documentId: DOCUMENT_ID, status: "validated",
        draftRevision: d.draftRevision, chapters: rows,
        reviewedHash: hash, baseHash: d.baseHash,
        baseRevision: d.baseRevision}};
    });
  }
  // Publication transactionnelle et versionnee : lecture de toutes les pieces
  // avant toute ecriture. Seul un brouillon valide et inchange peut sortir.
  return db.runTransaction(async (tx) => {
    const [meta, currentRows, work] = await Promise.all([
      tx.get(live), tx.get(chaptersRef), tx.get(draft),
    ]);
    const active = publishedSnapshot(meta, currentRows);
    const d = draftCheck(work, p.expectedDraftRevision);
    if (d.status !== "validated" || !clean(d.reviewedByUid) ||
        !d.reviewedAt || active.hash !== d.baseHash ||
        active.revision !== d.baseRevision) {
      throw error(409, "PUBLICATION_NON_VALIDEE_OU_VERSION_MODIFIEE");
    }
    const rows = canonicalChapters(d.chapters);
    const digest = fingerprint(rows);
    if (digest !== d.reviewedHash || digest !== p.expectedHash) {
      throw error(409, "PUBLICATION_CGV_DIFFERENTE_DU_TEXTE_VALIDE");
    }
    const nextRevision = active.revision < 0 ? 0 : active.revision + 1;
    const historicalRef = db.collection(HISTORY_COLLECTION)
        .doc(versionId(nextRevision, "published"));
    const predecessorRef = active.exists ? db.collection(HISTORY_COLLECTION)
        .doc(versionId(active.revision, "legacy")) : null;
    // Lire les archives avant toute ecriture de transaction Firestore.
    const [previous, publishedHistory] = await Promise.all([
      predecessorRef ? tx.get(predecessorRef) : Promise.resolve(null),
      tx.get(historicalRef),
    ]);
    if (publishedHistory.exists) {
      throw error(409, "REVISION_DEJA_PUBLIEE");
    }
    // Toutes les versions historisees sont create-only, jamais ecrasees.
    if (predecessorRef && previous.exists &&
        previous.data()?.fingerprint !== active.hash) {
      throw error(409, "HISTORIQUE_ANTERIEUR_INCOHERENT");
    }
    if (predecessorRef && !previous.exists) {
      tx.create(predecessorRef, {
          documentId: DOCUMENT_ID, version: active.version,
          revision: active.revision,
          status: active.published ? "Publié (avant migration)" :
            "Document antérieur non publié",
          chapters: active.chapters, fingerprint: active.hash,
          originalPublishedAt: meta.data()?.publishedAt || null,
          originalPublishedByUid: meta.data()?.publishedByUid || null,
          archivedAt: stamp(admin), archivedByUid: uid,
        source: "legacy_snapshot_before_controlled_publication_v1",
      });
    }
    tx.create(historicalRef, {
      documentId: DOCUMENT_ID, versionId: historicalRef.id,
      version: active.version, revision: nextRevision,
      status: "Publié", chapters: rows,
      fingerprint: digest, publishedByUid: uid,
      publishedAt: stamp(admin), publicationDate: new Date(now).toISOString(),
      documentsModified: ["CGV — SPHOT ADMIN"],
      chaptersModified: {"CGV — SPHOT ADMIN": rows.map((x) => x.id)},
      source: "server_superadmin_legal_publication_v1",
    });
    tx.set(live, {title: "CGV — SPHOT ADMIN", published: true,
      testOnly: false, version: active.version, revision: nextRevision,
      chapters: rows.map((row) => ({id: row.id, title: row.title,
        content: row.content})),
      publicationSource: "server_superadmin_legal_publication_v1",
      publishedByUid: uid, publishedAt: stamp(admin),
      updatedAt: stamp(admin)}, {merge: true});
    for (const old of currentRows.docs) {
      if (!rows.some((x) => x.id === old.id)) tx.delete(old.ref);
    }
    for (const row of rows) {
      tx.set(chaptersRef.doc(row.id), {
        title: row.title, content: row.content, order: row.order,
        isActive: true, updatedAt: stamp(admin)}, {merge: true});
    }
    tx.update(draft, {status: "published", publishedRevision: nextRevision,
      publishedAt: stamp(admin), publishedByUid: uid,
      updatedAt: stamp(admin)});
    return {published: true, documentId: DOCUMENT_ID,
      version: active.version, revision: nextRevision,
      archivedVersionId: historicalRef.id};
  });
}

function registerLegalAdminPublication({admin, onRequest}) {
  return onRequest({region: "us-central1", cors: ORIGINS,
    cpu: 1, memory: "256MiB", maxInstances: 3}, async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    if (req.method !== "POST") {
      return res.status(405).json({success: false});
    }
    try {
      const bearer = clean(req.get("Authorization"));
      if (!bearer.startsWith("Bearer ")) throw error(401, "SESSION_REQUISE");
      const token = await admin.auth().verifyIdToken(bearer.slice(7), true);
      const result = await legalAction({admin, token, input: req.body});
      return res.status(200).json({success: true, ...result});
    } catch (e) {
      const status = e.httpStatus || 403;
      if (!e.httpStatus) console.error("Legal publication denied");
      return res.status(status).json({success: false,
        error: e.httpStatus ? e.message : "OPERATION_REFUSEE"});
    }
  });
}

module.exports = {legalAction, registerLegalAdminPublication, fingerprint,
  canonicalChapters, assertReviewer};
