"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {resolveOdooCheckoutIdentity} = require("../odoo_checkout_identity");

const requestId = "SPHOT_admin_2026";
function firebase(claims, collection, record) {
  return {
    auth: () => ({verifyIdToken: async () => claims}),
    firestore: () => ({collection: (name) => {
      assert.equal(name, collection);
      return {doc: (id) => {
        assert.equal(id, requestId);
        return {get: async () => ({exists: true, data: () => record})};
      }};
    }}),
  };
}

test("Odoo: vérification des droits ADMIN depuis Firestore", async () => {
  const claims = {uid: requestId, adminUid: requestId,
    role: "ADMIN", territoireId: "fr44"};
  const dossier = {accessStatus: "approved", territoireId: "fr44",
    uid: requestId};
  const identity = await resolveOdooCheckoutIdentity({
    admin: firebase(claims, "admins", dossier),
    authorization: "Bearer token", market: "ADMIN", requestId,
  });
  assert.equal(identity.uid, requestId);
  assert.equal(identity.dossier, dossier);
});

test("Odoo: refus d'un ADMIN dont le territoire n'est pas approuvé",
    async () => {
      const claims = {uid: requestId, adminUid: requestId,
        role: "ADMIN", territoireId: "fr44"};
      await assert.rejects(resolveOdooCheckoutIdentity({
        admin: firebase(claims, "admins", {accessStatus: "approved",
          territoireId: "fr85"}),
        authorization: "Bearer token", market: "ADMIN", requestId,
      }), {httpStatus: 403});
    });

test("Odoo: annonceur lié à son propre dossier uniquement", async () => {
  const claims = {uid: "uid_advertiser", advertiserRequestId: requestId,
    role: "ANNONCEUR"};
  const identity = await resolveOdooCheckoutIdentity({
    admin: firebase(claims, "advertiserRequests", {
      status: "approved", firebaseUid: "uid_advertiser",
    }),
    authorization: "Bearer token", market: "ADVERTISER", requestId,
  });
  assert.equal(identity.market, "ADVERTISER");
  await assert.rejects(resolveOdooCheckoutIdentity({
    admin: firebase({...claims, advertiserRequestId: "another"},
        "advertiserRequests", {status: "approved"}),
    authorization: "Bearer token", market: "ADVERTISER", requestId,
  }), {httpStatus: 403});
});

test("Odoo: aucun droit sans jeton Firebase", async () => {
  await assert.rejects(resolveOdooCheckoutIdentity({
    admin: firebase({}, "admins", {}), market: "ADMIN", requestId,
  }), {httpStatus: 401});
});
