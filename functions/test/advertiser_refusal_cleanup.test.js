"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  eligibleForCleanup,
  purgeRejectedAdvertiserRequest,
  registerAdvertiserRefusalCleanup,
} = require("../advertiser_refusal_cleanup");

const REQUEST_ID = "advertiserRequest42";

/** @return {Object} Dossier refusé dont le mail a été expédié. */
function rejected() {
  return {
    uid: REQUEST_ID,
    status: "rejected",
    review: {status: "rejected"},
    rejectionEmail: {status: "sent", sentAt: "SERVER_TIME"},
    purgeAfterRejectionEmail: true,
  };
}

/** @return {Object} Fausse base et services pour tester les suppressions. */
function mockServices({data = rejected(), user = {providerData: []},
  fileNames = [`advertiser_requests/${REQUEST_ID}/proposed_visual.jpg`],
  storageFailure = false} = {}) {
  const calls = [];
  let exists = data !== null;
  const files = fileNames.map((name) => ({
    name,
    async delete(options) {
      calls.push(["file.delete", name, options]);
    },
  }));
  const reference = {
    async get() {
      calls.push("firestore.get");
      return {exists, data: () => data};
    },
  };
  const auth = {
    async getUser(id) {
      calls.push(["auth.getUser", id]);
      if (!user) {
        throw Object.assign(new Error("Not found"),
            {code: "auth/user-not-found"});
      }
      return user;
    },
    async deleteUser(id) {
      calls.push(["auth.deleteUser", id]);
      user = null;
    },
  };
  const admin = {
    firestore: () => ({
      collection: (name) => {
        assert.equal(name, "advertiserRequests");
        return {doc: (id) => {
          assert.equal(id, REQUEST_ID);
          return reference;
        }};
      },
      recursiveDelete: async (ref) => {
        assert.equal(ref, reference);
        calls.push("firestore.recursiveDelete");
        exists = false;
      },
    }),
    auth: () => auth,
    storage: () => ({bucket: (bucket) => {
      assert.equal(bucket, "sphot-ab80b.firebasestorage.app");
      return {getFiles: async ({prefix}) => {
        calls.push(["storage.getFiles", prefix]);
        if (storageFailure) throw new Error("Storage indisponible");
        return [files];
      }};
    }}),
  };
  return {admin, calls, get exists() {
    return exists;
  }};
}

test("seul un refus initial récent avec mail envoyé est éligible", () => {
  assert.equal(eligibleForCleanup(rejected()), true);
  assert.equal(eligibleForCleanup({...rejected(),
    purgeAfterRejectionEmail: undefined}), false);
  assert.equal(eligibleForCleanup({...rejected(),
    rejectionEmail: {status: "pending"}}), false);
  assert.equal(eligibleForCleanup({...rejected(),
    rejectionEmail: {status: "sent"}}), false);
  assert.equal(eligibleForCleanup({...rejected(),
    status: "approved", assetChangeRequest: {status: "rejected"}}), false);
});

test("supprime visuels, compte anonyme et dossier dans cet ordre", async () => {
  const mock = mockServices({fileNames: [
    `advertiser_requests/${REQUEST_ID}/proposed_visual.jpg`,
    `advertiser_requests/${REQUEST_ID}/foreign_registration_proof.pdf`,
  ]});
  assert.equal(await purgeRejectedAdvertiserRequest(mock.admin, REQUEST_ID),
      true);
  assert.equal(mock.exists, false);
  assert.deepEqual(mock.calls.map((call) =>
    Array.isArray(call) ? call[0] : call), [
    "firestore.get", "auth.getUser", "storage.getFiles", "file.delete",
    "file.delete", "auth.deleteUser", "firestore.get",
    "firestore.recursiveDelete",
  ]);
  assert.equal(mock.calls[2][1], `advertiser_requests/${REQUEST_ID}/`);
  assert.equal(await purgeRejectedAdvertiserRequest(mock.admin, REQUEST_ID),
      false);
});

test("aucune purge si le mail reste en attente ou le refus est ancien",
    async () => {
      for (const data of [
        {...rejected(), rejectionEmail: {status: "pending"}},
        {...rejected(), purgeAfterRejectionEmail: undefined},
      ]) {
        const mock = mockServices({data});
        assert.equal(await purgeRejectedAdvertiserRequest(
            mock.admin, REQUEST_ID), false);
        assert.equal(mock.exists, true);
        assert.deepEqual(mock.calls, ["firestore.get"]);
      }
    });

test("erreur Storage : document et utilisateur conservés pour nouvel essai",
    async () => {
      const mock = mockServices({storageFailure: true});
      await assert.rejects(purgeRejectedAdvertiserRequest(
          mock.admin, REQUEST_ID), /Storage indisponible/);
      assert.equal(mock.exists, true);
      assert.equal(mock.calls.some((call) => Array.isArray(call) &&
        call[0] === "auth.deleteUser"), false);
    });

test("ne touche pas un compte non anonyme ni un fichier hors périmètre",
    async () => {
      const linked = mockServices({user: {
        email: "contact@example.test", providerData: [{providerId: "password"}],
      }});
      await assert.rejects(purgeRejectedAdvertiserRequest(
          linked.admin, REQUEST_ID), /Compte non anonyme/);
      assert.equal(linked.exists, true);
      const unexpected = mockServices({
        fileNames: ["another_advertiser/image.jpg"],
      });
      await assert.rejects(purgeRejectedAdvertiserRequest(
          unexpected.admin, REQUEST_ID), /Fichier hors du dossier/);
      assert.equal(unexpected.exists, true);
    });

test("un compte déjà absent n'empêche pas la suppression du dossier",
    async () => {
      const mock = mockServices({user: null});
      assert.equal(await purgeRejectedAdvertiserRequest(mock.admin,
          REQUEST_ID), true);
      assert.equal(mock.exists, false);
    });

test("le trigger attend la confirmation du mail de refus", async () => {
  let callback;
  const mock = mockServices();
  const handler = registerAdvertiserRefusalCleanup({
    admin: mock.admin,
    onDocumentUpdated: (options, action) => {
      assert.equal(options.document, "advertiserRequests/{requestId}");
      assert.equal(options.retry, true);
      assert.equal(options.memory, "512MiB");
      callback = action;
      return action;
    },
  });
  assert.equal(handler, callback);
  await handler({
    data: {after: {data: () => ({...rejected(),
      rejectionEmail: {status: "pending"}})}},
    params: {requestId: REQUEST_ID},
  });
  assert.deepEqual(mock.calls, []);
  await handler({
    data: {after: {data: rejected}}, params: {requestId: REQUEST_ID},
  });
  assert.equal(mock.exists, false);
});
