"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {action} = require("../legal_document_editor");
const token = {uid: "sphot-super-admin-" + "a".repeat(32),
  role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
  sphotSaSessionExpiresAt: Date.now() + 600000};
for (const name of ["create", "save", "validate"]) {
  test(`avant publication initiale : ${name} refuse sans ecriture`, async () => {
    let writes = 0;
    const ref = (path) => ({path, collection: (n) => ref(`${path}/${n}`),
      doc: (id) => ref(`${path}/${id}`)});
    const snapshot = (path) => path.endsWith("/chapters") ? {docs: []} :
      {exists: false, data: () => ({})};
    const admin = {firestore: () => ({collection: (n) => ref(n),
      runTransaction: async (fn) => fn({get: async (r) => snapshot(r.path),
        set: () => {writes++;}, update: () => {writes++;}})})};
    const input = name === "create" ? {action: name, documentId: "cgu"} :
      name === "save" ? {action: name, documentId: "cgu",
        expectedDraftRevision: 0, articleId: "01", title: "Article",
        content: "Contenu", changeSummary: "Correction"} :
        {action: name, documentId: "cgu",
          expectedDraftRevision: 0, confirm: true};
    await assert.rejects(action({admin, token, input}),
      {httpStatus: 409, message: "PUBLIER_D_ABORD_LE_LOT_INITIAL"});
    assert.equal(writes, 0);
  });
}