/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {checkAdminReadiness} =
  require("../local/odoo_admin_test_readiness");

const PROJECT = "sphot-c4-test-20261029";
const DATABASE = "sphot_publicitaire_checkout_test";

function mocks({approved = false, review = false, contract = false,
  demoPublished = true} = {}) {
  const calls = [];
  const found = {adminRequests: approved,
    adminOdooReviewEvidence: review,
    adminOdooEngagementEvidence: contract,
    adminOdooCycles: false};
  const db = {
    projectId: PROJECT,
    collection(name) {
      assert.ok(Object.hasOwn(found, name), name);
      const query = {
        where(field, op, value) {
          assert.equal(name, "adminRequests");
          assert.deepEqual([field, op, value], ["status", "==", "approved"]);
          return query;
        },
        limit(n) {
          assert.equal(n, 1);
          return query;
        },
        async get() {
          calls.push(`firestore_read:${name}`);
          return {empty: !found[name]};
        },
      };
      return query;
    },
  };
  const odooClient = {
    async call(model, method, args) {
      calls.push(`odoo_read:${model}/${method}`);
      if (method === "search_read" && model === "sphot.admin.checkout") {
        assert.deepEqual(args.fields, ["id"]);
        return [];
      }
      assert.equal(method, "read_stripe_checkout_evidence");
      assert.equal(model, "sphot.admin.checkout");
      return {contract: "sphot_admin_stripe_evidence_v1",
        invoice_id: 14,
        reference: "SPHOT-ADM-TEST-014E00309CE1AFAC",
        fingerprint: "6ac32f241dddee576f484d22c086e3ec52b6cb0f79dd829f0390e106bf532135",
        stripe_providers: [{code: "stripe", is_live: false,
          is_published: true}],
        demo_providers: [{code: "demo", is_published: demoPublished}],
        transactions: []};
    },
  };
  return {db, odooClient, calls};
}

test("ADMIN prévol TEST : lectures Odoo + Firestore uniquement, zéro écriture", async () => {
  const {db, odooClient, calls} = mocks();
  const result = await checkAdminReadiness({db, odooClient,
    database: DATABASE});
  assert.equal(result.invoiceControl, "POSTED_AND_LINKED_BY_RESTRICTED_ODOO_METHOD");
  assert.equal(result.stripeTestPublished, true);
  assert.equal(result.demoPublished, true);
  assert.equal(result.firestoreActivationAttempted, false);
  assert.equal(result.nextGate, "TEST_ADMIN_APPROVAL_REQUIRED");
  assert.equal(calls.length, 6);
  assert.ok(calls.every((call) => /_read:/.test(call)));
});

test("ADMIN prévol TEST : preuve Super Admin absente reste bloquante", async () => {
  const {db, odooClient} = mocks({approved: true});
  const result = await checkAdminReadiness({db, odooClient,
    database: DATABASE});
  assert.equal(result.nextGate, "SERVER_REVIEW_ARCHIVE_REQUIRED");
});

test("ADMIN prévol TEST : engagement public absent reste bloquant", async () => {
  const {db, odooClient} = mocks({approved: true, review: true});
  const result = await checkAdminReadiness({db, odooClient,
    database: DATABASE});
  assert.equal(result.nextGate, "SERVER_CONTRACT_PROOF_REQUIRED");
});

test("ADMIN prévol TEST : présence des documents n'est pas une validation", async () => {
  const {db, odooClient} = mocks({approved: true, review: true,
    contract: true, demoPublished: false});
  const result = await checkAdminReadiness({db, odooClient,
    database: DATABASE});
  assert.equal(result.nextGate, "SERVER_EVIDENCE_AUDIT_REQUIRED");
  assert.equal(result.demoPublished, false);
  assert.equal(result.firestoreActivationAttempted, false);
});

test("ADMIN prévol TEST : interdit les autres destinations", async () => {
  const {db, odooClient, calls} = mocks();
  await assert.rejects(checkAdminReadiness({db: {...db,
    projectId: "sphot-ab80b"}, odooClient, database: DATABASE}),
  /réservé à Odoo et Firestore TEST/);
  await assert.rejects(checkAdminReadiness({db, odooClient,
    database: "sphot_publicitaire_test"}),
  /réservé à Odoo et Firestore TEST/);
  assert.equal(calls.length, 0);
});
