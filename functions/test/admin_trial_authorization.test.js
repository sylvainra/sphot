/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {TRIAL_SOURCE, authorizeTrial, endpoint} =
    require("../admin_trial_authorization");

const ID = "admin_trial_request_001";
const TERRITORY = "fr_test_commune_001";
const SIREN = "216301234";
const SIRET = `${SIREN}00012`;
const SA = `sphot-super-admin-${"a".repeat(32)}`;
const NOW = new Date("2026-10-31T12:00:00Z");

function token() {
  return {uid: SA, role: "SPHOT_SUPER_ADMIN", sphotSuperAdmin: true,
    sphotSaSessionExpiresAt: NOW.getTime() + 3600000};
}

function seed() {
  const locality = {pays: "France", region: "Auvergne-Rhône-Alpes",
    departement: "Puy-de-Dôme", ville: "TEST"};
  const requestFingerprint = crypto.createHash("sha256")
      .update(JSON.stringify({requestId: ID, territoryId: TERRITORY,
        siren: SIREN, siret: SIRET, locality}))
      .digest("hex");
  return new Map([
    [`adminRequests/${ID}`, {uid: ID, status: "approved",
      profile: {email: "contact@example.invalid"},
      structure: {siren: SIREN, siret: SIRET},
      territoire: {territoireId: TERRITORY, ...locality},
      trialRequestStatus: "pending", trialRequest: {
        trialDurationDays: 8, certifyRepresentative: true,
        legalReadConfirmed: true, privacyReadConfirmed: true,
        rgpdAccepted: true,
        acceptedDocuments: {version: "SPHOT-TEST-V1", cgu: true,
          privacy: true, rgpd: true, acceptedAt: new Date(NOW)}},
      trialTracking: {status: "pending"}}],
    [`admins/${ID}`, {uid: ID, accessStatus: "approved",
      territoireId: TERRITORY}],
    [`subscriptions/${ID}`, {adminUid: ID,
      status: "awaiting_configuration", numberOfRescueStations: 2}],
    [`adminOdooReviewEvidence/${ID}`, {source: "server_review_archive",
      status: "approved", adminUid: ID, territoireId: TERRITORY,
      verifiedSuperAdminReview: true, siren: SIREN, siret: SIRET,
      requestFingerprint,
      reviewedByUid: SA, reviewedAt: new Date(NOW),
      superAdminChecks: {locality: true, siren: true, siret: true}}],
  ]);
}

function fakeDb() {
  const entries = seed();
  const writes = [];
  const db = {entries, writes,
    collection(name) {return {doc(id) {return {key: `${name}/${id}`};}};},
    async runTransaction(callback) {
      const queued = [];
      const tx = {
        async get(ref) {return {exists: entries.has(ref.key),
          data: () => entries.get(ref.key)};},
        update(ref, data) {queued.push({key: ref.key, data, type: "update"});},
        set(ref, data) {queued.push({key: ref.key, data, type: "set"});},
        create(ref, data) {queued.push({key: ref.key, data, type: "create"});},
      };
      const result = await callback(tx);
      for (const op of queued) {
        if (op.type === "create" && entries.has(op.key)) {
          throw new Error("DUPLICATE_CREATE");
        }
        const data = {...entries.get(op.key)};
        for (const [key, value] of Object.entries(op.data)) {
          if (key.includes(".")) {
            const [a, b] = key.split(".");
            data[a] = {...(data[a] || {}), [b]: value};
          } else data[key] = value;
        }
        entries.set(op.key, data);
        writes.push(op);
      }
      return result;
    },
  };
  return db;
}

function start(db, extra = {}) {
  return authorizeTrial({db, requestId: ID, token: token(), now: NOW,
    fieldValue: {serverTimestamp: () => new Date(NOW)}, ...extra});
}

test("Essai ADMIN : 8 jours uniquement après contrôle Super Admin", async () => {
  const db = fakeDb();
  const result = await start(db);
  assert.equal(result.action, "started");
  assert.equal(db.writes.length, 4);
  const sub = db.entries.get(`subscriptions/${ID}`);
  assert.equal(sub.status, "trial");
  assert.equal((sub.trialEndDate - sub.trialStartDate) / 86400000, 8);
  assert.equal(sub.odooAdminCycleRef, undefined);
  assert.equal(sub.lastPaymentDate, undefined);
  assert.equal(db.entries.get(`admins/${ID}`).diffusionAccessGranted, true);
  const trial = db.entries.get(`adminTrialAuthorizations/${ID}`);
  assert.equal(trial.source, TRIAL_SOURCE);
  assert.equal(trial.authorizedByUid, SA);
});

test("Essai ADMIN : reprise idempotente sans second essai", async () => {
  const db = fakeDb();
  await start(db);
  const again = await start(db);
  assert.equal(again.reason, "trial_already_authorized");
  assert.equal(db.writes.length, 4);
});

test("Essai ADMIN : absence de preuve initiale bloquante", async () => {
  const db = fakeDb();
  db.entries.delete(`adminOdooReviewEvidence/${ID}`);
  await assert.rejects(start(db), /TRIAL_ADMIN_RECORDS_MISSING/);
  assert.equal(db.writes.length, 0);
});

test("Essai ADMIN : SIRET ou territoire incohérent bloqué", async () => {
  const db = fakeDb();
  db.entries.get(`adminOdooReviewEvidence/${ID}`).siret = "11111111100012";
  await assert.rejects(start(db), /TRIAL_INITIAL_REVIEW_NOT_PROVEN/);
  assert.equal(db.writes.length, 0);
});

test("Essai ADMIN : localité modifiée après filtrage bloquante", async () => {
  const db = fakeDb();
  db.entries.get(`adminRequests/${ID}`).territoire.ville = "AUTRE COMMUNE";
  await assert.rejects(start(db), /TRIAL_INITIAL_REVIEW_NOT_PROVEN/);
  assert.equal(db.writes.length, 0);
});

test("Essai ADMIN : non demandé ne démarre pas", async () => {
  const db = fakeDb();
  db.entries.get(`adminRequests/${ID}`).trialRequestStatus = "not_requested";
  await assert.rejects(start(db), /TRIAL_REQUEST_OR_LEGAL_ACCEPTANCE_MISSING/);
  assert.equal(db.writes.length, 0);
});

test("Essai ADMIN : acceptation juridique absente bloquante", async () => {
  const db = fakeDb();
  db.entries.get(`adminRequests/${ID}`).trialRequest.rgpdAccepted = false;
  await assert.rejects(start(db), /TRIAL_REQUEST_OR_LEGAL_ACCEPTANCE_MISSING/);
  assert.equal(db.writes.length, 0);
});

test("Essai ADMIN : version des documents juridiques obligatoire", async () => {
  const db = fakeDb();
  delete db.entries.get(`adminRequests/${ID}`).trialRequest
      .acceptedDocuments.version;
  await assert.rejects(start(db), /TRIAL_REQUEST_OR_LEGAL_ACCEPTANCE_MISSING/);
  assert.equal(db.writes.length, 0);
});

test("Essai ADMIN : abonnement ou Odoo déjà actif ne régresse pas", async () => {
  for (const mutation of [{status: "active"},
    {odooAdminCycleRef: "SPHOT-ADM-TEST-REFERENCE"},
    {trialStartDate: new Date(NOW)}]) {
    const db = fakeDb();
    Object.assign(db.entries.get(`subscriptions/${ID}`), mutation);
    await assert.rejects(start(db), /TRIAL_NOT_ELIGIBLE/);
    assert.equal(db.writes.length, 0);
  }
});

test("Essai ADMIN : session Super Admin expirée bloquante", async () => {
  const db = fakeDb();
  await assert.rejects(start(db, {token: {...token(),
    sphotSaSessionExpiresAt: NOW.getTime() - 1}}),
  /SUPERADMIN_SESSION_NOT_VERIFIED/);
  assert.equal(db.writes.length, 0);
});

test("Essai ADMIN : seule la fonction serveur valide depuis Flutter", () => {
  const source = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/super_admin/widgets/super_admin_admin_workflow_panel.dart"),
  "utf8");
  const block = source.slice(source.indexOf("Future<void> _approveTrial("),
      source.indexOf("Future<void> _renewTrial("));
  assert.match(block, /SuperAdminTrialAuthorizationService\.authorize/);
  assert.doesNotMatch(block, /\.batch\(|trialStartDate|trialEndDate/);
  const helper = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/super_admin/services/super_admin_trial_authorization_service.dart"),
  "utf8");
  assert.match(helper, /SPHOT_ADMIN_TRIAL_AUTHORIZATION_URL/);
  assert.doesNotMatch(helper, /sphot-ab80b\.cloudfunctions\.net/);
});

test("Essai ADMIN : endpoint refuse sans bearer Firebase", async () => {
  const db = fakeDb();
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => new Date(NOW)};
  const admin = {firestore, auth: () => ({
    async verifyIdToken(header, revoke) {
      assert.equal(header, "token_ok");
      assert.equal(revoke, true);
      return {...token(), sphotSaSessionExpiresAt: Date.now() + 3600000};
    },
  })};
  const route = endpoint({admin, onRequest: (_, handler) => handler});
  const response = () => ({statusCode: 200, body: null,
    set() {return this;}, status(code) {this.statusCode = code; return this;},
    json(body) {this.body = body; return this;},
    send(body) {this.body = body; return this;}});
  const rejected = response();
  await route({headers: {}, method: "POST", body: {requestId: ID}}, rejected);
  assert.equal(rejected.statusCode, 401);
  assert.equal(db.writes.length, 0);
});
