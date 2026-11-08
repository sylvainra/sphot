/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// SPHOT — publication ATOMIQUE des cinq textes consolidés.
// Aucune route n'est exposée sauf opt-in explicite dans functions/index.js.
// Interdiction de lancer en production tant que les écritures clientes sur
// legalDocuments, legalVersions, legalDocumentDrafts et legalPacks ne sont pas
// bloquées par des règles Firestore réellement déployées et vérifiées.
// Ni commande, ni facture, ni paiement, ni activation de droits commerciaux.
const crypto = require("node:crypto");
const {assertReviewer} = require("./legal_admin_publication");
const DOCUMENTS = Object.freeze([
  {id: "adminCgv", source: "adminCgv", label: "CGV — SPHOT ADMIN", count: 13,
    sha: "0af4acfca71fda38b3d36a9c54df5e6599e09319f66e4c759353467622a8a2f1"},
  {id: "advertiserCgv", source: "advertiserCgv", label: "CGV — SPHOT PUBLICITAIRE", count: 13,
    sha: "0a22c3e7ff78365672193477145ddccd50f6e21366ce483d07a641d923ca2c83"},
  {id: "cgu", source: "publicCgu", label: "CGU — GRAND PUBLIC", count: 13,
    sha: "acf965f9948712f4e31d416e122ef6a92015b5ef4c868b5ec0e85545c5c5226b"},
  {id: "sauveteurCgu", source: "sauveteurCgu", label: "CGU — SPHOT SAUVETEUR", count: 8,
    sha: "d3c74d3d7740b96059cecb91bf9c3b46d383ba05506c536ea34e0fd42190d7aa"},
  {id: "sauveteurCharter", source: "sauveteurCharter", label: "CHARTE — SPHOT SAUVETEUR", count: 7,
    sha: "bc9c86d66cf59935b4a8d567bf1aee322de7ca2163122b10194ab8c04b69d7d7"},
]);
const SOURCE = "sphot_c4_validated_legal_import_20261106_v1";
const ORIGINS = ["https://sphot.app", "https://www.sphot.app",
  "https://sphot-ab80b.web.app", "https://sphot-ab80b.firebaseapp.com"];
const COMMON = ["privacyPolicy", "rgpdNotice"];
function refuse(status, code) {const e = new Error(code); e.httpStatus = status; return e;}
function clean(x) {return typeof x === "string" ? x.trim() : "";}
function sha(x) {return crypto.createHash("sha256").update(JSON.stringify(x)).digest("hex");}
function canonical(rows) {
  if (!Array.isArray(rows) || !rows.length || rows.length > 60) throw refuse(409, "ARTICLES_INVALIDES");
  const ids = new Set();
  const result = rows.map((raw, i) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw refuse(409, "ARTICLE_INVALIDE");
    const id = clean(raw.id); const title = clean(raw.title); const content = clean(raw.content);
    if (id !== String(i + 1).padStart(2, "0") || ids.has(id) ||
      !title || !content || title.length > 240 || content.length > 40000 ||
      raw.order !== i + 1 || raw.isActive !== true) throw refuse(409, "ARTICLE_NON_CANONIQUE");
    ids.add(id);
    return {id, title, content, order: i + 1, isActive: true};
  });
  if (Buffer.byteLength(JSON.stringify(result), "utf8") > 700000) throw refuse(409, "DOCUMENT_TROP_VOLUMINEUX");
  return result;
}
function sourceDigest(rows) {
  return sha(canonical(rows).map(({title, content}) => ({title, content})));
}
function checkDraft(meta, spec) {
  if (!meta.exists) throw refuse(409, "BROUILLON_ABSENT_" + spec.id);
  const d = meta.data() || {};
  if (d.documentId !== spec.id || d.importSource !== SOURCE ||
    d.sourceProject !== "sphot-c4-test-20261029" ||
    d.sourceDocumentId !== spec.source || d.sourceVersion !== "1.0" ||
    !Number.isSafeInteger(d.sourceRevision) || d.sourceRevision < 1 ||
    d.importedC4Hash !== spec.sha ||
    !Number.isSafeInteger(d.draftRevision) || d.draftRevision !== 0 ||
    !Number.isSafeInteger(d.baseRevision) || !/^[a-f0-9]{64}$/.test(clean(d.baseHash))) {
    throw refuse(409, "BROUILLON_NON_VERIFIE_" + spec.id);
  }
  const rows = canonical(d.chapters);
  if (rows.length !== spec.count || sourceDigest(rows) !== spec.sha) {
    throw refuse(409, "TEXTE_NON_IDENTIQUE_AU_CORPUS_" + spec.id);
  }
  return {...d, chapters: rows};
}
function activeSnapshot(parent, subcollection) {
  const data = parent.exists ? parent.data() || {} : {};
  const parentRows = Array.isArray(data.chapters) ? data.chapters.map((x, i) =>
    ({...x, id: clean(x?.id) || String(i + 1).padStart(2, "0")})) : [];
  const rows = subcollection.docs.length ? subcollection.docs.map((d) =>
    ({...d.data(), id: d.id})) : parentRows;
  rows.sort((a, b) => String(a.id).localeCompare(String(b.id)));
  const normalized = rows.map((x, i) => ({id: String(x.id),
    title: clean(x.title || x.titre), content: clean(x.content || x.texte),
    order: i + 1, isActive: x.isActive !== false}));
  const version = clean(data.version) || "1.0";
  const revision = Number.isSafeInteger(data.revision) && data.revision >= 0 ? data.revision : -1;
  const published = data.published === true && data.testOnly !== true;
  return {exists: parent.exists, version, revision, published,
    rows: normalized, hash: sha({version, revision, published, chapters: normalized})};
}
function nextVersion(s) {
  const value = clean(s);
  const match = /^(\d{1,3})\.(\d{1,4})$/.exec(value);
  if (!match || +match[2] >= 9999) throw refuse(409, "VERSION_JURIDIQUE_INVALIDE");
  return `${+match[1]}.${+match[2] + 1}`;
}
function packHash(drafts) {
  return sha(DOCUMENTS.map((spec) => ({id: spec.id,
    hash: sha(drafts.find((d) => d.documentId === spec.id).chapters)})));
}
function validateInput(p) {
  if (!p || typeof p !== "object" || Array.isArray(p)) throw refuse(400, "REQUETE_INVALIDE");
  if (p.action === "status" || p.action === "validate") {
    if (Object.keys(p).length !== 1) throw refuse(400, "CHAMPS_INTERDITS");
    return p;
  }
  if (p.action === "publish" && Object.keys(p).sort().join("|") ===
      ["action", "confirm", "expectedPackHash", "expectedVersion"].sort().join("|") &&
    p.confirm === true && /^[a-f0-9]{64}$/.test(clean(p.expectedPackHash)) &&
    /^\d{1,3}\.\d{1,4}$/.test(clean(p.expectedVersion))) return p;
  throw refuse(400, "ACTION_OU_CONFIRMATION_INVALIDE");
}
async function action({admin, token, input, now = Date.now()}) {
  const uid = assertReviewer(token, now);
  const p = validateInput(input);
  const db = admin.firestore();
  const metadataRef = db.collection("legalDocuments").doc("metadata");
  const specs = DOCUMENTS.map((spec) => ({...spec,
    live: db.collection("legalDocuments").doc(spec.id),
    draft: db.collection("legalDocumentDrafts").doc(spec.id)}));
  if (p.action === "status") {
    const [metadata, ...drafts] = await Promise.all([
      metadataRef.get(), ...specs.map((s) => s.draft.get()),
    ]);
    let ready = false; let resultHash = "";
    try {
      const checked = specs.map((spec, i) => checkDraft(drafts[i], spec));
      ready = checked.every((d) => d.status === "validated" &&
        d.reviewedHash === sha(d.chapters) && clean(d.reviewedByUid));
      if (ready) resultHash = packHash(checked);
    } catch (_) {ready = false;}
    const data = metadata.data() || {};
    return {currentVersion: clean(data.legalVersion || data.version || data.activeVersion) || "1.0",
      ready, packHash: resultHash,
      documents: specs.map((s, i) => ({id: s.id, label: s.label,
        articles: s.count, status: drafts[i].exists ? drafts[i].data()?.status : "absent"}))};
  }
  return db.runTransaction(async (tx) => {
    // Lectures faites avant toute écriture ; la transaction est tout-ou-rien.
    const metadata = await tx.get(metadataRef);
    if (!metadata.exists) throw refuse(409, "METADONNEES_JURIDIQUES_ABSENTES");
    const current = metadata.data() || {};
    const currentVersion = clean(current.legalVersion || current.version || current.activeVersion);
    if (!currentVersion) throw refuse(409, "VERSION_ACTIVE_ABSENTE");
    const result = [];
    for (const spec of specs) {
      const [draftSnap, liveSnap, chapterSnap] = await Promise.all([
        tx.get(spec.draft), tx.get(spec.live), tx.get(spec.live.collection("chapters")),
      ]);
      const d = checkDraft(draftSnap, spec);
      const active = activeSnapshot(liveSnap, chapterSnap);
      if (active.hash !== d.baseHash || active.revision !== d.baseRevision) {
        throw refuse(409, "DOCUMENT_ACTIF_CHANGE_" + spec.id);
      }
      if (p.action === "validate" && d.status !== "draft" && d.status !== "validated") {
        throw refuse(409, "BROUILLON_ETAT_INVALIDE_" + spec.id);
      }
      if (p.action === "publish" &&
        (d.status !== "validated" || !clean(d.reviewedByUid) || !d.reviewedAt ||
         d.reviewedHash !== sha(d.chapters))) {
        throw refuse(409, "TEXTE_NON_VALIDE_" + spec.id);
      }
      result.push({spec, d, active, liveSnap, chapterSnap});
    }
    if (p.action === "validate") {
      const digest = packHash(result.map((r) => r.d));
      for (const item of result) {
        if (item.d.status === "validated") {
          if (item.d.reviewedHash !== sha(item.d.chapters)) {
            throw refuse(409, "ANCIENNE_VALIDATION_INCOHERENTE");
          }
        } else {
          tx.update(item.spec.draft, {status: "validated",
            reviewedHash: sha(item.d.chapters), reviewedByUid: uid,
            reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()});
        }
      }
      return {validated: true, packHash: digest, currentVersion,
        documentCount: result.length};
    }
    if (p.expectedVersion !== currentVersion ||
      p.expectedPackHash !== packHash(result.map((r) => r.d))) {
      throw refuse(409, "PUBLICATION_MODIFIEE_RECHARGEZ");
    }
    const newVersion = nextVersion(currentVersion);
    const id = newVersion.replace(".", "_");
    const historyRef = db.collection("legalVersions").doc(id);
    const packRef = db.collection("legalPacks").doc("versions")
      .collection("items").doc(id);
    const targetRefs = result.map((item) => ({
      previousRef: item.active.exists ? db.collection("legalVersions")
        .doc(item.active.revision < 0 ? `${item.spec.id}_legacy_unversioned` :
          `${item.spec.id}_r${String(item.active.revision).padStart(8, "0")}_legacy`) : null,
      currentRef: db.collection("legalVersions")
        .doc(`${item.spec.id}_r${String(item.active.revision + 1).padStart(8, "0")}_published`),
    }));
    const [historySnap, packSnap, ...historySnaps] = await Promise.all([
      tx.get(historyRef), tx.get(packRef),
      ...targetRefs.flatMap((r) => [r.previousRef ? tx.get(r.previousRef) : Promise.resolve(null), tx.get(r.currentRef)]),
    ]);
    if (historySnap.exists || packSnap.exists) throw refuse(409, "VERSION_DEJA_PUBLIEE");
    for (let i = 0; i < targetRefs.length; i++) {
      const prior = historySnaps[i * 2]; const next = historySnaps[i * 2 + 1];
      if (next.exists) throw refuse(409, "HISTORIQUE_DEJA_UTILISE");
      if (prior?.exists && prior.data()?.fingerprint !== result[i].active.hash) {
        throw refuse(409, "HISTORIQUE_PRECEDENT_INCOHERENT");
      }
    }
    const common = [];
    for (const cid of COMMON) {
      const parent = db.collection("legalDocuments").doc(cid);
      const [doc, chapters] = await Promise.all([tx.get(parent), tx.get(parent.collection("chapters"))]);
      if (!doc.exists || chapters.empty) throw refuse(409, "DOCUMENT_COMMUN_MANQUANT_" + cid);
      common.push({id: cid, version: clean(doc.data()?.version),
        revision: Number.isSafeInteger(doc.data()?.revision) ? doc.data().revision : 0,
        chapters: chapters.docs.map((d) => ({id: d.id, ...d.data()}))});
    }
    const stamp = () => admin.firestore.FieldValue.serverTimestamp();
    for (let i = 0; i < result.length; i++) {
      const {spec, d, active, chapterSnap} = result[i];
      const {previousRef, currentRef} = targetRefs[i];
      if (previousRef && !historySnaps[i * 2]?.exists) {
        tx.create(previousRef, {documentId: spec.id,
          version: active.version, revision: active.revision,
          status: active.published ? "Publié (avant migration)" : "Document antérieur non publié",
          chapters: active.rows, fingerprint: active.hash,
          archivedAt: stamp(), archivedByUid: uid,
          source: "legal_pack_previous_document_backup_v1"});
      }
      const rev = active.revision + 1;
      tx.create(currentRef, {documentId: spec.id, version: newVersion,
        revision: rev, status: "Publié", chapters: d.chapters,
        fingerprint: sha(d.chapters), publishedByUid: uid, publishedAt: stamp(),
        source: "legal_pack_five_documents_atomic_v1"});
      tx.set(spec.live, {title: spec.label, version: newVersion, revision: rev,
        published: true, testOnly: false,
        chapters: d.chapters.map((r) => ({id: r.id, title: r.title, content: r.content})),
        publicationSource: "legal_pack_five_documents_atomic_v1",
        publishedByUid: uid, publishedAt: stamp(), updatedAt: stamp()}, {merge: true});
      for (const old of chapterSnap.docs) {
        if (!d.chapters.some((r) => r.id === old.id)) tx.delete(old.ref);
      }
      for (const row of d.chapters) {tx.set(spec.live.collection("chapters").doc(row.id),
        {title: row.title, content: row.content, order: row.order,
          isActive: true, updatedAt: stamp()}, {merge: true});}
      tx.update(spec.draft, {status: "published", publishedVersion: newVersion,
        publishedRevision: rev, publishedAt: stamp(), publishedByUid: uid, updatedAt: stamp()});
    }
    tx.create(historyRef, {version: newVersion, versionId: id,
      previousVersion: currentVersion, status: "Publié",
      documentsModified: DOCUMENTS.map((s) => s.label),
      chaptersModified: Object.fromEntries(DOCUMENTS.map((s) => [s.label,
        result.find((r) => r.spec.id === s.id).d.chapters.map((r) => r.id)])),
      source: "legal_pack_five_documents_atomic_v1",
      publishedByUid: uid, publishedAt: stamp(),
      documentRevisions: Object.fromEntries(result.map((r) =>
        [r.spec.id, r.active.revision + 1])),
      commonDocuments: common.map((c) => ({id: c.id, version: c.version, revision: c.revision}))});
    tx.create(packRef, {version: newVersion, versionId: id,
      path: packRef.path, source: "legal_pack_five_documents_atomic_v1",
      publishedByUid: uid, publishedAt: stamp(),
      documents: result.map((r) => ({id: r.spec.id, title: r.spec.label,
        revision: r.active.revision + 1, chapters: r.d.chapters})),
      commonDocuments: common});
    tx.set(metadataRef, {version: newVersion, legalVersion: newVersion,
      activeVersion: newVersion, packPath: packRef.path,
      publishedAt: stamp(), updatedAt: stamp(),
      lastLegalPackPublicationSource: "legal_pack_five_documents_atomic_v1"},
    {merge: true});
    return {published: true, version: newVersion, packPath: packRef.path,
      documentsPublished: result.length};
  }, {maxAttempts: 3});
}
function registerLegalPackPublication({admin, onRequest}) {
  return onRequest({region: "us-central1", cors: ORIGINS,
    cpu: 1, memory: "512MiB", maxInstances: 2}, async (req, res) => {
    res.set("Cache-Control", "no-store");
    res.set("X-Content-Type-Options", "nosniff");
    if (req.method !== "POST") return res.status(405).json({success: false});
    try {
      const bearer = clean(req.get("Authorization"));
      if (!bearer.startsWith("Bearer ")) throw refuse(401, "SESSION_REQUISE");
      const token = await admin.auth().verifyIdToken(bearer.slice(7), true);
      const result = await action({admin, token, input: req.body});
      return res.status(200).json({success: true, ...result});
    } catch (e) {
      const status = e.httpStatus || 403;
      if (!e.httpStatus) console.error("SPHOT legal pack publication refused", e);
      return res.status(status).json({success: false,
        error: e.httpStatus ? e.message : "OPERATION_REFUSEE"});
    }
  });
}
module.exports = {DOCUMENTS, COMMON, canonical, sourceDigest, checkDraft,
  activeSnapshot, nextVersion, packHash, validateInput, action,
  registerLegalPackPublication};
