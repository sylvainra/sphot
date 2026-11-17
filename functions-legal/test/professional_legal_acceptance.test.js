"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {activeProfile, legalVersion, requiresAcceptance, validateInput, action} =
  require("../professional_legal_acceptance");
const {changedBlocks, buildAdminChanges} =
  require("../admin_legal_changes");

const adminToken = {uid: "uid-admin", role: "ADMIN", adminUid: "uid-admin"};
const advertiserToken = {
  uid: "advertiser-generated-uid", role: "ANNONCEUR",
  advertiserRequestId: "request-42",
};

function fixture(role = "ADMIN") {
  const docs = new Map();
  let autoId = 0;
  const actor = role === "ADMIN" ? adminToken : advertiserToken;
  const id = role === "ADMIN" ? "adminCgu" : "advertiserCgu";
  const count = role === "ADMIN" ? 14 : 12;
  docs.set("legalDocuments/" + id, {
    version: "1.2", revision: 1, published: true,
    chapters: Array.from({length: count}, (_, index) => ({
      id: String(index + 1).padStart(2, "0"),
      title: "Article " + (index + 1), content: "Contenu valide",
    })),
  });
  const ref = (path) => ({
    path,
    get: async () => ({
      exists: docs.has(path), data: () => docs.get(path),
    }),
    collection: (name) => ({
      doc: (key) => ref(path + "/" + name + "/" +
        (key || "history-" + (++autoId))),
    }),
  });
  const col = (name) => ({doc: (id) => ref(name + "/" + id)});
  const db = {collection: col,
    runTransaction: async (task) => {
      const tx = {
        get: (reference) => reference.get(),
        create: (reference, value) => {
          assert.equal(docs.has(reference.path), false);
          docs.set(reference.path, value);
        },
        set: (reference, value) => {
          docs.set(reference.path, {
            ...docs.get(reference.path), ...value,
          });
        },
      };
      return task(tx);
    },
  };
  const firestore = Object.assign(() => db, {FieldValue: {
    serverTimestamp: () => "SERVER_TIMESTAMP",
  }});
  return {docs, token: actor, id, admin: {firestore}};
}

test("ADMIN/annonceur : identité vérifiée par les claims signés", () => {
  assert.equal(activeProfile(adminToken).documentId, "adminCgu");
  assert.equal(activeProfile(advertiserToken).documentId, "advertiserCgu");
  assert.throws(() => activeProfile({uid: "x", role: "ADMIN",
    adminUid: "y"}), /PROFIL_PROFESSIONNEL_NON_AUTORISE/);
  assert.throws(() => activeProfile({uid: "x", role: "SAUVETEUR"}),
      /PROFIL_PROFESSIONNEL_NON_AUTORISE/);
});

test("les documents non publiés ne demandent aucune acceptation", async () => {
  const f = fixture();
  f.docs.get("legalDocuments/adminCgu").published = false;
  const result = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(result.published, false);
  assert.equal(result.required, false);
});

test("la publication d'une version active demande une acceptation", async () => {
  const f = fixture();
  const result = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(result.required, true);
  assert.equal(result.versionId, "1.2:r1");
  assert.equal(legalVersion(f.docs.get("legalDocuments/adminCgu"),
      activeProfile(adminToken)), "1.2:r1");
});

test("acceptation versionnée et historique ; autre version non acceptée", async () => {
  const f = fixture("ANNONCEUR");
  const accepted = await action({admin: f.admin, token: f.token,
    input: {action: "accept", versionId: "1.2:r1", accepted: true}});
  assert.equal(accepted.accepted, true);
  const recordPath = "professionalLegalAcceptances/ANNONCEUR_" +
      f.token.uid;
  assert.equal(f.docs.get(recordPath).versionId, "1.2:r1");
  assert.equal([...f.docs.keys()].filter((path) =>
    path.startsWith(recordPath + "/history/")).length, 1);
  const repeated = await action({admin: f.admin, token: f.token,
    input: {action: "accept", versionId: "1.2:r1", accepted: true}});
  assert.equal(repeated.alreadyAccepted, true);
  assert.equal([...f.docs.keys()].filter((path) =>
    path.startsWith(recordPath + "/history/")).length, 1);
  f.docs.get("legalDocuments/advertiserCgu").revision = 2;
  const next = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(next.required, true);
  assert.equal(next.versionId, "1.2:r2");
  await assert.rejects(() => action({admin: f.admin, token: f.token,
    input: {action: "accept", versionId: "1.2:r1", accepted: true}}),
  /DOCUMENT_JURIDIQUE_MODIFIE_RECHARGEZ/);
});

test("les versions exactes sont exigées et les preuves anciennes restent", () => {
  const current = {documentId: "adminCgu", versionId: "1.4:r3"};
  assert.equal(requiresAcceptance(current, {documentId: "adminCgu",
    versionId: "1.4:r3", accepted: true}), false);
  assert.equal(requiresAcceptance(current, {documentId: "cgu",
    versionId: "1.4:r3", accepted: true}), true);
  assert.equal(requiresAcceptance(current, {documentId: "adminCgu",
    versionId: "1.4:r2", accepted: true}), true);
  assert.throws(() => validateInput({
    action: "accept", versionId: "1.4:r3", accepted: false,
  }), /ACTION_OU_CHAMPS_INTERDITS/);
});

test("ADMIN : nouvelle version impose reacceptation sans effacer l'historique", async () => {
  const f = fixture("ADMIN");
  const initial = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(initial.required, true);
  assert.equal(initial.versionId, "1.2:r1");
  const first = await action({admin: f.admin, token: f.token,
    input: {action: "accept", versionId: "1.2:r1", accepted: true}});
  assert.equal(first.accepted, true);
  let status = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(status.required, false);

  const doc = f.docs.get("legalDocuments/adminCgu");
  doc.version = "1.8";
  doc.revision = 1;
  status = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(status.required, true);
  assert.equal(status.versionId, "1.8:r1");

  await assert.rejects(
      action({admin: f.admin, token: f.token, input: {
        action: "accept", versionId: "1.2:r1", accepted: true,
      }}),
      /DOCUMENT_JURIDIQUE_MODIFIE_RECHARGEZ/);
  const second = await action({admin: f.admin, token: f.token,
    input: {action: "accept", versionId: "1.8:r1", accepted: true}});
  assert.equal(second.accepted, true);
  status = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(status.required, false);

  const recordPath = "professionalLegalAcceptances/ADMIN_" + f.token.uid;
  assert.equal(f.docs.get(recordPath).versionId, "1.8:r1");
  assert.equal([...f.docs.keys()].filter(
      (key) => key.startsWith(recordPath + "/history/")).length, 2);
});

test("ADMIN : comparaison uniquement des passages effectivement modifies", () => {
  const old = "Introduction intacte.\n\nAncien paragraphe.\n\nConclusion.";
  const now = "Introduction intacte.\n\nNouveau paragraphe.\n\nConclusion.";
  assert.deepEqual(changedBlocks(old, now), [{
    before: "Ancien paragraphe.", after: "Nouveau paragraphe.",
  }]);
  assert.deepEqual(changedBlocks("A.\n\nC.", "A.\n\nB.\n\nC."), [
    {before: "", after: "B."},
  ]);
  assert.deepEqual(changedBlocks("A.\n\nB.\n\nC.", "A.\n\nC."), [
    {before: "B.", after: ""},
  ]);

  const previous = [
    {id: "01", title: "Article un", content: old},
    {id: "02", title: "Article deux", content: "Texte inchangé."},
  ];
  const current = [
    {id: "01", title: "Article un", content: now},
    {id: "02", title: "Article deux", content: "Texte inchangé."},
  ];
  const changes = buildAdminChanges(previous, current, {
    baselineVersionId: "1.7:r0", baselineKind: "previousPublished",
    versionId: "1.8:r1",
  });
  assert.equal(changes.articleCount, 1);
  assert.equal(changes.articles[0].id, "01");
  assert.deepEqual(changes.articles[0].blocks, [
    {before: "Ancien paragraphe.", after: "Nouveau paragraphe."},
  ]);
});

test("ADMIN : plusieurs articles, titres et ordre non ignores", () => {
  const a = [
    {id: "01", title: "A", content: "Identique"},
    {id: "02", title: "B", content: "Contenu B"},
    {id: "03", title: "C", content: "Contenu C"},
  ];
  const b = [
    {id: "02", title: "B révisé", content: "Contenu B"},
    {id: "01", title: "A", content: "Identique"},
    {id: "03", title: "C", content: "Contenu C modifié"},
  ];
  const diff = buildAdminChanges(a, b, {
    baselineVersionId: "1.1:r0", baselineKind: "lastAccepted",
    versionId: "1.5:r1",
  });
  assert.equal(diff.articleCount, 3);
  assert.equal(diff.articles[0].orderChanged, true);
  assert.equal(diff.articles[1].titleChanged, true);
  assert.equal(diff.articles[2].blocks[0].after, "Contenu C modifié");
});

test("ADMIN : statut sans ancienne preuve compare la publication precedente", async () => {
  const f = fixture("ADMIN");
  const current = f.docs.get("legalDocuments/adminCgu");
  const old = JSON.parse(JSON.stringify(current.chapters));
  old[6].content = "Début inchangé.\n\nTexte précédent.\n\nFin inchangée.";
  f.docs.set("legalVersions/adminCgu_r00000001_published", {
    documentId: "adminCgu", version: "1.2", revision: 1,
    chapters: old,
  });
  current.version = "1.8";
  current.revision = 2;
  current.chapters[6].content =
      "Début inchangé.\n\nTexte nouveau.\n\nFin inchangée.";
  const status = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(status.required, true);
  assert.equal(status.adminChanges.baselineKind, "previousPublished");
  assert.equal(status.adminChanges.baselineVersionId, "1.2:r1");
  assert.equal(status.adminChanges.articleCount, 1);
  assert.equal(status.adminChanges.articles[0].id, "07");
  assert.deepEqual(status.adminChanges.articles[0].blocks, [
    {before: "Texte précédent.", after: "Texte nouveau."},
  ]);
});

test("ADMIN : ancienne acceptation identifiee, ecarts cumules multi-revisions", async () => {
  const f = fixture("ADMIN");
  const old = JSON.parse(JSON.stringify(
      f.docs.get("legalDocuments/adminCgu").chapters));
  old[0].content = "Première rédaction.";
  old[1].content = "Seconde rédaction.";
  f.docs.set("legalVersions/adminCgu_r00000001_legacy", {
    documentId: "adminCgu", version: "1.2", revision: 1,
    chapters: old,
  });
  // Une publication intermédiaire r2 peut être absente des archives :
  // le calcul remonte toujours jusqu'à la dernière version acceptée.
  f.docs.set("professionalLegalAcceptances/ADMIN_uid-admin", {
    accepted: true, documentId: "adminCgu", versionId: "1.2:r1",
  });
  const current = f.docs.get("legalDocuments/adminCgu");
  current.version = "1.9";
  current.revision = 3;
  current.chapters[0].content = "Première rédaction mise à jour.";
  current.chapters[1].content = "Seconde rédaction mise à jour.";
  const status = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(status.adminChanges.baselineKind, "lastAccepted");
  assert.equal(status.adminChanges.baselineVersionId, "1.2:r1");
  assert.equal(status.adminChanges.articleCount, 2);
  assert.deepEqual(status.adminChanges.articles.map((row) => row.id),
      ["01", "02"]);
});

test("ADMIN : archive absente signifie CGU integrales, sans inventer de diff", async () => {
  const f = fixture("ADMIN");
  const result = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(result.required, true);
  assert.equal(result.adminChanges, null);
});

test("PUBLICITAIRE : le contrat de statut ne change pas", async () => {
  const f = fixture("ANNONCEUR");
  const status = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(status.required, true);
  assert.equal(Object.hasOwn(status, "adminChanges"), false);
});

test("ADMIN : la copie legacy exacte prime sur une version publiee obsolete", async () => {
  const f = fixture("ADMIN");
  const current = f.docs.get("legalDocuments/adminCgu");
  current.version = "1.8";
  current.revision = 1;
  current.chapters[6].content = "Clause finale actualisée.";
  const correct = JSON.parse(JSON.stringify(current.chapters));
  correct[6].content = "Clause finale précédente.";
  const obsolete = JSON.parse(JSON.stringify(current.chapters));
  obsolete[0].content = "Texte plus ancien sans rapport.";
  f.docs.set("legalVersions/adminCgu_r00000000_published", {
    documentId: "adminCgu", version: "1.1", revision: 0,
    chapters: obsolete,
  });
  f.docs.set("legalVersions/adminCgu_r00000000_legacy", {
    documentId: "adminCgu", version: "1.7", revision: 0,
    chapters: correct,
  });
  const status = await action({admin: f.admin, token: f.token,
    input: {action: "status"}});
  assert.equal(status.adminChanges.baselineVersionId, "1.7:r0");
  assert.deepEqual(status.adminChanges.articles.map((item) => item.id),
      ["07"]);
  assert.equal(status.adminChanges.articles[0].blocks[0].after,
      "Clause finale actualisée.");
});
