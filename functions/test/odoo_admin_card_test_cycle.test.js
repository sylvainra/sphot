"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {TEST_PROJECT_ID} = require("../local/odoo_c4_test_firestore");
const {CHECKOUT_TEST_DATABASE} = require("../local/odoo_secure_checkout_client");
const {fixture: oldFixture} = require("../local/odoo_admin_test_fixture");
const {UID, STATIONS, buildCardFixture, cardRecords,
  checkCardFixture, seedCardFixture, verifyStripeReadiness,
  runCardCycle} = require("../local/odoo_admin_card_test_cycle");

const PREPARED = buildCardFixture();

function withEnv(vars, task) {
  const old = new Map(Object.keys(vars).map((key) =>
    [key, process.env[key]]));
  for (const [key, value] of Object.entries(vars)) {
    if (value == null) delete process.env[key];
    else process.env[key] = value;
  }
  return Promise.resolve().then(task).finally(() => {
    for (const [key, value] of old) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  });
}

const TEST_WRITE_ENV = {
  SPHOT_ADMIN_TEST_FIRESTORE_WRITES: "true",
  SPHOT_ADMIN_TEST_PROJECT_ID: TEST_PROJECT_ID,
  GCLOUD_PROJECT: TEST_PROJECT_ID,
  GOOGLE_CLOUD_PROJECT: TEST_PROJECT_ID,
};

function harness(seeded = false) {
  const docs = new Map(seeded ? cardRecords().entries.map(
      ([coll, id, value]) => [coll + "/" + id, {...value}]) : []);
  const calls = [];
  function snap(key) {
    return {exists: docs.has(key), data: () => docs.get(key)};
  }
  const db = {projectId: TEST_PROJECT_ID,
    collection(coll) {
      return {doc(id) {
        const key = coll + "/" + id;
        return {key, get: async () => {
          calls.push(["read", key]); return snap(key);
        }};
      }};
    },
    runTransaction: async (fn) => {
      calls.push(["transaction"]);
      return fn({get: async (ref) => snap(ref.key),
        create(ref, val) {calls.push(["create", ref.key]); docs.set(ref.key, val);},
        set() {throw new Error("UNEXPECTED_SET");}});
    }};
  const odooClient = {async call(model, method, body) {
    calls.push(["odoo", model, method]);
    if (model === "product.product" && method === "read") {
      return [2, 3, 4, 5].map((id, i) => ({
        id, default_code: "SPHOT-ADM-TEST-T" + (i + 1),
        type: "service", invoice_policy: "order",
        sale_ok: true, active: true, list_price: 0}));
    }
    if (model === "res.partner" && method === "read") {
      return [{id: 8, name: "SPHOT CLIENT API - TEST NEUTRALISE",
        is_company: true, active: true,
        country_id: [1, "France"], street: "1 rue Test",
        zip: "75000", city: "PARIS"}];
    }
    throw Error("UNEXPECTED_ODOO_CALL " + model);
  }};
  return {db, docs, calls, odooClient};
}

function checkout(statusResult, stripeEvidenceResult) {
  const used = [];
  const client = {
    status: async () => {used.push("status"); return statusResult;},
    draft: async () => {used.push("draft"); return {order: {id: 40}};},
    invoice: async () => {used.push("invoice"); return {outcome: "created"};},
    stripeEvidence: async () => {used.push("stripeEvidence");
      return stripeEvidenceResult;},
    verifiedStripePayment: async () => {used.push("verifiedStripePayment");
      throw Error("STRIPE_NOT_PROVEN");},
  };
  return {used, client, factory: () => client};
}

function unPaidStatus() {
  return {order: {id: 41, name: "S00041", state: "sale"},
    invoice: {id: 55, name: "FAC/2026/00041",
      state: "posted", payment_state: "not_paid"}};
}

function stripeEvidence({demoPublished = false, transactions = []} = {}) {
  return {stripe_providers: [{id: 8, code: "stripe",
    is_live: false, is_published: true}],
  demo_providers: [{id: 7, code: "demo",
    is_published: demoPublished}], transactions};
}

test("CARTE : fixture séparée, 2 postes fictifs, 898 HT / 1077,60 TTC", () => {
  assert.notEqual(PREPARED.reference, oldFixture().prepared.reference);
  assert.equal(PREPARED.paymentMethod, "card");
  assert.equal(PREPARED.expectedUntaxedCents, 89800);
  assert.equal(PREPARED.expectedTotalCents, 107760);
  assert.equal(PREPARED.locked.adminUid, UID);
  assert.deepEqual(PREPARED.locked.stationIds, [...STATIONS].sort());
  const entries = cardRecords().entries;
  assert.equal(entries.length, 8);
  assert.ok(entries.every((row) => row[2].testOnly === true));
  assert.equal(entries.some((row) =>
    row[0] === "adminOdooEngagementEvidence"), false);
  assert.equal(entries.find((row) =>
    row[0] === "adminOdooFixtureManifests")[2].paymentMethod, "card");
});

test("CARTE : prévol initial sans aucune écriture", async () => {
  const h = harness();
  const result = await runCardCycle({db: h.db, odooClient: h.odooClient,
    database: CHECKOUT_TEST_DATABASE});
  assert.equal(result.nextGate, "SEED_FIRESTORE_C4_TEST");
  assert.equal(result.expectedTtcCents, 107760);
  assert.equal(h.calls.some((r) =>
    ["create", "transaction", "odoo"].includes(r[0])), false);
});

test("CARTE : ni base PROD ni Firestore historique ni émulateur", async () => {
  const h = harness();
  h.db.projectId = "sphot-ab80b";
  await assert.rejects(runCardCycle({db: h.db,
    odooClient: h.odooClient, database: CHECKOUT_TEST_DATABASE}),
  /DESTINATION_TEST_ONLY/);
  h.db.projectId = TEST_PROJECT_ID;
  await assert.rejects(runCardCycle({db: h.db,
    odooClient: h.odooClient, database: "production"}),
  /DESTINATION_TEST_ONLY/);
  await withEnv({FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"},
      async () => assert.rejects(runCardCycle({db: h.db,
        odooClient: h.odooClient, database: CHECKOUT_TEST_DATABASE}),
      /DESTINATION_TEST_ONLY/));
});

test("CARTE : seed interdit sans consentement explicite", async () => {
  const h = harness();
  await assert.rejects(seedCardFixture(h.db), /TEST_FIRESTORE_ONLY/);
  await withEnv(TEST_WRITE_ENV, async () => {
    await assert.rejects(seedCardFixture(h.db),
        /SEED_EXPLICIT_OPT_IN_REQUIRED/);
  });
  assert.equal(h.docs.size, 0);
  assert.equal(h.calls.some((x) => x[0] === "transaction"), false);
});

test("CARTE : seed C4 atomique, idempotent et sans preuve publique", async () => {
  const h = harness();
  await withEnv({...TEST_WRITE_ENV,
    SPHOT_ADMIN_TEST_CARD_SEED: "true"}, async () => {
    const first = await seedCardFixture(h.db);
    assert.equal(first.action, "seeded");
    assert.equal(first.documentCount, 8);
    assert.equal(h.docs.size, 8);
    const second = await seedCardFixture(h.db);
    assert.equal(second.action, "none");
    assert.equal(h.docs.size, 8);
    h.docs.get("adminRequests/" + UID).structure.siret = "99999999999999";
    await assert.rejects(seedCardFixture(h.db), /FIXTURE_COLLISION/);
  });
});

test("CARTE : facture Odoo impossible sans opt-in, aucun RPC", async () => {
  const h = harness(true);
  await assert.rejects(runCardCycle({db: h.db,
    odooClient: h.odooClient, database: CHECKOUT_TEST_DATABASE,
    mode: "invoice"}), /INVOICE_EXPLICIT_OPT_IN_REQUIRED/);
  assert.equal(h.calls.some((row) => row[0] === "odoo"), false);
});

test("CARTE : facture distincte créée uniquement sur fixture vérifiée", async () => {
  const h = harness(true);
  const c = checkout(null);
  let calls = 0;
  c.client.status = async () => {
    calls++; return calls >= 2 ? unPaidStatus() : null;
  };
  await withEnv({SPHOT_ADMIN_TEST_CARD_INVOICE: "true",
    SPHOT_ADMIN_TEST_ODOO_WRITES: "true",
    SPHOT_ADMIN_TEST_ODOO_DATABASE: CHECKOUT_TEST_DATABASE}, async () => {
    const result = await runCardCycle({db: h.db,
      odooClient: h.odooClient, database: CHECKOUT_TEST_DATABASE,
      mode: "invoice", checkoutFactory: c.factory});
    assert.equal(result.action, "created");
    assert.equal(result.expectedHtCents, 89800);
    assert.equal(result.expectedTtcCents, 107760);
    assert.equal(result.firestoreActivationAttempted, false);
    assert.deepEqual(c.used.filter((x) => x !== "status"),
        ["draft", "invoice"]);
  });
  assert.equal(h.calls.some((row) => row[0] === "transaction"), false);
});

test("CARTE : Stripe Démo publié bloque le passage au paiement", async () => {
  const h = harness(true);
  const c = checkout(unPaidStatus(), stripeEvidence({demoPublished: true}));
  const result = await runCardCycle({db: h.db, odooClient: h.odooClient,
    database: CHECKOUT_TEST_DATABASE,
    mode: "stripe", checkoutFactory: c.factory});
  assert.deepEqual(result.blockers, ["DEMO_PROVIDER_MUST_BE_UNPUBLISHED"]);
  assert.equal(result.nextGate, "ODOO_TEST_PAYMENT_CONFIGURATION");
  assert.equal(h.calls.some((row) => row[0] === "transaction"), false);
});

test("CARTE : Stripe TEST seul et sans transaction donne un feu vert de prévol", async () => {
  const h = harness(true);
  const c = checkout(unPaidStatus(), stripeEvidence());
  const result = await runCardCycle({db: h.db, odooClient: h.odooClient,
    database: CHECKOUT_TEST_DATABASE, checkoutFactory: c.factory});
  assert.deepEqual(result.blockers, []);
  assert.equal(result.nextGate, "STRIPE_TEST_PAYMENT_IN_ODOO_UI");
  assert.equal(result.paymentStatus, "not_paid");
  assert.equal(result.transactionCount, 0);
});

test("CARTE : activation bloquée avant preuve Stripe et sans opt-in", async () => {
  const h = harness(true);
  const c = checkout(unPaidStatus(), stripeEvidence());
  await assert.rejects(runCardCycle({db: h.db, odooClient: h.odooClient,
    database: CHECKOUT_TEST_DATABASE, mode: "activate",
    checkoutFactory: c.factory}), /TEST_FIRESTORE_ONLY/);
  await withEnv({...TEST_WRITE_ENV,
    SPHOT_ADMIN_TEST_CARD_ACTIVATE: "true"}, async () => {
    await assert.rejects(runCardCycle({db: h.db,
      odooClient: h.odooClient, database: CHECKOUT_TEST_DATABASE,
      mode: "activate", checkoutFactory: c.factory}), /STRIPE_NOT_PROVEN/);
  });
  assert.equal(h.calls.some((row) => row[0] === "transaction"), false);
});

test("CARTE : paiement en cours ne donne aucun droit", async () => {
  const h = harness(true);
  const pending = unPaidStatus();
  pending.invoice.payment_state = "in_payment";
  const c = checkout(pending, stripeEvidence());
  const result = await runCardCycle({db: h.db, odooClient: h.odooClient,
    database: CHECKOUT_TEST_DATABASE, checkoutFactory: c.factory});
  assert.equal(result.nextGate, "ODOO_RECONCILIATION_PENDING");
  assert.equal(result.stripeVerified, false);
  assert.equal(h.calls.some((row) => row[0] === "transaction"), false);
});

test("CARTE : aucun déclenchement Stripe, déploiement ou write PROD dans le script", () => {
  const source = fs.readFileSync(path.resolve(__dirname,
      "../local/odoo_admin_card_test_cycle.js"), "utf8");
  assert.doesNotMatch(source, /stripe\.PaymentIntent\.create|payment\.transaction.*create/);
  assert.match(source, /SPHOT_ADMIN_TEST_CARD_SEED/);
  assert.match(source, /SPHOT_ADMIN_TEST_CARD_INVOICE/);
  assert.match(source, /SPHOT_ADMIN_TEST_CARD_ACTIVATE/);
  assert.match(source, /readC4Credentials\(\)/);
});
