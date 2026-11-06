/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {assertReviewer, reviewTerms, approveInitialRequest, endpoint} =
  require("../admin_initial_approval");

const UID = "admin_valid_request_001";
const REVIEWER = `sphot-super-admin-${"a".repeat(32)}`;
const NOW = Date.parse("2026-10-31T12:00:00Z");
const CHECKS = {locality: true, siren: true, siret: true};
const SIRET = "21630123400012";

function request() {
  return {uid: UID, status: "pending", requestNumber: "SPHOT-ADMIN-TEST",
    profile: {email: "mairie@example.invalid"},
    proConnect: {siren: "216301234", siret: SIRET},
    structure: {nom: "COLLECTIVITE DE TEST", siren: "216301234",
      siret: SIRET},
    territoire: {territoireId: "territoire_fr_test_001",
      pays: "France", region: "Auvergne-Rhône-Alpes",
      departement: "Puy-de-Dôme", ville: "VILLE FICTIVE",
      villeLat: 45.8, villeLng: 3.1, logoVille: "https://example.invalid/logo.png",
      codePostal: "63000"},
    facturation: {billingOrganisation: "COLLECTIVITE DE TEST"}};
}

function actor() {
  return {uid: REVIEWER, role: "SPHOT_SUPER_ADMIN",
    sphotSuperAdmin: true, sphotSaSessionExpiresAt: NOW + 3600000};
}

function fakeDb() {
  const entries = new Map([[`adminRequests/${UID}`, request()]]);
  const writes = [];
  const db = {
    entries, writes,
    collection(name) {
      return {doc(id) {return {key: `${name}/${id}`};}};
    },
    async runTransaction(callback) {
      const ops = [];
      const tx = {
        async get(ref) {
          return {exists: entries.has(ref.key),
            data: () => entries.get(ref.key)};
        },
        update(ref, data) {ops.push({mode: "update", key: ref.key, data});},
        set(ref, data) {ops.push({mode: "set", key: ref.key, data});},
        create(ref, data) {ops.push({mode: "create", key: ref.key, data});},
      };
      const result = await callback(tx);
      for (const op of ops) {
        if (op.mode === "create" && entries.has(op.key)) {
          throw new Error("duplicate create");
        }
        const current = entries.get(op.key) || {};
        const merged = {...current};
        for (const [key, value] of Object.entries(op.data)) {
          if (key.includes(".")) {
            const [part, child] = key.split(".");
            merged[part] = {...(merged[part] || {}), [child]: value};
          } else merged[key] = value;
        }
        entries.set(op.key, merged);
        writes.push(op);
      }
      return result;
    },
  };
  return db;
}

function send(db, options = {}) {
  return approveInitialRequest({db,
    fieldValue: {serverTimestamp: () => new Date(NOW)},
    requestId: UID, token: actor(), nowMs: NOW,
    ...options});
}

test("Première validation ADMIN : identité Super Admin bornée à 2 h", () => {
  assert.equal(assertReviewer(actor(), NOW), REVIEWER);
  assert.throws(() => assertReviewer({...actor(),
    sphotSaSessionExpiresAt: NOW - 1}, NOW),
  /SUPERADMIN_SESSION_NOT_VERIFIED/);
  assert.throws(() => assertReviewer({...actor(),
    sphotSuperAdmin: false}, NOW), /SUPERADMIN_SESSION_NOT_VERIFIED/);
  assert.throws(() => assertReviewer({...actor(),
    uid: "other_user_001"}, NOW), /SUPERADMIN_SESSION_NOT_VERIFIED/);
});

test("Première validation ADMIN : territoire et SIREN/SIRET cohérents", () => {
  const terms = reviewTerms(UID, request());
  assert.equal(terms.siren, SIRET.slice(0, 9));
  assert.equal(terms.siret, SIRET);
  assert.equal(terms.territoryId, "territoire_fr_test_001");
  assert.match(terms.sourceHash, /^[a-f0-9]{64}$/);
});

test("Première validation ADMIN : contrôles automatiques sans cases", () => {
  const terms = reviewTerms(UID, request());
  assert.equal(terms.siren, "216301234");
  const fictitious = request();
  fictitious.proConnect.siren = "01234567";
  fictitious.structure.siren = "01234567";
  fictitious.proConnect.siret = "01234567891011";
  fictitious.structure.siret = "01234567891011";
  assert.throws(() => reviewTerms(UID, fictitious),
      /ADMIN_SIREN_SIRET_TERRITORY_INVALID/);
});

test("Première validation ADMIN : SIREN faux ou localité absente bloquent", () => {
  const badSiren = request();
  badSiren.structure.siren = "123456789";
  assert.throws(() => reviewTerms(UID, badSiren),
  /IDENTITE_ADMIN_INCOHERENTE/);
  const badLocality = request();
  delete badLocality.territoire.ville;
  assert.throws(() => reviewTerms(UID, badLocality),
  /ADMIN_LOCALITY_INCOMPLETE/);
});

test("Première validation ADMIN : décision et preuve atomiques", async () => {
  const db = fakeDb();
  const result = await send(db);
  assert.equal(result.action, "approved");
  assert.equal(db.writes.length, 5);
  const archived = db.entries.get(`adminOdooReviewEvidence/${UID}`);
  assert.equal(archived.verifiedSuperAdminReview, true);
  assert.equal(archived.source, "server_review_archive");
  assert.equal(archived.reviewedByUid, REVIEWER);
  assert.deepEqual(archived.superAdminChecks, CHECKS);
  assert.deepEqual(archived.serverConsistencyChecks, CHECKS);
  assert.equal(archived.verificationMethod,
      "server_consistency_and_superadmin_decision");
  assert.equal(db.entries.get(`adminRequests/${UID}`).status, "approved");
  assert.equal(db.entries.get(`admins/${UID}`).accessStatus, "approved");
  assert.equal(db.entries.get(`territoires/territoire_fr_test_001`).villeLat, 45.8);
  assert.equal(db.entries.get(`territoires/territoire_fr_test_001`).codePostal,
      "63000");
  const subscription = db.entries.get(`subscriptions/${UID}`);
  assert.equal(subscription.status, "awaiting_configuration");
  assert.equal(subscription.trialStartDate, null);
  assert.equal(subscription.subscriptionStartDate, null);
});

test("Première validation ADMIN : ancienne identité incompatible bloquée", async () => {
  const db = fakeDb();
  db.entries.set(`admins/${UID}`, {uid: UID, accessStatus: "pending",
    siret: "99999999900012"});
  await assert.rejects(send(db), /ADMIN_ALREADY_GRANTED/);
  assert.equal(db.writes.length, 0);
});

test("Première validation ADMIN : abonnement déjà démarré bloqué", async () => {
  const db = fakeDb();
  db.entries.set(`subscriptions/${UID}`, {adminUid: UID,
    status: "awaiting_configuration", trialStartDate: new Date(NOW)});
  await assert.rejects(send(db), /ADMIN_SUBSCRIPTION_ALREADY_RUNNING/);
  assert.equal(db.writes.length, 0);
});

test("Première validation ADMIN : reprise idempotente sans écriture", async () => {
  const db = fakeDb();
  await send(db);
  const again = await send(db);
  assert.equal(again.action, "none");
  assert.equal(db.writes.length, 5);
});

test("Première validation ADMIN : dossier déjà approuvé sans preuve refusé", async () => {
  const db = fakeDb();
  db.entries.get(`adminRequests/${UID}`).status = "approved";
  await assert.rejects(send(db), /ADMIN_INITIAL_APPROVAL_NOT_READY/);
  assert.equal(db.writes.length, 0);
});

test("Première validation ADMIN : archive d'autre auteur refusée", async () => {
  const db = fakeDb();
  db.entries.set(`adminOdooReviewEvidence/${UID}`, {
    source: "server_review_archive", status: "approved",
    adminUid: UID, reviewedByUid: "someone_else", verifiedSuperAdminReview: true});
  await assert.rejects(send(db), /ADMIN_APPROVAL_ARCHIVE_CONFLICT/);
  assert.equal(db.writes.length, 0);
});

test("Première validation ADMIN : aucune validation directe depuis les deux écrans", () => {
  for (const page of ["super_admin_admin_requests_page.dart",
    "super_admin_dashboard_page.dart"]) {
    const source = fs.readFileSync(path.resolve(__dirname,
        "../../lib/web/super_admin/pages", page), "utf8");
    assert.match(source, /SuperAdminInitialApprovalService\.approve/);
  }
  const service = fs.readFileSync(path.resolve(__dirname,
      "../../lib/web/super_admin/services/super_admin_initial_approval_service.dart"),
  "utf8");
  assert.match(service, /SPHOT_ADMIN_INITIAL_APPROVAL_URL/);
  assert.match(service, /sphot-ab80b\.cloudfunctions\.net/);
  assert.match(service, /Firebase\.app\(\)\.options\.projectId != 'sphot-ab80b'/);
  assert.match(service, /endpointUrl != _productionEndpoint/);
  assert.doesNotMatch(service, /CheckboxListTile|StatefulBuilder/);
  assert.doesNotMatch(service, /'checks':/);
});

test("Accusé ADMIN : logo et marqueur identiques au mail, titre non tronqué", () => {
  const source = fs.readFileSync(path.resolve(__dirname, "../index.js"), "utf8");
  const pdf = source.slice(source.indexOf("function createAdminRequestPdf({"),
      source.indexOf("async function sendAdminAccessAcknowledgementEmail("));
  assert.match(pdf, /buildSphotMessage\(\{text: ""\}\)/);
  assert.match(pdf, /asset\.filename === "sphot_title\.png"/);
  assert.match(pdf, /asset\.filename === "fire_red_icon\.png"/);
  assert.match(pdf, /doc\.image\(mailLogo/);
  assert.match(pdf, /doc\.image\(mailFire/);
  assert.doesNotMatch(pdf, /SURVEILLER\s+•\s+PRÉSERVER\s+•\s+INFORMER/);
  assert.doesNotMatch(pdf, /roundedRect\(left, 30, contentWidth, 72/);
  assert.match(pdf, /"ADMINISTRATEUR",\s+left,\s+doc\.y/);
});

test("Première validation ADMIN : endpoint vérifie le bearer Firebase", async () => {
  const db = fakeDb();
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => new Date(NOW)};
  const admin = {firestore, auth() {
    return {async verifyIdToken(idToken, checkRevoked) {
      assert.equal(idToken, "token_de_test");
      assert.equal(checkRevoked, true);
      return {...actor(), sphotSaSessionExpiresAt: Date.now() + 3600000};
    }};
  }};
  const route = endpoint({admin, onRequest: (_, handler) => handler});
  const makeResponse = () => {
    const res = {statusCode: 200, body: null, headers: {},
      set(key, value) {this.headers[key] = value; return this;},
      status(code) {this.statusCode = code; return this;},
      json(body) {this.body = body; return this;},
      send(body) {this.body = body; return this;}};
    return res;
  };
  const withoutToken = makeResponse();
  await route({method: "POST", headers: {},
    body: {requestId: UID}}, withoutToken);
  assert.equal(withoutToken.statusCode, 401);
  assert.equal(db.writes.length, 0);
  const authenticated = makeResponse();
  await route({method: "POST", headers: {
    authorization: "Bearer token_de_test",
    origin: "https://sphot.app",
  }, body: {requestId: UID}}, authenticated);
  assert.equal(authenticated.statusCode, 200);
  assert.equal(authenticated.body.action, "approved");
  assert.equal(db.writes.length, 5);
});
