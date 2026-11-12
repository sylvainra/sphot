"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {activeProfile, legalVersion, requiresAcceptance, validateInput, action} =
  require("../professional_legal_acceptance");

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
