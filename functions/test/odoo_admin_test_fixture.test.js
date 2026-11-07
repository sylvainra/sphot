/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {ADMIN_UID, TERRITORY_ID, fixture, fixtureRecords, seedFixture} =
  require("../local/odoo_admin_test_fixture");
const {createAdminTestFirestoreSync} =
  require("../local/odoo_admin_test_firestore_sync");

const PROJECT = "sphot-c4-test-20261029";
const DATE = new Date("2026-10-31T12:00:00Z");

function fakeDb(projectId = PROJECT) {
  const entries = new Map();
  const writes = [];
  const db = {
    projectId, entries, writes,
    collection(path) {
      return {doc(id) {return {key: `${path}/${id}`};}};
    },
    async runTransaction(callback) {
      const operations = [];
      const tx = {
        async get(ref) {
          const exists = entries.has(ref.key);
          return {exists, data: () => entries.get(ref.key)};
        },
        create(ref, data) {
          operations.push({op: "create", key: ref.key, data});
        },
        set(ref, data, options) {
          operations.push({op: "set", key: ref.key, data, options});
        },
      };
      const result = await callback(tx);
      if (operations.some((item) => item.op === "create" &&
        entries.has(item.key))) throw new Error("Document déjà présent");
      for (const item of operations) {
        entries.set(item.key, {...(item.options?.merge ?
            entries.get(item.key) || {} : {}), ...item.data});
        writes.push(item);
      }
      return result;
    },
  };
  return db;
}

async function withTestEnv(callback) {
  const keys = ["SPHOT_ADMIN_TEST_FIRESTORE_WRITES",
    "SPHOT_ADMIN_TEST_FIXTURE_WRITES", "SPHOT_ADMIN_TEST_PROJECT_ID",
    "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT", "FIRESTORE_EMULATOR_HOST"];
  const prior = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  Object.assign(process.env, {
    SPHOT_ADMIN_TEST_FIRESTORE_WRITES: "true",
    SPHOT_ADMIN_TEST_FIXTURE_WRITES: "true",
    SPHOT_ADMIN_TEST_PROJECT_ID: PROJECT,
    GCLOUD_PROJECT: PROJECT, GOOGLE_CLOUD_PROJECT: PROJECT,
  });
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try {return await callback();} finally {
    for (const key of keys) {
      if (prior[key] === undefined) delete process.env[key];
      else process.env[key] = prior[key];
    }
  }
}

test("ADMIN FICTIF : référence, montants et périmètre cohérents", () => {
  const {prepared, documentHash} = fixture();
  assert.match(prepared.reference, /^SPHOT-ADM-TEST-[A-F0-9]{16}$/);
  assert.equal(prepared.expectedUntaxedCents, 129700);
  assert.equal(prepared.expectedTotalCents, 155640);
  assert.deepEqual(prepared.locked.stationIds, [
    "sphot_station_fictive_01", "sphot_station_fictive_02",
    "sphot_station_fictive_03"]);
  assert.match(documentHash, /^[a-f0-9]{64}$/);
  const {entries} = fixtureRecords(DATE);
  assert.ok(entries.every((entry) => entry[2].testOnly === true));
  assert.ok(entries.some((entry) => entry[0] === "adminOdooReviewEvidence" &&
    entry[2].source === "test_fixture_superadmin_review"));
  assert.ok(entries.some((entry) => entry[0] === "adminOdooEngagementEvidence" &&
    entry[2].verificationSource === "test_fixture_simulation"));
  assert.ok(entries.every((entry) => !["orders", "invoices",
    "adminOdooCycles"].includes(entry[0])));
});

test("ADMIN FICTIF : sans opt-in, aucun document créé", async () => {
  const db = fakeDb();
  await assert.rejects(seedFixture(db, DATE), /TEST_FIRESTORE_ONLY/);
  assert.equal(db.entries.size, 0);
});

test("ADMIN FICTIF : refuse le projet historique même avec opt-in", async () => {
  await withTestEnv(async () => {
    const db = fakeDb("sphot-ab80b");
    await assert.rejects(seedFixture(db, DATE), /TEST_FIRESTORE_ONLY/);
    assert.equal(db.writes.length, 0);
  });
});

test("ADMIN FICTIF : refuse l'émulateur et les années futures", async () => {
  await withTestEnv(async () => {
    const db = fakeDb();
    process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
    await assert.rejects(seedFixture(db, DATE), /TEST_FIRESTORE_ONLY/);
    delete process.env.FIRESTORE_EMULATOR_HOST;
    await assert.rejects(seedFixture(db, new Date("2027-01-01T12:00:00Z")),
        /FIXTURE_ADMIN_YEAR_EXPIRED/);
    assert.equal(db.writes.length, 0);
  });
});

test("ADMIN FICTIF : création atomique TEST et reprise idempotente", async () => {
  await withTestEnv(async () => {
    const db = fakeDb();
    const first = await seedFixture(db, DATE);
    assert.equal(first.action, "created");
    assert.equal(db.writes.length, first.documentCount);
    assert.equal(db.entries.get(`admins/${ADMIN_UID}`).diffusionAccessGranted,
        false);
    assert.equal(db.entries.get(`subscriptions/${ADMIN_UID}`).status,
        "awaiting_subscription");
    assert.equal(db.entries.get(`territoires/${TERRITORY_ID}`).testOnly,
        true);
    assert.equal(db.entries.has(`adminOdooCycles/${first.reference}`), false);
    assert.equal((await seedFixture(db, DATE)).action, "none");
    assert.equal(db.writes.length, first.documentCount);
  });
});

test("ADMIN FICTIF : collision et changement de SIRET refusés", async () => {
  await withTestEnv(async () => {
    const db = fakeDb();
    await seedFixture(db, DATE);
    db.entries.get(`adminOdooReviewEvidence/${ADMIN_UID}`).siret =
      "12345678900012";
    await assert.rejects(seedFixture(db, DATE),
        /FIXTURE_ADMIN_COLLISION_OR_PARTIAL_RECORDS/);
  });
});

test("ADMIN FICTIF : simulation d'engagement active, sans paiement", async () => {
  await withTestEnv(async () => {
    const db = fakeDb();
    const {prepared} = fixture();
    await seedFixture(db, DATE);
    const client = {
      async status() {
        return {order: {id: 77, name: "S00077", state: "sale",
          x_sphot_reference: prepared.reference,
          x_sphot_fingerprint: prepared.fingerprint,
          client_order_ref: prepared.reference}, invoice: null};
      },
      async verifiedStripePayment() {
        throw new Error("Aucun paiement simulé pour un engagement public");
      },
    };
    const writer = createAdminTestFirestoreSync({db, checkoutClient: client});
    const result = await writer.activate({prepared, activatedAt: DATE});
    assert.equal(result.action, "activate");
    assert.equal(result.basis, "verified_public_commitment");
    assert.equal(db.entries.get(`adminOdooCycles/${prepared.reference}`)
        .paymentStatus, "not_paid");
    assert.equal(db.entries.get(`subscriptions/${ADMIN_UID}`).status,
        "active");
  });
});

test("ADMIN FICTIF : simulation sans marqueur test refusée", async () => {
  await withTestEnv(async () => {
    const db = fakeDb();
    const {prepared} = fixture();
    await seedFixture(db, DATE);
    db.entries.get(`adminOdooReviewEvidence/${ADMIN_UID}`).testOnly = false;
    const client = {
      async status() {
        return {order: {id: 77, name: "S00077", state: "sale",
          x_sphot_reference: prepared.reference,
          x_sphot_fingerprint: prepared.fingerprint,
          client_order_ref: prepared.reference}};
      },
      async verifiedStripePayment() {throw new Error("ne doit pas être appelé");},
    };
    await assert.rejects(createAdminTestFirestoreSync({db,
      checkoutClient: client}).activate({prepared, activatedAt: DATE}),
    /INITIAL_SUPERADMIN_REVIEW_NOT_PROVEN/);
  });
});

test("ADMIN FICTIF : fausse preuve de contrôle SIREN refusée", async () => {
  await withTestEnv(async () => {
    const db = fakeDb();
    const {prepared} = fixture();
    await seedFixture(db, DATE);
    db.entries.get(`adminOdooReviewEvidence/${ADMIN_UID}`)
        .superAdminChecks.siren = false;
    const writer = createAdminTestFirestoreSync({db, checkoutClient: {
      async status() {
        return {order: {id: 77, name: "S00077", state: "sale",
          x_sphot_reference: prepared.reference,
          x_sphot_fingerprint: prepared.fingerprint,
          client_order_ref: prepared.reference}};
      },
      async verifiedStripePayment() {throw new Error("unexpected");},
    }});
    await assert.rejects(writer.activate({prepared, activatedAt: DATE}),
    /INITIAL_SUPERADMIN_REVIEW_NOT_PROVEN/);
    assert.equal(db.entries.has(`adminOdooCycles/${prepared.reference}`), false);
  });
});
