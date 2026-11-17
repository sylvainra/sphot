"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {acceptAdminCgv, readAdminCgvAcceptanceStatus, historicalId} =
  require("../odoo_admin_cgv_acceptance");

const UID = "admin_1234567890";
function harness() {
  const storage = new Map();
  const key = (c, id) => `${c}/${id}`;
  const put = (c, id, data) => storage.set(key(c, id), structuredClone(data));
  put("admins", UID, {uid: UID, territoireId: "longer_2026",
    accessStatus: "approved"});
  put("subscriptions", UID, {adminUid: UID, billingCycle: "annual"});
  put("legalDocuments", "adminCgv", {version: "1.0", revision: 2,
    published: true});
  const ref = (c, id) => ({id, collectionName: c,
    async get() {
      const value = storage.get(key(c, id));
      return {exists: value !== undefined, data: () => value && structuredClone(value)};
    },
    collection(sub) {
      assert.equal(c, "legalDocuments");
      assert.equal(sub, "chapters");
      return {limit(n) {
        assert.equal(n, 1);
        return {async get() {return {empty: false};}};
      }};
    },
  });
  const db = {
    collection(c) {return {doc(id) {return ref(c, id);}};},
    async runTransaction(fn) {
      const ops = [];
      const result = await fn({
        get: (reference) => reference.get(),
        set: (reference, value) => ops.push(() => put(
          reference.collectionName, reference.id, value)),
        create: (reference, value) => ops.push(() => {
          const k = key(reference.collectionName, reference.id);
          if (storage.has(k)) throw Error("already_exists");
          put(reference.collectionName, reference.id, value);
        }),
        update: (reference, value) => ops.push(() => {
          const k = key(reference.collectionName, reference.id);
          if (!storage.has(k)) throw Error("not_found");
          put(reference.collectionName, reference.id,
            {...storage.get(k), ...value});
        }),
      });
      ops.forEach((op) => op());
      return result;
    },
  };
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => ({seconds: 1793872800})};
  const admin = {auth: () => ({verifyIdToken: async (token, revoked) => {
    if (token !== "good" || revoked !== true) throw Error("invalid token");
    return {uid: UID, adminUid: UID, role: "ADMIN",
      territoireId: "longer_2026"};
  }}), firestore};
  const args = {admin, authorization: "Bearer good", requestId: UID,
    expectedVersion: "1.0", expectedRevision: 2, accepted: true};
  return {admin, args, storage, put};
}

test("CGV ADMIN : acceptation atomique, trace serveur et copie d'affichage", async () => {
  const h = harness();
  const response = await acceptAdminCgv(h.args);
  assert.equal(response.alreadyAccepted, false);
  const proof = h.storage.get(`odooAdminCgvAcceptanceEvidence/${UID}`);
  assert.equal(proof.source, "sphot_admin_cgv_server_acceptance_v1");
  assert.equal(proof.version, "1.0");
  assert.equal(proof.revision, 2);
  assert.equal(proof.testOnly, false);
  assert.equal(h.storage.get(`subscriptions/${UID}`)
    .commercialCgvAcceptance.version, "1.0");
  assert.ok(h.storage.has(`odooAdminCgvAcceptanceHistory/${historicalId(UID, "1.0", 2)}`));
  assert.equal(h.storage.size, 5);
});

test("CGV ADMIN : second clic idempotent, pas de double historique", async () => {
  const h = harness();
  await acceptAdminCgv(h.args);
  const second = await acceptAdminCgv(h.args);
  assert.equal(second.alreadyAccepted, true);
  assert.equal(h.storage.size, 5);
});

test("CGV ADMIN : aucune acceptation sans consentement explicite", async () => {
  const h = harness();
  await assert.rejects(() => acceptAdminCgv({...h.args, accepted: false}),
    /Confirmation/);
  assert.equal(h.storage.size, 3);
});

test("CGV ADMIN : revision modifiee, aucune trace", async () => {
  const h = harness();
  h.put("legalDocuments", "adminCgv", {version: "1.0", revision: 3,
    published: true});
  await assert.rejects(() => acceptAdminCgv(h.args), /Version/);
  assert.equal(h.storage.size, 3);
});

test("CGV ADMIN : session non autorisee, aucune trace", async () => {
  const h = harness();
  await assert.rejects(() => acceptAdminCgv({...h.args,
    authorization: "Bearer invalid"}), /Session/);
  assert.equal(h.storage.size, 3);
});

test("CGV ADMIN : factureur sans abonnement n'est pas accepte", async () => {
  const h = harness();
  h.storage.delete(`subscriptions/${UID}`);
  await assert.rejects(() => acceptAdminCgv(h.args), /Abonnement/);
  assert.equal(h.storage.size, 2);
});

test("CGV ADMIN : une version de TEST n'est jamais acceptee", async () => {
  const h = harness();
  h.put("legalDocuments", "adminCgv", {version: "1.0", revision: 2,
    published: true, testOnly: true});
  await assert.rejects(() => acceptAdminCgv(h.args), /Version/);
  assert.equal(h.storage.size, 3);
});

test("CGV ADMIN : nouvelle revision historisee sans ecraser l'ancienne", async () => {
  const h = harness();
  await acceptAdminCgv(h.args);
  h.put("legalDocuments", "adminCgv", {version: "1.0", revision: 3,
    published: true});
  const next = await acceptAdminCgv({...h.args, expectedRevision: 3});
  assert.equal(next.alreadyAccepted, false);
  assert.ok(h.storage.has(`odooAdminCgvAcceptanceHistory/${historicalId(UID, "1.0", 2)}`));
  assert.ok(h.storage.has(`odooAdminCgvAcceptanceHistory/${historicalId(UID, "1.0", 3)}`));
  assert.equal(h.storage.get(`odooAdminCgvAcceptanceEvidence/${UID}`).revision, 3);
  assert.equal(h.storage.size, 6);
});

test("CGV ADMIN : etat juridique lu depuis la preuve serveur", async () => {
  const h = harness();
  const before = await readAdminCgvAcceptanceStatus({
    admin: h.admin, authorization: "Bearer good", requestId: UID,
  });
  assert.equal(before.accepted, false);
  await acceptAdminCgv(h.args);
  const after = await readAdminCgvAcceptanceStatus({
    admin: h.admin, authorization: "Bearer good", requestId: UID,
  });
  assert.equal(after.accepted, true);
  assert.equal(after.version, "1.0");
  assert.equal(after.revision, 2);
  h.put("legalDocuments", "adminCgv", {version: "1.0", revision: 3,
    published: true});
  const outdated = await readAdminCgvAcceptanceStatus({
    admin: h.admin, authorization: "Bearer good", requestId: UID,
  });
  assert.equal(outdated.accepted, false);
});
