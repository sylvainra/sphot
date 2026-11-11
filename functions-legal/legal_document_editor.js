/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Edition versionnee des sources juridiques SPHOT (CGU par profil).
// Les brouillons editoriaux sont distincts des cinq textes consolides C4 :
// une correction ne peut donc pas alterer leur publication initiale.
// Aucune route n'est exportee sans SPHOT_ENABLE_LEGAL_DOCUMENT_EDITOR.
// Publier exige un second opt-in, independent de l'acces aux brouillons.
const crypto = require("node:crypto");
const {assertReviewer} = require("./legal_admin_publication");
const initialPack = require("./legal_pack_publication");

const EDITOR_SOURCE = "sphot_legal_document_editor_v1";
const INITIAL_SOURCE = "legal_pack_five_documents_atomic_v1";
const EDITOR_DRAFTS = "legalEditorialDrafts";
const SPECIFICATIONS = Object.freeze({
  cgu: "CGU — GRAND PUBLIC",
  adminCgu: "CGU — SPHOT ADMIN",
  advertiserCgu: "CGU — SPHOT PUBLICITAIRE",
  adminCgv: "CGV — SPHOT ADMIN",
  advertiserCgv: "CGV — SPHOT PUBLICITAIRE",
  sauveteurCgu: "CGU — SPHOT SAUVETEUR",
  sauveteurCharter: "CHARTE — SPHOT SAUVETEUR",
  rgpdNotice: "NOTICE RGPD",
  privacyPolicy: "POLITIQUE DE CONFIDENTIALITÉ",
});
const INITIAL_IDS = new Set(initialPack.DOCUMENTS.map((s) => s.id));
// Les deux nouvelles CGU sont importées uniquement depuis le corpus
// approuvé. Aucun document n'est publié automatiquement.
const SEEDED_CGU = Object.freeze({
  adminCgu: require("./legal_sources/adminCgu.json"),
  advertiserCgu: require("./legal_sources/advertiserCgu.json"),
});
function approvedSeed(id) {
  const seed = SEEDED_CGU[id];
  if (!seed || seed.documentId !== id ||
      seed.status !== "PREPUBLICATION_NON_PUBLIE" ||
      seed.approvedOn !== "2026-11-11") {
    throw refuse(409, "SOURCE_CGU_NON_VALIDEE");
  }
  return canonical(seed.chapters);
}
const ORIGINS = ["https://sphot.app", "https://www.sphot.app",
  "http://127.0.0.1:5081", "http://localhost:5081",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com"];

function refuse(status, code) {
  const e = new Error(code);
  e.httpStatus = status;
  return e;
}
function clean(value) {return typeof value === "string" ? value.trim() : "";}
function hash(value) {
  return crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
}
function specFor(id) {
  if (!Object.hasOwn(SPECIFICATIONS, id)) throw refuse(400, "DOCUMENT_INCONNU");
  return {id, label: SPECIFICATIONS[id]};
}
function canonical(rows) {
  if (!Array.isArray(rows) || rows.length === 0 || rows.length > 60) {
    throw refuse(409, "ARTICLES_INVALIDES");
  }
  const ids = new Set();
  const normalized = rows.map((row, index) => {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      throw refuse(409, "ARTICLE_INVALIDE");
    }
    const id = clean(row.id);
    const title = clean(row.title || row.titre);
    const content = clean(row.content || row.texte);
    if (!/^[A-Za-z0-9_-]{2,64}$/.test(id) || ids.has(id) ||
        !title || title.length > 240 ||
        !content || content.length > 40000 ||
        row.order !== index + 1 || row.isActive !== true) {
      throw refuse(409, "ARTICLE_NON_CANONIQUE");
    }
    ids.add(id);
    return {id, title, content, order: index + 1, isActive: true};
  });
  if (Buffer.byteLength(JSON.stringify(normalized), "utf8") > 700000) {
    throw refuse(409, "DOCUMENT_TROP_VOLUMINEUX");
  }
  return normalized;
}
function validateInput(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw refuse(400, "REQUETE_INVALIDE");
  }
  specFor(value.documentId);
  const fields = {
    status: ["action", "documentId"],
    create: ["action", "documentId"],
    save: ["action", "documentId", "expectedDraftRevision", "articleId", "title", "content", "changeSummary"],
    validate: ["action", "documentId", "expectedDraftRevision", "confirm"],
    discard: ["action", "documentId", "expectedDraftRevision", "confirm"],
    publish: ["action", "documentId", "expectedDraftRevision", "expectedHash", "confirm"],
  };
  const accepted = Object.hasOwn(fields, value.action) ? fields[value.action] : null;
  if (!accepted || Object.keys(value).sort().join("|") !== accepted.sort().join("|")) {
    throw refuse(400, "ACTION_OU_CHAMPS_INTERDITS");
  }
  if (["save", "validate", "publish", "discard"].includes(value.action) &&
    (!Number.isSafeInteger(value.expectedDraftRevision) || value.expectedDraftRevision < 0)) {
    throw refuse(400, "REVISION_BROUILLON_INVALIDE");
  }
  if (value.action === "save" &&
    (!/^[A-Za-z0-9_-]{2,64}$/.test(clean(value.articleId)) ||
     !clean(value.title) || clean(value.title).length > 240 ||
     !clean(value.content) || clean(value.content).length > 40000 ||
     !clean(value.changeSummary) || clean(value.changeSummary).length > 600)) {
    throw refuse(400, "MODIFICATION_INVALIDE");
  }
  if (["validate", "publish", "discard"].includes(value.action) && value.confirm !== true) {
    throw refuse(400, "CONFIRMATION_EXPLICITE_REQUISE");
  }
  if (value.action === "publish" && !/^[a-f0-9]{64}$/.test(clean(value.expectedHash))) {
    throw refuse(400, "EMPREINTE_INVALIDE");
  }
  return value;
}
function checkDraft(snapshot, expectedRevision) {
  const data = snapshot.exists ? snapshot.data() || {} : {};
  if (!snapshot.exists || data.source !== EDITOR_SOURCE ||
      !Object.hasOwn(SPECIFICATIONS, data.documentId) ||
      !Number.isSafeInteger(data.draftRevision) ||
      (expectedRevision != null && data.draftRevision !== expectedRevision) ||
      !["draft", "validated"].includes(data.status) ||
      !/^[a-f0-9]{64}$/.test(clean(data.baseHash)) ||
      !Number.isSafeInteger(data.baseRevision) ||
      !/^[a-f0-9]{64}$/.test(clean(data.sourceHash))) {
    throw refuse(409, "BROUILLON_OBSOLETE_RECHARGEZ");
  }
  return {...data, chapters: canonical(data.chapters)};
}
function isInitialPublished(meta) {
  const d = meta.exists ? meta.data() || {} : {};
  return Boolean(clean(d.packPath)) &&
    [INITIAL_SOURCE, EDITOR_SOURCE].includes(clean(d.lastLegalPackPublicationSource));
}
function stamp(admin) {return admin.firestore.FieldValue.serverTimestamp();}
function formattedRevision(n) {return String(n).padStart(8, "0");}
function draftResult(data) {
  if (!data) return null;
  return {status: data.status, draftRevision: data.draftRevision,
    chapters: data.chapters, reviewedHash: data.reviewedHash || "",
    changeSummary: data.changeSummary || "",
    sourcePendingInitialPublication: data.sourcePendingInitialPublication === true};
}

async function action({admin, token, input, now = Date.now(), allowPublish = false}) {
  const uid = assertReviewer(token, now);
  const p = validateInput(input);
  const spec = specFor(p.documentId);
  const db = admin.firestore();
  const liveRef = db.collection("legalDocuments").doc(spec.id);
  const editorRef = db.collection(EDITOR_DRAFTS).doc(spec.id);
  const metaRef = db.collection("legalDocuments").doc("metadata");
  if (p.action === "status") {
    const [live, chapters, draft, metadata] = await Promise.all([
      liveRef.get(), liveRef.collection("chapters").get(),
      editorRef.get(), metaRef.get(),
    ]);
    const active = initialPack.activeSnapshot(live, chapters);
    const draftData = draft.exists ? draft.data() : null;
    if (draftData && (draftData.source !== EDITOR_SOURCE ||
        draftData.documentId !== spec.id)) {
      throw refuse(409, "BROUILLON_EDITEUR_INATTENDU");
    }
    return {documentId: spec.id, title: spec.label,
      initialPackPublished: isInitialPublished(metadata),
      publicationEnabled: allowPublish,
      published: {version: active.version, revision: active.revision,
        published: active.published},
      draft: draftResult(draftData)};
  }
  if (p.action === "create") {
    return db.runTransaction(async (tx) => {
      const [live, chapters, draft, metadata] = await Promise.all([
        tx.get(liveRef), tx.get(liveRef.collection("chapters")),
        tx.get(editorRef), tx.get(metaRef),
      ]);
      const active = initialPack.activeSnapshot(live, chapters);
      if (!isInitialPublished(metadata)) {
        throw refuse(409, "PUBLIER_D_ABORD_LE_LOT_INITIAL");
      }
      if (draft.exists && ["draft", "validated"].includes(draft.data()?.status)) {
        const existing = checkDraft(draft);
        if (existing.documentId !== spec.id) throw refuse(409, "BROUILLON_MAUVAIS_DOCUMENT");
        return {draft: draftResult(existing)};
      }
      if (draft.exists && draft.data()?.source !== EDITOR_SOURCE) {
        throw refuse(409, "BROUILLON_EDITEUR_INATTENDU");
      }
      const beforeInitial = !isInitialPublished(metadata);
      let rows = active.rows;
      if (!active.exists && Object.hasOwn(SEEDED_CGU, spec.id)) {
        rows = approvedSeed(spec.id);
      }
      if (beforeInitial && INITIAL_IDS.has(spec.id)) {
        const sourceSpec = initialPack.DOCUMENTS.find((s) => s.id === spec.id);
        const imported = await tx.get(db.collection("legalDocumentDrafts").doc(spec.id));
        rows = initialPack.checkDraft(imported, sourceSpec).chapters;
      }
      rows = canonical(rows);
      const payload = {source: EDITOR_SOURCE, documentId: spec.id,
        status: "draft", draftRevision: 0, chapters: rows,
        sourceHash: hash(rows), baseHash: active.hash,
        baseRevision: active.revision, baseVersion: active.version,
        sourcePendingInitialPublication: beforeInitial,
        reviewedHash: "", reviewedByUid: null, reviewedAt: null,
        changeSummary: "", createdByUid: uid, createdAt: stamp(admin),
        updatedByUid: uid, updatedAt: stamp(admin)};
      tx.set(editorRef, payload);
      return {draft: draftResult(payload)};
    });
  }
  if (p.action === "save" || p.action === "validate") {
    return db.runTransaction(async (tx) => {
      const metadata = await tx.get(metaRef);
      if (!isInitialPublished(metadata)) {
        throw refuse(409, "PUBLIER_D_ABORD_LE_LOT_INITIAL");
      }
      const draftSnap = await tx.get(editorRef);
      const draft = checkDraft(draftSnap, p.expectedDraftRevision);
      if (draft.documentId !== spec.id) throw refuse(409, "BROUILLON_MAUVAIS_DOCUMENT");
      if (p.action === "save") {
        const index = draft.chapters.findIndex((row) => row.id === p.articleId);
        if (index < 0) throw refuse(409, "ARTICLE_INTROUVABLE");
        const rows = draft.chapters.map((row, i) => i === index ?
          {...row, title: clean(p.title), content: clean(p.content)} : row);
        const checked = canonical(rows);
        if (hash(checked) === hash(draft.chapters)) throw refuse(409, "AUCUNE_MODIFICATION");
        const updates = {chapters: checked, status: "draft",
          draftRevision: draft.draftRevision + 1,
          changeSummary: clean(p.changeSummary), reviewedHash: "",
          reviewedByUid: null, reviewedAt: null,
          updatedByUid: uid, updatedAt: stamp(admin)};
        tx.update(editorRef, updates);
        return {draft: draftResult({...draft, ...updates})};
      }
      const initialSeed = Object.hasOwn(SEEDED_CGU, spec.id) &&
        draft.baseRevision === -1 && draft.draftRevision === 0 &&
        hash(draft.chapters) === hash(approvedSeed(spec.id));
      if (!initialSeed &&
          (draft.draftRevision === 0 ||
            hash(draft.chapters) === draft.sourceHash)) {
        throw refuse(409, "AUCUN_CHANGEMENT_A_VALIDER");
      }
      const reviewedHash = hash(draft.chapters);
      tx.update(editorRef, {status: "validated", reviewedHash,
        reviewedByUid: uid, reviewedAt: stamp(admin),
        updatedByUid: uid, updatedAt: stamp(admin)});
      return {draft: draftResult({...draft, status: "validated", reviewedHash})};
    });
  }
  // Abandon transactionnel : ne touche jamais aux textes publies ni a l'historique.
  if (p.action === "discard") {
    return db.runTransaction(async (tx) => {
      const snapshot = await tx.get(editorRef);
      const draft = checkDraft(snapshot, p.expectedDraftRevision);
      if (draft.documentId !== spec.id) {
        throw refuse(409, "BROUILLON_MAUVAIS_DOCUMENT");
      }
      tx.delete(editorRef);
      return {discarded: true, documentId: spec.id};
    });
  }
  if (!allowPublish) throw refuse(403, "PUBLICATION_NON_ACTIVEE");
  return db.runTransaction(async (tx) => {
    const [metadata, draftSnap, ...snapshots] = await Promise.all([
      tx.get(metaRef), tx.get(editorRef),
      ...Object.keys(SPECIFICATIONS).flatMap((id) => {
        const ref = db.collection("legalDocuments").doc(id);
        return [tx.get(ref), tx.get(ref.collection("chapters"))];
      }),
    ]);
    if (!isInitialPublished(metadata)) throw refuse(409, "PUBLIER_D_ABORD_LES_CINQ_TEXTES_VALIDES");
    const draft = checkDraft(draftSnap, p.expectedDraftRevision);
    if (draft.documentId !== spec.id || draft.status !== "validated" ||
      !clean(draft.reviewedByUid) || !draft.reviewedAt ||
      hash(draft.chapters) !== draft.reviewedHash ||
      p.expectedHash !== draft.reviewedHash) {
      throw refuse(409, "BROUILLON_NON_VALIDE_OU_MODIFIE");
    }
    const ids = Object.keys(SPECIFICATIONS);
    const current = ids.map((id, i) => ({id, parent: snapshots[i * 2],
      chapters: snapshots[i * 2 + 1],
      ...initialPack.activeSnapshot(snapshots[i * 2], snapshots[i * 2 + 1])}));
    if (current.some((row) => {
      // Un texte nouveau non encore publié ne bloque pas les textes existants.
      // Il ne participe au corpus historique qu'une fois publié.
      if (!row.exists && Object.hasOwn(SEEDED_CGU, row.id)) return false;
      return !row.exists || !canonical(row.rows).length ||
        (INITIAL_IDS.has(row.id) && !row.published) ||
        (Object.hasOwn(SEEDED_CGU, row.id) && !row.published);
    })) {
      throw refuse(409, "PACK_JURIDIQUE_INCOMPLET");
    }
    const prior = current.find((row) => row.id === spec.id);
    if (prior.hash !== draft.baseHash || prior.revision !== draft.baseRevision) {
      // Un brouillon antérieur au premier pack est recevable uniquement si
      // le pack a publié, sans changement, le texte initial validé.
      if (!draft.sourcePendingInitialPublication ||
        hash(canonical(prior.rows)) !== draft.sourceHash) {
        throw refuse(409, "VERSION_PUBLIEE_MODIFIEE_RECREER_BROUILLON");
      }
    }
    const info = metadata.data() || {};
    const currentVersion = clean(info.legalVersion || info.version || info.activeVersion);
    const nextVersion = initialPack.nextVersion(currentVersion);
    const versionId = nextVersion.replace(".", "_");
    const globalRef = db.collection("legalVersions").doc(versionId);
    const packRef = db.collection("legalPacks").doc("versions")
      .collection("items").doc(versionId);
    const revision = prior.revision + 1;
    const oldRef = db.collection("legalVersions")
      .doc(`${spec.id}_r${formattedRevision(prior.revision)}_legacy`);
    const nextRef = db.collection("legalVersions")
      .doc(`${spec.id}_r${formattedRevision(revision)}_published`);
    const [global, pack, legacy, next] = await Promise.all([
      tx.get(globalRef), tx.get(packRef), tx.get(oldRef), tx.get(nextRef),
    ]);
    if (global.exists || pack.exists || next.exists ||
      (legacy.exists && legacy.data()?.fingerprint !== prior.hash)) {
      throw refuse(409, "HISTORIQUE_INCOHERENT_OU_VERSION_EXISTANTE");
    }
    const updated = current.map((row) => row.id === spec.id ?
      {...row, rows: draft.chapters, revision, version: nextVersion,
        exists: true, published: true} : row);
    const publicDocuments = updated.filter((row) => INITIAL_IDS.has(row.id));
    const commonDocuments = updated.filter((row) =>
      !INITIAL_IDS.has(row.id) && row.exists && row.published);
    if (prior.exists && !legacy.exists) {tx.create(oldRef, {
      documentId: spec.id, version: prior.version, revision: prior.revision,
      status: "Publié (archive)", chapters: prior.rows, fingerprint: prior.hash,
      archivedAt: stamp(admin), archivedByUid: uid, source: EDITOR_SOURCE,
    });}
    tx.create(nextRef, {documentId: spec.id, version: nextVersion,
      revision, status: "Publié", chapters: draft.chapters,
      fingerprint: hash(draft.chapters), changeSummary: draft.changeSummary,
      publishedAt: stamp(admin), publishedByUid: uid, source: EDITOR_SOURCE});
    tx.create(globalRef, {version: nextVersion, versionId,
      previousVersion: currentVersion, status: "Publié", source: EDITOR_SOURCE,
      documentsModified: [spec.label],
      chaptersModified: {[spec.label]: draft.chapters.map((x) => x.id)},
      documentRevisions: Object.fromEntries(publicDocuments.map((x) =>
        [x.id, x.revision])),
      commonDocuments: commonDocuments.map((x) => ({id: x.id,
        version: x.version, revision: x.revision})),
      publishedAt: stamp(admin), publishedByUid: uid});
    tx.create(packRef, {version: nextVersion, versionId, path: packRef.path,
      source: EDITOR_SOURCE, publishedAt: stamp(admin), publishedByUid: uid,
      documents: publicDocuments.map((x) => ({id: x.id,
        title: SPECIFICATIONS[x.id], revision: x.revision, chapters: x.rows})),
      commonDocuments: commonDocuments.map((x) => ({id: x.id,
        version: x.version, revision: x.revision, chapters: x.rows}))});
    tx.set(liveRef, {title: spec.label, version: nextVersion, revision,
      published: true, testOnly: false,
      chapters: draft.chapters, publicationSource: EDITOR_SOURCE,
      publishedAt: stamp(admin), publishedByUid: uid,
      updatedAt: stamp(admin)}, {merge: true});
    for (const row of draft.chapters) {
      tx.set(liveRef.collection("chapters").doc(row.id), {
        title: row.title, content: row.content,
        order: row.order, isActive: true,
        updatedAt: stamp(admin)}, {merge: true});
    }
    tx.update(editorRef, {status: "published", publishedVersion: nextVersion,
      publishedRevision: revision, publishedAt: stamp(admin),
      publishedByUid: uid, updatedAt: stamp(admin)});
    tx.set(metaRef, {version: nextVersion, legalVersion: nextVersion,
      activeVersion: nextVersion, packPath: packRef.path,
      publishedAt: stamp(admin), updatedAt: stamp(admin),
      lastLegalPackPublicationSource: EDITOR_SOURCE}, {merge: true});
    return {published: true, documentId: spec.id,
      version: nextVersion, revision, packPath: packRef.path};
  }, {maxAttempts: 3});
}

function register({admin, onRequest}) {
  return onRequest({region: "us-central1", cors: ORIGINS,
    cpu: 1, memory: "512MiB", maxInstances: 2}, async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    if (req.method !== "POST") return res.status(405).json({success: false});
    try {
      const auth = clean(req.get("Authorization"));
      if (!auth.startsWith("Bearer ")) throw refuse(401, "SESSION_REQUISE");
      const token = await admin.auth().verifyIdToken(auth.slice(7), true);
      const result = await action({admin, token, input: req.body,
        allowPublish: true /* publication individuelle explicite uniquement */});
      return res.status(200).json({success: true, ...result});
    } catch (e) {
      const status = e.httpStatus || 403;
      if (!e.httpStatus) console.error("SPHOT legal editing refused", e);
      return res.status(status).json({success: false,
        error: e.httpStatus ? e.message : "OPERATION_REFUSEE"});
    }
  });
}

module.exports = {SPECIFICATIONS, EDITOR_SOURCE, EDITOR_DRAFTS, hash,
  canonical, validateInput, checkDraft, isInitialPublished, action, register};
