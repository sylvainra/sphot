"use strict";

// Tests d'autorisation uniquement contre un emulateur Firestore local.
// Ne jamais connecter ce fichier aux donnees ou identifiants de production.
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {doc, setDoc, getDoc, updateDoc, deleteDoc} = require("firebase/firestore");

test("droits Firestore juridiques : lecture conservee, ecritures clientes refusees", async () => {
  const rules = fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8");
  const env = await initializeTestEnvironment({
    projectId: "demo-sphot-legal-rules",
    firestore: {host: "127.0.0.1", port: 8080, rules},
  });
  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "legalDocuments/cgu"), {version: "1.0"});
      await setDoc(doc(db, "legalDocuments/cgu/chapters/01"), {title: "Objet"});
      await setDoc(doc(db, "legalVersions/1_0"), {version: "1.0"});
      await setDoc(doc(db, "documents/dossier_owner"), {adminUid: "owner"});
    });

    const anonymous = env.unauthenticatedContext().firestore();
    const ordinary = env.authenticatedContext("user").firestore();
    const superAdmin = env.authenticatedContext("sphot-super-admin-" + "a".repeat(32), {
      role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
    }).firestore();

    // Compatibilite : carte et textes publics restent lisibles.
    for (const db of [anonymous, ordinary, superAdmin]) {
      await assertSucceeds(getDoc(doc(db, "legalDocuments/cgu")));
      await assertSucceeds(getDoc(doc(db, "legalDocuments/cgu/chapters/01")));
      await assertSucceeds(getDoc(doc(db, "legalVersions/1_0")));

      // L'app cliente, meme dotee de claims Super Admin, ne peut jamais
      // modifier un texte ou un historique. Seul le serveur Admin SDK ecrit.
      await assertFails(setDoc(doc(db, "legalDocuments/adminCgv"), {title: "INJECTE"}));
      await assertFails(updateDoc(doc(db, "legalDocuments/cgu"), {version: "9.9"}));
      await assertFails(deleteDoc(doc(db, "legalDocuments/cgu")));
      await assertFails(setDoc(doc(db, "legalDocuments/cgu/chapters/02"), {title: "INJECTE"}));
      await assertFails(updateDoc(doc(db, "legalDocuments/cgu/chapters/01"), {title: "INJECTE"}));
      await assertFails(setDoc(doc(db, "legalVersions/1_1"), {version: "1.1"}));
      await assertFails(updateDoc(doc(db, "legalVersions/1_0"), {version: "9.9"}));
      await assertFails(deleteDoc(doc(db, "legalVersions/1_0")));

      // Les brouillons et snapshots sont prives, sans lecture cliente.
      for (const name of ["legalDocumentDrafts/cgu", "legalEditorialDrafts/cgu",
        "legalPacks/versions/items/1_1"]) {
        await assertFails(getDoc(doc(db, name)));
        await assertFails(setDoc(doc(db, name), {version: "INJECTE"}));
      }
    }

    // Le comportement de la collection /documents est preserve.
    const owner = env.authenticatedContext("owner").firestore();
    await assertSucceeds(getDoc(doc(owner, "documents/dossier_owner")));
    await assertFails(getDoc(doc(ordinary, "documents/dossier_owner")));
    await assertFails(setDoc(doc(owner, "documents/dossier_owner"), {adminUid: "owner"}));
  } finally {
    await env.cleanup();
  }
});
