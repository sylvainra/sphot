/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {adminQuote} = require("../commercial_quote_pricing");
const {computeDiscountCents} = require("../commercial_discounts");
const {prepareAdminCheckout} =
  require("../local/odoo_admin_checkout_contract");
const {createAdminTestFirestoreSync} =
  require("../local/odoo_admin_test_firestore_sync");
const PROJECT = "sphot-c4-test-20261029";
const UID = "admin_uid_001";
const SIRET = "21630123400012";

function fixture(paymentMethod = "public_invoice") {
  const base = adminQuote({publishedVersion: 3,
    publishedPrices: [499, 399, 299, 199]}, 3);
  const quote = {...base, ...computeDiscountCents(base.amountExclTax, 10),
    fromServerPublishedCatalog: true};
  const untaxed = quote.payableExclTaxCents / 100;
  const tax = Math.round(quote.payableExclTaxCents * 0.2) / 100;
  return prepareAdminCheckout({
    adminUid: UID, requestId: UID, cycleId: "cycle_2026_001", year: 2026,
    approval: {status: "approved", adminUid: UID,
      territoireId: "territoire_001", siret: SIRET,
      siren: SIRET.slice(0, 9)},
    buyer: {verified: true, relation: "manager", siret: SIRET,
      legalName: "Commune TEST", billingEmail: "test@example.fr"},
    stations: ["station_001", "station_002", "station_003"].map(
        (spotDocumentId) => ({spotDocumentId,
          belongsToAdminTerritory: true, isRescueStation: true})),
    quote,
    fiscality: {status: "validated", calculationVerified: true,
      amountExclTax: untaxed, taxAmount: tax,
      amountInclTax: untaxed + tax, legalBasis: "TAX_TEST"},
    legalAcceptance: {verified: true, adminUid: UID,
      version: "CGV_ADMIN_TEST", acceptedAt: "2026-10-31T12:00:00Z"},
    paymentMethod, partnerId: 42,
    adminTierProductIds: [11, 12, 13, 14],
  });
}

function seed(prepared) {
  return {
    [`adminOdooReviewEvidence/${UID}`]: {
      verifiedSuperAdminReview: true, source: "server_review_archive",
      status: "approved", adminUid: UID, territoireId: "territoire_001",
      siren: SIRET.slice(0, 9), siret: SIRET,
      reviewedByUid: "super_admin_001", reviewedAt: "2026-10-30T12:00:00Z",
    },
    [`adminRequests/${UID}`]: {
      uid: UID, status: "approved", structure: {siret: SIRET,
        siren: SIRET.slice(0, 9)},
      territoire: {territoireId: "territoire_001"},
    },
    [`admins/${UID}`]: {
      uid: UID, role: "ADMIN", accessStatus: "approved",
      territoireId: "territoire_001",
    },
    [`subscriptions/${UID}`]: {
      adminUid: UID, status: "trial",
      selectedRescueStationIds: ["station_003", "station_001", "station_002"],
    },
    [`adminOdooEngagementEvidence/${prepared.reference}`]: {
      status: "verified", documentType: "purchase_order",
      signerAuthorityVerified: true, buyerSiret: SIRET,
      orderReference: prepared.reference,
      orderFingerprint: prepared.fingerprint,
      documentHash: "a".repeat(64),
      verifiedAt: "2026-10-31T12:00:00Z",
      verificationSource: "institutional_registry",
    },
  };
}

function fakeDb(prepared, projectId = PROJECT) {
  const entries = new Map(Object.entries(seed(prepared)));
  const writes = [];
  const db = {
    projectId, entries, writes,
    collection(name) {
      return {doc(id) {return {key: `${name}/${id}`};}};
    },
    async runTransaction(callback) {
      const pending = [];
      const tx = {
        async get(ref) {
          const data = entries.get(ref.key);
          return {exists: Boolean(data), data: () => data};
        },
        create(ref, value) {
          pending.push({type: "create", key: ref.key, value});
        },
        set(ref, value, options) {
          pending.push({type: "set", key: ref.key, value, options});
        },
      };
      const result = await callback(tx);
      for (const op of pending) {
        if (op.type === "create" && entries.has(op.key)) {
          throw new Error("Document déjà créé");
        }
        const previous = op.options?.merge ? entries.get(op.key) || {} : {};
        entries.set(op.key, {...previous, ...op.value});
        writes.push(op);
      }
      return result;
    },
  };
  return db;
}

function fakeClient(prepared, paid = false) {
  return {
    async status() {
      return {order: {id: 77, name: "S00077", state: "sale",
        x_sphot_reference: prepared.reference,
        x_sphot_fingerprint: prepared.fingerprint,
        client_order_ref: prepared.reference},
      invoice: paid ? {id: 88} : null};
    },
    async verifiedStripePayment() {
      if (!paid) throw new Error("Paiement Stripe non confirmé par Odoo");
      return {provider: "stripe", transactionState: "done",
        invoiceState: "posted", invoicePaymentState: "paid",
        amountResidualCents: 0,
        invoiceTotalCents: prepared.expectedTotalCents,
        orderReference: prepared.reference};
    },
  };
}

async function withTestEnv(callback) {
  const keys = ["SPHOT_ADMIN_TEST_FIRESTORE_WRITES",
    "SPHOT_ADMIN_TEST_PROJECT_ID", "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT",
    "FIRESTORE_EMULATOR_HOST"];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  process.env.SPHOT_ADMIN_TEST_FIRESTORE_WRITES = "true";
  process.env.SPHOT_ADMIN_TEST_PROJECT_ID = PROJECT;
  process.env.GCLOUD_PROJECT = PROJECT;
  process.env.GOOGLE_CLOUD_PROJECT = PROJECT;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try {
    return await callback();
  } finally {
    for (const key of keys) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
}

test("ADMIN TEST : refus absolu du projet Firebase historique", async () => {
  await withTestEnv(() => {
    const prepared = fixture();
    assert.throws(() => createAdminTestFirestoreSync({
      db: fakeDb(prepared, "sphot-ab80b"),
      checkoutClient: fakeClient(prepared),
    }), /TEST_FIRESTORE_ONLY/);
  });
});

test("ADMIN TEST : sans activation explicite, aucune écriture autorisée", () => {
  const prepared = fixture();
  const old = process.env.SPHOT_ADMIN_TEST_FIRESTORE_WRITES;
  delete process.env.SPHOT_ADMIN_TEST_FIRESTORE_WRITES;
  try {
    assert.throws(() => createAdminTestFirestoreSync({
      db: fakeDb(prepared), checkoutClient: fakeClient(prepared),
    }), /TEST_FIRESTORE_ONLY/);
  } finally {
    if (old === undefined) delete process.env.SPHOT_ADMIN_TEST_FIRESTORE_WRITES;
    else process.env.SPHOT_ADMIN_TEST_FIRESTORE_WRITES = old;
  }
});

test("ADMIN TEST : engagement vérifié ouvre les droits sans paiement", async () => {
  await withTestEnv(async () => {
    const prepared = fixture();
    const db = fakeDb(prepared);
    const writer = createAdminTestFirestoreSync({db,
      checkoutClient: fakeClient(prepared)});
    const result = await writer.activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")});
    assert.deepEqual(result, {testOnly: true, action: "activate",
      reference: prepared.reference, basis: "verified_public_commitment"});
    assert.equal(db.entries.get(`subscriptions/${UID}`).status, "active");
    assert.equal(db.entries.get(`subscriptions/${UID}`).odooAdminManaged, true);
    assert.equal(db.entries.get(`adminOdooCycles/${prepared.reference}`)
        .paymentStatus, "not_paid");
    assert.equal(db.writes.length, 4);
    assert.equal((await writer.activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")})).action, "none");
    assert.equal(db.writes.length, 4);
  });
});

test("ADMIN TEST : sans preuve initiale du Super Admin, aucune activation", async () => {
  await withTestEnv(async () => {
    const prepared = fixture();
    const db = fakeDb(prepared);
    db.entries.delete(`adminOdooReviewEvidence/${UID}`);
    await assert.rejects(createAdminTestFirestoreSync({db,
      checkoutClient: fakeClient(prepared)}).activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")}),
    /INITIAL_SUPERADMIN_REVIEW_NOT_PROVEN/);
    assert.equal(db.writes.length, 0);
  });
});

test("ADMIN TEST : un numéro d'engagement sans justificatif ne suffit pas", async () => {
  await withTestEnv(async () => {
    const prepared = fixture();
    const db = fakeDb(prepared);
    db.entries.set(`adminOdooEngagementEvidence/${prepared.reference}`,
        {status: "verified", engagementNumber: "BC-123"});
    await assert.rejects(createAdminTestFirestoreSync({db,
      checkoutClient: fakeClient(prepared)}).activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")}),
    /PUBLIC_CONTRACT_NOT_VERIFIED/);
    assert.equal(db.writes.length, 0);
  });
});

test("ADMIN TEST : carte impayée ne peut activer Firestore", async () => {
  await withTestEnv(async () => {
    const prepared = fixture("card");
    const db = fakeDb(prepared);
    await assert.rejects(createAdminTestFirestoreSync({db,
      checkoutClient: fakeClient(prepared)}).activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")}),
    /Paiement Stripe non confirmé/);
    assert.equal(db.writes.length, 0);
  });
});

test("ADMIN TEST : Stripe rapproché et facture payée ouvrent les droits", async () => {
  await withTestEnv(async () => {
    const prepared = fixture("card");
    const db = fakeDb(prepared);
    const result = await createAdminTestFirestoreSync({db,
      checkoutClient: fakeClient(prepared, true)}).activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")});
    assert.equal(result.basis, "stripe_verified");
    assert.equal(db.entries.get(`adminOdooCycles/${prepared.reference}`)
        .paymentStatus, "paid");
  });
});

test("ADMIN TEST : abonnement annulé ou lié à un autre cycle refusé", async () => {
  await withTestEnv(async () => {
    const prepared = fixture();
    const db = fakeDb(prepared);
    db.entries.get(`subscriptions/${UID}`).status = "cancelled";
    await assert.rejects(createAdminTestFirestoreSync({db,
      checkoutClient: fakeClient(prepared)}).activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")}),
    /OTHER_ACTIVE_CYCLE_PRESENT/);
    assert.equal(db.writes.length, 0);
  });
});

test("ADMIN TEST : une sélection de postes modifiée bloque l'activation", async () => {
  await withTestEnv(async () => {
    const prepared = fixture();
    const db = fakeDb(prepared);
    db.entries.get(`subscriptions/${UID}`)
        .selectedRescueStationIds = ["station_001"];
    await assert.rejects(createAdminTestFirestoreSync({db,
      checkoutClient: fakeClient(prepared)}).activate({prepared,
      activatedAt: new Date("2026-10-31T12:00:00Z")}),
    /SUBSCRIPTION_SELECTION_CHANGED/);
    assert.equal(db.writes.length, 0);
  });
});
